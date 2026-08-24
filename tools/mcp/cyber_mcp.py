#!/usr/bin/env python3
"""CYBER SUNDAY MCP server -- a zero-dependency stdio bridge between an AI agent and this Godot project.

WHAT THIS EXPOSES
-----------------
Ten tools over two completely different transports:

  1-7  cyber_catalog / cyber_audit / cyber_refs / cyber_graph / cyber_balance / cyber_list / cyber_describe
       Shell out to `godot --headless -s scripts/tools/cyber.gd`. These read the project FROM DISK and need no
       running editor. They are the agent's answer to "what does this project actually contain?" instead of
       guessing at component names, resource paths, or balance numbers.

  8-10 godot_fs_sync / godot_editor_state / godot_reveal
       Talk over a localhost TCP socket to the CYBER SUNDAY "Bridge" tab inside the OPEN EDITOR. These see what
       the headless CLI never can: the edited scene, the selection, and -- the important one -- they can tell the
       editor that a file changed on disk. Without that, the editor's stale in-memory copy of an externally
       written .tres silently wins on the user's next Ctrl+S.

WHY ZERO DEPENDENCIES
---------------------
The `mcp` PyPI package is NOT installed on this machine and must not become a requirement. MCP over stdio is just
line-delimited JSON-RPC 2.0, which the standard library covers completely (json / sys / socket / subprocess /
pathlib). A tool that needs `pip install` before it can tell you about the project is a tool that stops working.

STDOUT IS PROTOCOL-SACRED
-------------------------
Every byte on stdout must be one JSON-RPC message per line. A single stray print() corrupts the stream and the
client either desyncs or hangs. So: ALL diagnostics go to stderr via _log(), and the JSON-RPC envelope is dumped
with ensure_ascii=True so the bytes stay pure ASCII no matter what code page a Windows console hands us.

THE ~7.7 s TAX
--------------
A headless boot of this project measures ~7.7 s before the first frame -- that is per PROCESS, not per question.
It is why cyber.gd grew a --batch mode and why every CLI tool's description below tells the caller to decide what
it needs up front instead of probing one field at a time.

USAGE
-----
As an MCP server (how a client launches it):
    python "C:/Users/dalla/3D RPG/rpg/tools/mcp/cyber_mcp.py"

Smoke test (prints the resolved paths + the tool table to STDERR, then exits; stdout stays empty on purpose):
    python cyber_mcp.py --selftest

Environment overrides:
    CYBER_GODOT     path to the Godot binary   (default: C:/Users/dalla/bin/godot.cmd, then PATH lookup)
    CYBER_PROJECT   path to the project root   (default: resolved two levels up from this file)
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable

# --- protocol -----------------------------------------------------------------------------------------------

## Pinned by contract. MCP negotiates a version in `initialize`; announcing one we actually implement is the
## honest answer, and clients downgrade gracefully.
PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "cyber-sunday"
SERVER_VERSION = "1.0.0"

## JSON-RPC 2.0 error codes we actually emit.
ERR_PARSE = -32700
ERR_INVALID_REQUEST = -32600
ERR_METHOD_NOT_FOUND = -32601
ERR_INVALID_PARAMS = -32602
ERR_INTERNAL = -32603

# --- the headless CLI transport -----------------------------------------------------------------------------

## Keep these two literals in sync with scripts/tools/cyber.gd (JSON_BEGIN / JSON_END). Godot's banner plus ~20 UI
## autoloads print into stdout before our script ever gets a frame, so the payload is fenced and we slice between
## the fences rather than trying to guess where the noise ends.
SENTINEL_BEGIN = "<<<CYBER-JSON"
SENTINEL_END = "CYBER-JSON>>>"

## Path is relative to the project root -- cyber.gd is launched with an ABSOLUTE --path, and `--path .` silently
## fails on this project, so the project root is never left implicit.
CLI_SCRIPT = "scripts/tools/cyber.gd"

## Generous but finite. A cold audit walks every resource on disk; 120 s is far past the ~7.7 s boot plus the
## slowest verb, and a timeout must return a clean error rather than hanging the agent forever.
CLI_TIMEOUT_S = 120

DEFAULT_GODOT = "C:/Users/dalla/bin/godot.cmd"

# --- the editor bridge transport ----------------------------------------------------------------------------

## Written by bridge_server.gd on Start, DELETED on Stop. Its presence is not proof of a live listener (an editor
## crash strands it), which is why a refused connect gets its own message below.
HANDSHAKE_REL = ".godot/cyber_bridge.json"

## The bridge is per-call connect / one line in / one line out / close, so a socket that has not answered in a few
## seconds is dead, not slow. Short timeout, no retry loop: a retry against a stranded port just multiplies the wait.
BRIDGE_TIMEOUT_S = 5.0

## Refuse to buffer an unbounded "line" from a peer that never sends a newline.
BRIDGE_MAX_BYTES = 8 * 1024 * 1024

## The one error message worth getting right -- it is the first thing the agent sees when the user simply has not
## pressed Start, and it must say exactly which button to press rather than "connection refused".
BRIDGE_OFF_HINT = (
    "the CYBER SUNDAY Bridge tab is not running - open the CYBER SUNDAY bottom panel in the Godot editor, "
    "select the Bridge tab, and press Start."
)


def _log(message: str) -> None:
    """Diagnostics go to STDERR, always. stdout carries the JSON-RPC stream and nothing else -- see the module
    docstring. Flushed immediately so a client tailing stderr sees progress during a 7.7 s headless boot."""
    print(f"[cyber_mcp] {message}", file=sys.stderr, flush=True)


# ============================================================================================================
# Path resolution
# ============================================================================================================


def project_root() -> Path:
    """Resolve the project root WITHOUT hardcoding one machine's layout.

    This file lives at <PROJ>/tools/mcp/cyber_mcp.py, so parents[2] is the project root. CYBER_PROJECT overrides
    it for the case where the script is copied elsewhere. Resolved (not just absolute) so a symlinked checkout
    still hands Godot a real path.
    """
    override = os.environ.get("CYBER_PROJECT", "").strip().strip('"')
    if override:
        return Path(override).expanduser().resolve()
    return Path(__file__).resolve().parents[2]


def godot_binary() -> str:
    """Resolve the Godot launcher: CYBER_GODOT, else the known .cmd shim, else whatever is on PATH.

    The default is a .cmd BATCH SHIM, not an .exe. That matters for how we spawn it -- see run_cli()'s comment
    block on CreateProcess and batch files.
    """
    override = os.environ.get("CYBER_GODOT", "").strip().strip('"')
    if override:
        return override
    if Path(DEFAULT_GODOT).exists():
        return DEFAULT_GODOT
    found = shutil.which("godot")
    # Fall back to the documented default even when it is missing: run_cli() turns the resulting spawn failure
    # into a readable "not found, set CYBER_GODOT" error, which beats an empty string here.
    return found or DEFAULT_GODOT


def handshake_path() -> Path:
    return project_root() / HANDSHAKE_REL


# ============================================================================================================
# CLI transport: build args, spawn Godot, slice the fenced payload back out
# ============================================================================================================


## Characters we refuse to put on a Godot command line. This is not paranoia about the caller; it is about HOW the
## process is spawned on Windows. The launcher is a .cmd, and CreateProcess runs batch files through cmd.exe, which
## re-parses the command line with ITS OWN rules -- a rules mismatch that has produced real command-injection CVEs
## in other runtimes (the "BatBadBut" family). Python quotes list arguments with MSVCRT rules, which correctly
## protects spaces and `&`/`|` inside double quotes, but an embedded double quote can end the quoted run early and
## `%FOO%` is still expanded by cmd.exe inside quotes. None of the real arguments here (res:// paths, type names,
## substring filters, severities) ever contain these, so rejecting them costs nothing and removes the whole class.
_UNSAFE_ARG_CHARS = '"%'


def _reject_unsafe(text: str, where: str) -> str:
    """Return "" when the value is safe to pass on a command line, else a human-readable reason."""
    for ch in text:
        if ch in _UNSAFE_ARG_CHARS or ord(ch) < 0x20:
            shown = repr(ch)
            return (
                f"{where} contains the character {shown}, which cannot be passed safely through the Godot "
                f"launcher on Windows (it is a batch shim re-parsed by cmd.exe). Remove it."
            )
    return ""


def encode_arg_value(value: Any) -> str:
    """Encode one JSON argument value for cyber.gd's `--arg:<key>=<value>` form.

    cyber.gd COERCES the string it receives: "true"/"false" -> bool, "42" -> int, "1.5" -> float, else String,
    with a `str:` prefix as the verbatim-String escape hatch. So a filter of "404" would silently arrive as the
    NUMBER 404 and match nothing. Every string we send therefore gets the `str:` prefix -- including strings that
    already start with "str:", because the coercer strips exactly one prefix. Bools and numbers are sent bare so
    they land as the type the verb expects.
    """
    if isinstance(value, bool):  # must precede int: bool is a subclass of int in Python
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return "str:" + str(value)


def build_cli_args(verb: str, args: dict[str, Any]) -> list[str]:
    """Build only the USER args (everything after the bare `--`). Kept separate from the spawn so the selftest can
    exercise it without launching Godot."""
    out = [f"--verb={verb}"]
    # sorted(): the same call must always produce byte-identical argv, so selftest() can pin the exact list and a
    # dict-ordering difference between two clients can never change what Godot is asked.
    for key in sorted(args):
        out.append(f"--arg:{key}={encode_arg_value(args[key])}")
    return out


def extract_payload(stdout: str) -> tuple[Any, str]:
    """Slice the fenced JSON block out of Godot's noisy stdout. Returns (payload, error_message).

    The fence exists because ~20 autoloads and the engine banner print before our first frame. Two parse attempts,
    in order of likelihood:
      1. first BEGIN -> first END after it (the normal case),
      2. first BEGIN -> LAST END (covers a payload that happens to contain the END literal, e.g. a `refs` result
         that mentions cyber.gd's own source).
    A payload that parses is the only thing we accept; anything else is reported honestly rather than guessed at.
    """
    begin = stdout.find(SENTINEL_BEGIN)
    if begin < 0:
        return None, "no CYBER-JSON block in Godot's output"
    body_start = begin + len(SENTINEL_BEGIN)

    candidates = []
    first_end = stdout.find(SENTINEL_END, body_start)
    if first_end >= 0:
        candidates.append(first_end)
    # The `>= body_start` guard is load-bearing: rfind() searches the WHOLE string, so an END literal printed
    # before the fence ever opened (this module's own docs echoed by a tool, a `describe` of cyber.gd) would give
    # a negative-width slice and report "not valid JSON" for what is really an unterminated block.
    last_end = stdout.rfind(SENTINEL_END)
    if last_end >= body_start and last_end != first_end:
        candidates.append(last_end)
    if not candidates:
        return None, "Godot's output opened a CYBER-JSON block but never closed it (did the process die mid-print?)"

    for end in candidates:
        chunk = stdout[body_start:end].strip()
        try:
            return json.loads(chunk), ""
        except json.JSONDecodeError:
            continue
    return None, "the CYBER-JSON block did not contain valid JSON"


def _tail(text: str, lines: int = 12) -> str:
    """Last few lines of stderr, for an error message. Godot's real complaint is always at the end."""
    rows = [r for r in text.replace("\r\n", "\n").split("\n") if r.strip()]
    return "\n".join(rows[-lines:])


def _cli_error(verb: str, message: str) -> dict[str, Any]:
    """A failure raised HERE in the proxy, wearing cyber_cmds.run()'s exact five-key contract shape
    {ok, verb, data, error, warnings}.

    The point is that a caller parses ONE shape whether the verb failed inside Godot or never got there: code that
    reads result["warnings"] must not KeyError just because the launch itself is what broke.
    """
    return {"ok": False, "verb": verb, "data": None, "error": message, "warnings": []}


def _bridge_error(tool: str, message: str) -> dict[str, Any]:
    """The bridge's own wire shape is {ok, data, error} (bridge_server.gd error_response()); a failure we raise
    before ever reaching it keeps those keys and adds `tool` so the caller can tell which one it was."""
    return {"ok": False, "tool": tool, "data": None, "error": message}


def run_cli(verb: str, args: dict[str, Any]) -> tuple[Any, bool]:
    """Run one cyber.gd verb headlessly. Returns (payload, is_error).

    SPAWNING, and why it is list-form with shell=False:
    The launcher is `godot.cmd`, a batch shim. CreateProcess DOES accept .cmd/.bat directly (it detects them and
    runs them via cmd.exe), so a plain list-form spawn works and we never need shell=True -- which would hand the
    whole command line to a shell and make quoting the caller's problem. List form also means the project path's
    SPACE ("3D RPG") is quoted by Python instead of by us. Belt and braces: if the direct spawn is refused because
    the OS declines the image (WinError 193 on some shim/redirect setups), we retry through COMSPEC explicitly --
    still list-form, still no shell=True.
    """
    proj = project_root()
    if not (proj / "project.godot").is_file():
        return _cli_error(verb, (
            f"project root {proj} has no project.godot - this script expects to live at "
            f"<project>/tools/mcp/cyber_mcp.py, or set CYBER_PROJECT."
        )), True

    for key, value in args.items():
        reason = _reject_unsafe(str(key), f"argument name '{key}'")
        if reason:
            return _cli_error(verb, reason), True
        if isinstance(value, str):
            reason = _reject_unsafe(value, f"argument '{key}'")
            if reason:
                return _cli_error(verb, reason), True

    godot = godot_binary()
    # `--path <ABSOLUTE>`: `--path .` silently fails on this project. Everything after the bare `--` is a user arg
    # (OS.get_cmdline_user_args()); everything before it belongs to the engine.
    argv = [godot, "--headless", "--path", str(proj), "-s", CLI_SCRIPT, "--"] + build_cli_args(verb, args)

    # CREATE_NO_WINDOW keeps the batch shim from flashing a console window on the user's desktop every call.
    creation_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
    started = time.monotonic()
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            timeout=CLI_TIMEOUT_S,
            shell=False,  # never: see the docstring
            creationflags=creation_flags,
        )
    except subprocess.TimeoutExpired:
        return _cli_error(verb, (
            f"Godot did not finish within {CLI_TIMEOUT_S}s and was killed. A cold headless boot is ~7.7s, so "
            f"this usually means the editor is mid-reimport (retry in a few seconds) or the verb hit a very "
            f"large scan."
        )), True
    except OSError as exc:
        # WinError 193 = "%1 is not a valid Win32 application": the OS refused the batch image. Retry through the
        # command interpreter explicitly, still without shell=True.
        if os.name == "nt" and getattr(exc, "winerror", None) == 193:
            comspec = os.environ.get("COMSPEC", "cmd.exe")
            try:
                proc = subprocess.run(
                    [comspec, "/c"] + argv,
                    capture_output=True,
                    timeout=CLI_TIMEOUT_S,
                    shell=False,
                    creationflags=creation_flags,
                )
            except OSError as exc2:
                return _cli_error(verb, f"could not launch Godot ({godot}): {exc2}"), True
            except subprocess.TimeoutExpired:
                return _cli_error(verb, f"Godot did not finish within {CLI_TIMEOUT_S}s and was killed."), True
        else:
            return _cli_error(verb, (
                f"could not launch Godot ({godot}): {exc}. Set CYBER_GODOT to the Godot binary if it lives "
                f"somewhere else."
            )), True

    # Decode explicitly as UTF-8: Godot prints UTF-8 regardless of the console code page, and letting Python guess
    # the locale encoding mangles any non-ASCII resource name into mojibake (or raises).
    stdout = proc.stdout.decode("utf-8", errors="replace")
    stderr = proc.stderr.decode("utf-8", errors="replace")
    elapsed = time.monotonic() - started

    payload, parse_error = extract_payload(stdout)
    if parse_error:
        _log(f"{verb}: no usable payload after {elapsed:.1f}s (exit {proc.returncode})")
        failure = _cli_error(verb, f"{parse_error} (godot exit code {proc.returncode})")
        # The one extra key: without Godot's own last words a parse failure is unactionable ("no CYBER-JSON block"
        # says nothing about the compile error that ate the frame).
        failure["godot_stderr"] = _tail(stderr)
        return failure, True

    # cyber.gd's envelope is {"ok": bool, "results": [ <one result per command> ]}. We always ask exactly one
    # question, so hand the caller that ONE result dict -- the {ok, verb, data, error, warnings} contract shape --
    # rather than making it dig through a single-element array. Anything unexpected is passed through untouched.
    result: Any = payload
    if isinstance(payload, dict):
        results = payload.get("results")
        if isinstance(results, list) and len(results) == 1:
            result = results[0]

    ok = bool(result.get("ok", False)) if isinstance(result, dict) else False
    _log(f"{verb}: {'ok' if ok else 'FAILED'} in {elapsed:.1f}s (godot exit {proc.returncode})")
    return result, not ok


# ============================================================================================================
# Bridge transport: handshake file -> one localhost round trip
# ============================================================================================================


def read_handshake() -> tuple[dict[str, Any] | None, str]:
    """Read {"port", "token", "pid"} written by bridge_server.gd on Start. Returns (handshake, error_message)."""
    path = handshake_path()
    if not path.is_file():
        return None, f"no handshake file at {path} - {BRIDGE_OFF_HINT}"
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, f"cannot read the handshake file {path}: {exc}"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"the handshake file {path} is not valid JSON ({exc}) - press Stop then Start on the Bridge tab."
    if not isinstance(data, dict):
        return None, f"the handshake file {path} does not hold a JSON object."

    port = data.get("port")
    token = data.get("token")
    if not isinstance(port, int) or not (0 < port < 65536):
        return None, f"the handshake file {path} has no usable \"port\" - press Stop then Start on the Bridge tab."
    if not isinstance(token, str) or not token:
        return None, f"the handshake file {path} has no \"token\" - press Stop then Start on the Bridge tab."
    return data, ""


def _recv_line(sock: socket.socket) -> tuple[str, str]:
    """Read one newline-terminated line. Returns (line, error_message).

    The bridge answers with exactly one line and then closes, so a clean EOF with data already buffered is a
    perfectly good terminator -- some senders close instead of writing the trailing newline.
    """
    chunks: list[bytes] = []
    total = 0
    while True:
        try:
            chunk = sock.recv(65536)
        except socket.timeout:
            return "", f"the Bridge accepted the connection but sent no reply within {BRIDGE_TIMEOUT_S:.0f}s."
        except OSError as exc:
            return "", f"socket error while reading the Bridge reply: {exc}"
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
        if total > BRIDGE_MAX_BYTES:
            return "", "the Bridge reply exceeded the size limit and was abandoned."
        if b"\n" in chunk:
            break
    if not chunks:
        return "", "the Bridge closed the connection without replying."
    return b"".join(chunks).split(b"\n", 1)[0].decode("utf-8", errors="replace"), ""


def call_bridge(tool: str, args: dict[str, Any]) -> tuple[Any, bool]:
    """One request to the in-editor Bridge. Returns (payload, is_error).

    Transport, deliberately dumb: connect, send ONE json line, read ONE json line, close. No persistent socket, no
    heartbeat, no reconnect -- which deletes the entire stale-connection bug family. A failure here is nearly always
    "the user has not pressed Start", so every error path routes to that message instead of a raw errno.
    """
    handshake, error = read_handshake()
    if handshake is None:
        return _bridge_error(tool, error), True

    port = int(handshake["port"])
    request = json.dumps({"token": handshake["token"], "tool": tool, "args": args}, ensure_ascii=True) + "\n"

    try:
        sock = socket.create_connection(("127.0.0.1", port), timeout=BRIDGE_TIMEOUT_S)
    except ConnectionRefusedError:
        return _bridge_error(tool, (
            f"nothing is listening on 127.0.0.1:{port} even though a handshake file exists (it is stale - the "
            f"editor was closed or crashed without pressing Stop). {BRIDGE_OFF_HINT}"
        )), True
    except OSError as exc:
        return _bridge_error(tool, f"cannot reach the Bridge on 127.0.0.1:{port}: {exc}"), True

    try:
        sock.settimeout(BRIDGE_TIMEOUT_S)
        try:
            sock.sendall(request.encode("utf-8"))
        except OSError as exc:
            return _bridge_error(tool, f"could not send the request to the Bridge: {exc}"), True
        line, read_error = _recv_line(sock)
    finally:
        # The server closes its side per call; close ours unconditionally so a half-open socket can never linger.
        try:
            sock.close()
        except OSError:
            pass

    if read_error:
        return _bridge_error(tool, read_error), True
    try:
        response = json.loads(line)
    except json.JSONDecodeError:
        return _bridge_error(tool, f"the Bridge replied with something that is not JSON: {line[:400]}"), True
    if not isinstance(response, dict):
        return _bridge_error(tool, "the Bridge reply was not a JSON object."), True

    ok = bool(response.get("ok", False))
    return response, not ok


# ============================================================================================================
# The tool table
# ============================================================================================================

## Repeated verbatim in every CLI tool description. The cost is per PROCESS, not per question, and an agent that
## knows this asks for what it needs in one shot instead of a dozen chatty probes.
BOOT_COST_NOTE = (
    "COST: each call boots Godot headlessly (~7.7 s) - decide everything you need before calling, and prefer one "
    "broad call over several narrow ones."
)


def _tool(name: str, description: str, schema: dict[str, Any], handler: Callable[[dict[str, Any]], tuple[Any, bool]]) -> dict[str, Any]:
    return {"name": name, "description": description, "inputSchema": schema, "handler": handler}


def _schema(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    """Every tool gets a REAL JSON Schema. additionalProperties:false is not decoration -- validate_arguments()
    enforces it, so a typo'd argument name is an immediate error instead of a silently unfiltered result that reads
    as a confident, wrong answer."""
    return {
        "type": "object",
        "properties": properties,
        "required": required or [],
        "additionalProperties": False,
    }


def _cli(verb: str) -> Callable[[dict[str, Any]], tuple[Any, bool]]:
    return lambda args: run_cli(verb, args)


def _bridge(tool: str) -> Callable[[dict[str, Any]], tuple[Any, bool]]:
    return lambda args: call_bridge(tool, args)


def build_tools() -> list[dict[str, Any]]:
    """The ten tools. Built by a function (not a module const) so the selftest and the JSON-RPC loop share exactly
    one definition and cannot drift."""
    tools: list[dict[str, Any]] = [
        _tool(
            "cyber_catalog",
            "List the droppable components this project ACTUALLY has (class name, script/scene path, category, "
            "what it does, key @export fields). Read this before suggesting a component - it is the cure for "
            "inventing nodes that do not exist. " + BOOT_COST_NOTE,
            _schema({
                "filter": {
                    "type": "string",
                    "description": "Optional case-insensitive substring matched against the component name/category.",
                }
            }),
            _cli("catalog"),
        ),
        _tool(
            "cyber_audit",
            "Run the full project audit (disk + wiring + player-text debt + menu-sound debt) and return findings "
            "grouped by severity, with totals. The single best 'what is broken right now' call. " + BOOT_COST_NOTE,
            _schema({
                "severity": {
                    "type": "string",
                    "description": "Optional filter, e.g. \"ERROR\" to see only errors.",
                },
                "limit": {
                    "type": "integer",
                    "description": "Optional cap on the number of findings returned.",
                    "minimum": 1,
                },
            }),
            _cli("audit"),
        ),
        _tool(
            "cyber_refs",
            "Find every file that references a resource or script. Resolves BOTH res:// paths AND uid:// ids, "
            "which a plain text search misses entirely - that is the whole reason to use this instead of grep "
            "before renaming or deleting anything. " + BOOT_COST_NOTE,
            _schema({
                "path": {
                    "type": "string",
                    "description": "The res:// path whose back-references you want, e.g. res://scripts/items/item.gd",
                }
            }, ["path"]),
            _cli("refs"),
        ),
        _tool(
            "cyber_graph",
            "Build the dialogue or quest graph and, most importantly, report DANGLING TARGETS (a choice pointing "
            "at a node that does not exist, a quest step with no destination). Check the returned 'problems' "
            "array first. " + BOOT_COST_NOTE,
            _schema({
                "kind": {
                    "type": "string",
                    "enum": ["dialogue", "quests"],
                    "description": "Which graph to build.",
                },
                "path": {
                    "type": "string",
                    "description": "Optional, dialogue only: one res:// dialogue resource instead of scanning resources/dialogue/.",
                },
            }, ["kind"]),
            _cli("graph"),
        ),
        _tool(
            "cyber_balance",
            "Compute the DERIVED weapon and loot numbers a designer cannot see in the inspector (DPS, time to "
            "kill, effective range, reload economy; loot-table roll tallies) plus balance warnings such as an "
            "unknown caliber. " + BOOT_COST_NOTE,
            _schema({
                "path": {
                    "type": "string",
                    "description": "Optional res:// path to ONE weapon or loot-table resource; omit to scan resources/weapons/ + resources/loot/.",
                }
            }),
            _cli("balance"),
        ),
        _tool(
            "cyber_list",
            "Inventory the project's authored content grouped by type (items, weapons, NPCs, dialogue, quests, "
            "levels, ...). Use this to learn what exists before writing anything that references content. "
            + BOOT_COST_NOTE,
            _schema({
                "type": {
                    "type": "string",
                    "description": "Optional content type to restrict the listing to.",
                },
                "filter": {
                    "type": "string",
                    "description": "Optional case-insensitive substring matched against the entries.",
                },
            }),
            _cli("list"),
        ),
        _tool(
            "cyber_describe",
            "Dump ONE resource's authored fields - only the script-declared, saved properties, not the whole "
            "engine property set. Use it to read the real values of an .tres before changing anything. "
            + BOOT_COST_NOTE,
            _schema({
                "path": {
                    "type": "string",
                    "description": "res:// path to the resource, e.g. res://resources/weapons/Pistol.tres",
                }
            }, ["path"]),
            _cli("describe"),
        ),
        _tool(
            "godot_fs_sync",
            "Tell the OPEN Godot editor that files changed on disk, so it reloads them instead of keeping a stale "
            "in-memory copy that silently overwrites your edit on the user's next Ctrl+S. CALL THIS AFTER ANY "
            "EXTERNAL WRITE to a .tres/.tscn/.gd. Fast (no headless boot) but it needs the CYBER SUNDAY Bridge tab "
            "running in the editor.",
            _schema({
                "paths": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "res:// paths that changed. Omit or pass an empty array to trigger a full filesystem scan (slower).",
                }
            }),
            _bridge("godot_fs_sync"),
        ),
        _tool(
            "godot_editor_state",
            "Report what the user is actually looking at in the editor: the edited scene and its root, the "
            "selected nodes, and the resource open in the Inspector. Use it to ground an answer in the user's "
            "current context instead of guessing. Needs the CYBER SUNDAY Bridge tab running.",
            _schema({}),
            _bridge("godot_editor_state"),
        ),
        _tool(
            "godot_reveal",
            "Show the user something: open a resource in the Inspector and highlight it in the FileSystem dock, or "
            "select a node in the currently edited scene. Read-only - it navigates, it never edits. Needs the "
            "CYBER SUNDAY Bridge tab running.",
            _schema({
                "path": {"type": "string", "description": "res:// path of a resource to reveal."},
                "node": {"type": "string", "description": "Node path inside the edited scene to select."},
            }),
            _bridge("godot_reveal"),
        ),
    ]
    return tools


TOOLS: list[dict[str, Any]] = build_tools()
TOOLS_BY_NAME: dict[str, dict[str, Any]] = {t["name"]: t for t in TOOLS}


def public_tools() -> list[dict[str, Any]]:
    """The tools/list payload: everything except our internal handler reference."""
    return [{"name": t["name"], "description": t["description"], "inputSchema": t["inputSchema"]} for t in TOOLS]


# ============================================================================================================
# Argument validation (driven by the declared schema, so the two can never disagree)
# ============================================================================================================

_JSON_TYPE_NAMES = {
    "string": (str,),
    "integer": (int,),
    "number": (int, float),
    "boolean": (bool,),
    "array": (list,),
    "object": (dict,),
}


def normalize_arguments(schema: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    """Fold the two shapes a conforming JSON client legitimately produces into the one the verbs expect. Runs
    BEFORE validate_arguments(), so the validator only ever sees a canonical dict.

    Two rules, both of them about not rejecting a call that is actually valid:
      1. An explicit `null` for an argument means "not supplied". Model-generated tool calls fill every declared
         property and pass null for the ones they are not using; treating that as a type error would reject a
         correct call. Dropping it before the `required` check also turns a required-but-null into the honest
         "missing required argument" rather than "got NoneType".
      2. JSON has ONE number type, so 40 and 40.0 are the same value on the wire, and JSON Schema defines
         `integer` as any number with a zero fractional part. Coerce here so `limit: 40.0` is accepted AND so
         encode_arg_value() emits `--arg:limit=40` instead of `40.0` (cyber.gd's _coerce would otherwise hand the
         verb a float where the CLI form hands it an int).
    A genuinely fractional value (1.5) is left alone and validate_arguments() rejects it, which is correct.
    """
    properties: dict[str, Any] = schema.get("properties", {})
    out: dict[str, Any] = {}
    for key, value in args.items():
        if value is None:
            continue
        spec = properties.get(key)
        if (isinstance(spec, dict) and spec.get("type") == "integer"
                and isinstance(value, float) and value.is_integer()):
            value = int(value)  # is_integer() is False for inf/nan, so this can never wrap
        out[key] = value
    return out


def validate_arguments(schema: dict[str, Any], args: dict[str, Any]) -> str:
    """Check `args` against the tool's own inputSchema. Returns "" when valid, else one readable reason.

    Validating here rather than 7.7 seconds later inside Godot is the point: a missing required `path` should cost
    milliseconds, and an unknown key must be an ERROR (a silently dropped filter reads as "0 findings, all clear").
    Expects normalize_arguments() to have run first (nulls dropped, integral floats folded to int).
    """
    properties: dict[str, Any] = schema.get("properties", {})
    for name in schema.get("required", []):
        if name not in args:
            return f"missing required argument \"{name}\""
    for key, value in args.items():
        spec = properties.get(key)
        if spec is None:
            known = ", ".join(sorted(properties)) or "(none)"
            return f"unknown argument \"{key}\" - this tool accepts: {known}"
        expected = spec.get("type")
        allowed = _JSON_TYPE_NAMES.get(expected)
        if allowed is not None:
            # bool is a subclass of int in Python, so an explicit guard is needed or True passes as an integer.
            article = "an" if expected[0] in "aeiou" else "a"
            if expected in ("integer", "number") and isinstance(value, bool):
                return f"argument \"{key}\" must be {article} {expected}, got a boolean"
            if not isinstance(value, allowed):
                return f"argument \"{key}\" must be {article} {expected}, got {type(value).__name__}"
        if expected == "array":
            item_type = spec.get("items", {}).get("type")
            allowed_items = _JSON_TYPE_NAMES.get(item_type) if item_type else None
            if allowed_items is not None:
                for element in value:
                    if not isinstance(element, allowed_items):
                        return f"every entry of \"{key}\" must be a {item_type}"
        choices = spec.get("enum")
        if choices is not None and value not in choices:
            return f"argument \"{key}\" must be one of {choices}, got {value!r}"
    return ""


def call_tool(name: str, arguments: dict[str, Any]) -> tuple[Any, bool]:
    """Dispatch one tool call. Returns (payload, is_error). Never raises -- an exception here would end up as a
    protocol-level failure when it is really just a tool that could not answer."""
    tool = TOOLS_BY_NAME.get(name)
    if tool is None:
        return {
            "ok": False,
            "data": None,
            "error": f"unknown tool \"{name}\". Available: {', '.join(sorted(TOOLS_BY_NAME))}",
        }, True

    arguments = normalize_arguments(tool["inputSchema"], arguments)
    reason = validate_arguments(tool["inputSchema"], arguments)
    if reason:
        return {"ok": False, "tool": name, "data": None, "error": reason}, True

    # godot_reveal is the one tool whose schema cannot express its own rule (exactly one of path/node), so it gets
    # a hand-written check rather than being left to fail confusingly inside the editor.
    if name == "godot_reveal":
        has_path = bool(str(arguments.get("path", "")).strip())
        has_node = bool(str(arguments.get("node", "")).strip())
        if has_path == has_node:
            return {
                "ok": False,
                "tool": name,
                "data": None,
                "error": "pass exactly one of \"path\" (a res:// resource) or \"node\" (a node path in the edited scene).",
            }, True

    try:
        return tool["handler"](arguments)
    except Exception as exc:  # noqa: BLE001 - a tool must never take the server down with it
        _log(f"{name}: unhandled {type(exc).__name__}: {exc}")
        return {"ok": False, "tool": name, "data": None, "error": f"{type(exc).__name__}: {exc}"}, True


# ============================================================================================================
# JSON-RPC 2.0 over stdio
# ============================================================================================================


def _result(request_id: Any, result: Any) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def _error(request_id: Any, code: int, message: str) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def handle_request(request: Any) -> dict[str, Any] | None:
    """Turn one decoded JSON-RPC message into the response to send, or None when nothing may be sent.

    THE NOTIFICATION RULE, which is the single most common way a hand-rolled MCP server hangs its client: a message
    with NO "id" is a notification and gets NO response, ever - not a result, not an error, not an ack. Sending one
    leaves the client matching a response against a request it never made. `notifications/initialized` is the one
    every client sends immediately after `initialize`, so getting this wrong breaks the very first handshake.
    """
    if not isinstance(request, dict):
        return _error(None, ERR_INVALID_REQUEST, "request must be a JSON object")

    method = request.get("method")
    is_notification = "id" not in request
    request_id = request.get("id")

    if not isinstance(method, str) or not method:
        return None if is_notification else _error(request_id, ERR_INVALID_REQUEST, "missing \"method\"")

    params = request.get("params")
    if params is None:
        params = {}
    if not isinstance(params, dict):
        return None if is_notification else _error(request_id, ERR_INVALID_PARAMS, "\"params\" must be an object")

    if is_notification:
        # Notifications we understand still get acted on where that makes sense; they simply produce no output.
        # `notifications/cancelled` arrives when the user aborts -- our calls are synchronous, so there is nothing
        # to cancel, but it must not be answered either.
        _log(f"notification: {method}")
        return None

    if method == "initialize":
        # Echo back OUR protocol version. A client that speaks a different one negotiates or degrades; claiming
        # theirs when we do not implement it is how subtle incompatibilities start.
        return _result(request_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        })

    if method == "ping":
        return _result(request_id, {})

    if method == "tools/list":
        return _result(request_id, {"tools": public_tools()})

    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments")
        if arguments is None:
            arguments = {}
        if not isinstance(name, str) or not name:
            return _error(request_id, ERR_INVALID_PARAMS, "tools/call needs a string \"name\"")
        if not isinstance(arguments, dict):
            return _error(request_id, ERR_INVALID_PARAMS, "tools/call \"arguments\" must be an object")

        payload, is_error = call_tool(name, arguments)
        # MCP convention: a tool that could not answer is a SUCCESSFUL rpc carrying isError - not a JSON-RPC error.
        # That keeps "the Bridge is not running" as something the model reads and acts on, instead of a transport
        # failure the client may hide or retry.
        text = json.dumps(payload, ensure_ascii=True, indent=None, default=str)
        return _result(request_id, {"content": [{"type": "text", "text": text}], "isError": is_error})

    return _error(request_id, ERR_METHOD_NOT_FOUND, f"unknown method \"{method}\"")


def serve(stdin: Any = None, stdout: Any = None) -> int:
    """The stdio loop: one JSON object per line in, at most one JSON object per line out."""
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout

    _log(f"ready - project {project_root()} - godot {godot_binary()} - {len(TOOLS)} tools")
    while True:
        try:
            line = stdin.readline()
        except (KeyboardInterrupt, EOFError):
            break
        except Exception as exc:  # noqa: BLE001 - a broken pipe on stdin ends the session, it is not a crash
            _log(f"stdin read failed: {type(exc).__name__}: {exc}")
            break
        if line == "":  # EOF: the client went away
            break
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            # A parse error has no id to correlate with, so JSON-RPC says answer with id null. It is still a
            # response (never silence) so a client that DID send a request is not left waiting forever.
            _write(stdout, _error(None, ERR_PARSE, f"invalid JSON: {exc}"))
            continue

        try:
            response = handle_request(request)
        except Exception as exc:  # noqa: BLE001 - the loop must outlive any single bad request
            _log(f"unhandled {type(exc).__name__} handling a request: {exc}")
            rid = request.get("id") if isinstance(request, dict) else None
            response = None if (isinstance(request, dict) and "id" not in request) else _error(
                rid, ERR_INTERNAL, f"{type(exc).__name__}: {exc}")

        if response is not None:
            _write(stdout, response)

    _log("stdin closed - exiting")
    return 0


def _write(stream: Any, message: dict[str, Any]) -> None:
    """One message, one line, flushed. ensure_ascii=True keeps the bytes pure ASCII whatever code page a Windows
    console is using -- a UnicodeEncodeError here would kill the session over a resource name with an accent."""
    try:
        stream.write(json.dumps(message, ensure_ascii=True, default=str) + "\n")
        stream.flush()
    except Exception as exc:  # noqa: BLE001
        _log(f"could not write a response: {type(exc).__name__}: {exc}")


# ============================================================================================================
# Entry point + smoke test
# ============================================================================================================


def selftest() -> int:
    """`python cyber_mcp.py --selftest` -- prints the resolved environment and the tool table to STDERR and exits.

    STDOUT STAYS EMPTY on purpose: this is the same binary a client launches as a protocol server, and a smoke test
    that printed to stdout would teach exactly the wrong habit. Returns a non-zero exit code if a pure-logic check
    fails, so it is usable as a CI gate.
    """
    proj = project_root()
    godot = godot_binary()
    _log("--- environment ---")
    _log(f"project root      : {proj}  (project.godot present: {(proj / 'project.godot').is_file()})")
    _log(f"cyber.gd          : {proj / CLI_SCRIPT}  (present: {(proj / CLI_SCRIPT).is_file()})")
    _log(f"godot binary      : {godot}  (present: {Path(godot).exists()})")
    _log(f"handshake file    : {handshake_path()}  (present: {handshake_path().is_file()})")
    _log(f"python            : {sys.version.split()[0]}")

    _log("--- tools ---")
    for tool in TOOLS:
        required = tool["inputSchema"].get("required", [])
        props = ", ".join(sorted(tool["inputSchema"].get("properties", {}))) or "-"
        _log(f"{tool['name']:<20} args: {props:<20} required: {required}")

    failures: list[str] = []

    # Pure-logic checks: everything here runs without a socket, without Godot, and without an editor.
    if json.loads(json.dumps({"tools": public_tools()}))["tools"][0]["name"] != TOOLS[0]["name"]:
        failures.append("tools/list payload did not survive a JSON round trip")

    sample = "Godot Engine v4.7.1 banner\nsome autoload noise\n" + SENTINEL_BEGIN + "\n" + \
        json.dumps({"ok": True, "results": [{"ok": True, "verb": "catalog", "data": [1, 2], "error": "", "warnings": []}]}) + \
        "\n" + SENTINEL_END + "\ntrailing noise\n"
    payload, error = extract_payload(sample)
    if error or not isinstance(payload, dict) or payload.get("ok") is not True:
        failures.append(f"extract_payload failed on a well-formed sample: {error}")
    if extract_payload("no fence here at all")[1] == "":
        failures.append("extract_payload accepted output with no fence")

    args = build_cli_args("audit", {"severity": "ERROR", "limit": 40})
    if args != ["--verb=audit", "--arg:limit=40", "--arg:severity=str:ERROR"]:
        failures.append(f"build_cli_args produced {args}")
    if encode_arg_value("404") != "str:404":
        failures.append("a numeric-looking string must be sent with the str: prefix or cyber.gd coerces it to a number")
    if encode_arg_value(True) != "true" or encode_arg_value(7) != "7":
        failures.append("bool/int encoding is wrong")

    # The notification rule, checked explicitly because it is the classic client-hanging bug.
    if handle_request({"jsonrpc": "2.0", "method": "notifications/initialized"}) is not None:
        failures.append("a notification (no id) must produce NO response")
    if handle_request({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}) is None:
        failures.append("initialize must produce a response")
    unknown = handle_request({"jsonrpc": "2.0", "id": 2, "method": "no/such/method"})
    if not unknown or unknown.get("error", {}).get("code") != ERR_METHOD_NOT_FOUND:
        failures.append("an unknown method must answer -32601")
    listed = handle_request({"jsonrpc": "2.0", "id": 3, "method": "tools/list"})
    if not listed or len(listed["result"]["tools"]) != len(TOOLS):
        failures.append("tools/list did not return every tool")

    # Argument normalisation, checked WITHOUT handle_request() so no branch of this can launch Godot.
    audit_schema = TOOLS_BY_NAME["cyber_audit"]["inputSchema"]
    if normalize_arguments(audit_schema, {"limit": 40.0}) != {"limit": 40}:
        failures.append("an integer sent as 40.0 must fold to 40 (JSON has one number type)")
    if normalize_arguments(audit_schema, {"severity": None}) != {}:
        failures.append("an explicit null for an optional argument must be treated as \"not supplied\"")
    if validate_arguments(audit_schema, normalize_arguments(audit_schema, {"limit": 1.5})) == "":
        failures.append("a fractional value for an integer argument must still be rejected")
    refs_schema = TOOLS_BY_NAME["cyber_refs"]["inputSchema"]
    if "missing required" not in validate_arguments(refs_schema, normalize_arguments(refs_schema, {"path": None})):
        failures.append("a required argument sent as null must read as missing, not as a type error")

    # Every failure this module raises itself must wear the same five-key shape a real result does, so a caller
    # never has to branch on where the failure happened.
    for key in ("ok", "verb", "data", "error", "warnings"):
        if key not in _cli_error("audit", "boom"):
            failures.append(f"_cli_error() is missing the contract key \"{key}\"")

    # A required arg missing must fail in milliseconds, not after a 7.7 s boot.
    started = time.monotonic()
    refs = handle_request({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                           "params": {"name": "cyber_refs", "arguments": {}}})
    if not refs or refs["result"]["isError"] is not True:
        failures.append("cyber_refs without \"path\" must be an isError result")
    if time.monotonic() - started > 2.0:
        failures.append("a missing required argument was not caught before launching Godot")
    reveal = handle_request({"jsonrpc": "2.0", "id": 5, "method": "tools/call",
                             "params": {"name": "godot_reveal", "arguments": {"path": "res://a.tres", "node": "Root"}}})
    if not reveal or reveal["result"]["isError"] is not True:
        failures.append("godot_reveal with BOTH path and node must be rejected")

    _log("--- checks ---")
    if failures:
        for f in failures:
            _log(f"FAIL: {f}")
        return 1
    _log(f"PASS: {len(TOOLS)} tools, framing / arg-encoding / JSON-RPC notification rules all behave.")
    return 0


def main(argv: list[str]) -> int:
    # Line-delimited protocol on a Windows box: force UTF-8 both ways and stop the "\n" -> "\r\n" translation that
    # would otherwise put a stray carriage return inside every protocol line.
    for stream, kwargs in ((sys.stdin, {"errors": "replace"}),
                           (sys.stdout, {"newline": "\n"}),
                           (sys.stderr, {"errors": "replace"})):
        try:
            stream.reconfigure(encoding="utf-8", **kwargs)
        except Exception:  # noqa: BLE001 - a stream that cannot be reconfigured (a pipe wrapper) still works
            pass

    if "--selftest" in argv:
        return selftest()
    if "--help" in argv or "-h" in argv:
        _log(__doc__ or "")
        return 0
    if len(argv) > 0:
        _log(f"ignoring unrecognised arguments: {argv} (this program takes only --selftest or --help)")

    try:
        return serve()
    except KeyboardInterrupt:
        _log("interrupted")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
