@tool
extends RefCounted

## The editor-side command server behind the CYBER SUNDAY "Bridge" tab (dock_bridge/bridge_view.gd owns it and is
## the ONLY thing that starts it). An external process — the MCP server at tools/mcp/cyber_mcp.py — can already read
## this project headlessly (scripts/tools/cyber.gd), but a headless boot cannot see the OPEN EDITOR: which scene is
## being edited, what is selected, and above all it cannot tell the editor that a file it just wrote on disk has
## changed. Until the editor happens to rescan, its stale in-memory copy silently wins on the next Ctrl+S. This
## server closes exactly that gap, with three READ-ONLY tools and nothing else.
##
## NOT A NODE, ON PURPOSE. The owning tab drives it: it calls poll() from its own _process while listening, and
## calls stop() from _exit_tree. That keeps the lifetime pinned to a Control the user can see, instead of a
## free-floating Node that could outlive the panel across a plugin reload.
##
## THE SECURITY POSTURE — every line of it is load-bearing, do not "simplify" any of these away:
##  1. The listener binds "127.0.0.1" EXPLICITLY. TCPServer.listen()'s DEFAULT bind address is "*" — every
##     interface, i.e. the whole LAN. An unauthenticated command channel into a game editor reachable from the
##     network is a remote-code-execution surface, not a convenience. If you ever see BIND_ADDRESS removed or
##     replaced with "*", that is the bug.
##  2. Every request must carry the token from the handshake file. The token is CRYPTO random
##     (Crypto.generate_random_bytes) — never randi()/seeded RNG, whose output a local process can predict, which
##     would defeat the point of having a token at all.
##  3. The server is OFF unless the user pressed Start (that policy lives in the tab; this file just never
##     self-starts).
##  4. A request line is size-capped, so a chatty or hostile client cannot grow the editor's memory by never
##     sending a newline.
##
## THE TRANSPORT — one connection = one JSON line in, one JSON line out, then close. No persistent connection, no
## heartbeat, no reconnect logic. That deliberately deletes the entire stale-connection bug family (half-open
## sockets, a client that reconnects while the editor reloads the plugin, a dead peer held forever). Reads are
## non-blocking: a peer that has not delivered a whole line yet stays in a small pending list with a ~2 s deadline
## and is dropped when it expires, so poll() ALWAYS returns promptly and can never stall the editor's frame.
##
## FAIL LOUD ON A BUSY PORT. start() returns the error string and stays off. It must never silently try port+1:
## the external proxy reads the port from the handshake file exactly once per call, and a silent fallback is how
## comparable Unity/Unreal bridges end up talking to a dead listener forever with no visible failure.
##
## TESTABLE SURFACE (tests/test_cyber_bridge.gd) — the parse/auth/response-shape logic is PURE and static, callable
## with no socket and no EditorInterface: parse_request(), validate_request(), ok_response(), error_response(),
## encode_response(), handshake_payload(), summarize(). The three tool handlers below DO need EditorInterface (which
## only exists in an editor session) and are therefore instance methods, kept clearly separate from the statics.

## Emitted once per served (or rejected) request so the tab can show a live audit trail of what the open port did.
signal request_served(tool_name: String, ok: bool, detail: String)

## Default listening port. A dev-tool port is not a gameplay number (see CLAUDE.md) — a plain const is correct.
const DEFAULT_PORT := 8975
## Localhost only. See posture note 1 in the header: this is NOT a default we inherit, we pass it explicitly.
const BIND_ADDRESS := "127.0.0.1"
## The handshake lives in the engine's own cache dir: already git-ignored, already per-machine, and it disappears
## with the rest of .godot/ if the user nukes the cache — exactly the lifetime a transient port+token wants.
const HANDSHAKE_PATH := "res://.godot/cyber_bridge.json"

## 16 bytes of crypto randomness -> 32 hex chars. Long enough that guessing is hopeless, short enough to eyeball
## against an MCP error message.
const TOKEN_BYTES := 16
## How long a connected peer may take to deliver its one complete line before it is dropped.
const PEER_TIMEOUT_MS := 2000
## Work budgets per editor frame. The bridge must never be able to monopolise the editor's main loop.
const MAX_ACCEPTS_PER_POLL := 4
const MAX_SERVES_PER_POLL := 4
## Hard cap on one request line. A client that never sends "\n" gets dropped instead of growing the buffer forever.
const MAX_REQUEST_BYTES := 65536
## Byte value of "\n" — the request/response frame delimiter.
const NEWLINE_BYTE := 10
## How much of a served payload is echoed into the tab's log row.
const LOG_DETAIL_CHARS := 140

const TOOL_FS_SYNC := "godot_fs_sync"
const TOOL_EDITOR_STATE := "godot_editor_state"
const TOOL_REVEAL := "godot_reveal"
## The COMPLETE served surface. validate_request() rejects anything not on this list, so an unknown tool never
## reaches the editor-touching code at all.
const TOOLS: Array[String] = [TOOL_FS_SYNC, TOOL_EDITOR_STATE, TOOL_REVEAL]

var _server: TCPServer = null
var _port := 0
var _token := ""
## Peers that have connected but not yet delivered a full line: [{"peer": StreamPeerTCP, "buf": PackedByteArray,
## "deadline": int msec}]. Bounded in practice by the per-frame accept budget plus the drop deadline.
var _pending: Array[Dictionary] = []


# --- lifetime ----------------------------------------------------------------------------------------------------

## Open the listener and write the handshake file. Returns "" on success, else a human-readable error (the tab
## shows it verbatim). NEVER falls back to another port — see the FAIL LOUD note in the header.
func start(port: int = DEFAULT_PORT) -> String:
	if is_listening():
		return "The Bridge is already listening on %s:%d." % [BIND_ADDRESS, _port]
	if port < 1 or port > 65535:
		return "Port %d is out of range (1-65535)." % port

	var srv := TCPServer.new()
	# The second argument is the whole security posture: without it TCPServer binds "*" (every interface).
	var err := srv.listen(port, BIND_ADDRESS)
	if err != OK:
		return "Couldn't bind %s:%d — %s. Something else owns that port (often a Bridge from a previous editor session that wasn't stopped). Pick another port and press Start again." % [
			BIND_ADDRESS, port, error_string(err)]

	_server = srv
	_port = srv.get_local_port()  # ask the socket what it actually got, never assume the requested number
	_token = _new_token()

	var werr := _write_handshake()
	if werr != "":
		# A listener no client can address is precisely the silent-failure family this design exists to delete, so
		# a handshake we couldn't write is a FAILED start — unwind the socket rather than leave a ghost port open.
		stop()
		return werr
	return ""


## Close the listener, drop every pending peer, and DELETE the handshake file. Idempotent: the tab calls it from
## _exit_tree AND from NOTIFICATION_PREDELETE, and the user toggles this plugin off/on dozens of times a day.
func stop() -> void:
	for entry in _pending:
		var peer: StreamPeerTCP = entry.get("peer")
		if peer != null:
			peer.disconnect_from_host()
	_pending.clear()
	if _server != null:
		_server.stop()
		_server = null
	_port = 0
	_token = ""
	_delete_handshake()


func is_listening() -> bool:
	return _server != null and _server.is_listening()


## The port actually bound (0 while off). The tab displays this; the MCP proxy reads it from the handshake file.
func port() -> int:
	return _port


## The current session's shared secret ("" while off). The tab shows only a short prefix of it on screen.
func token() -> String:
	return _token


# --- the frame pump ----------------------------------------------------------------------------------------------

## Called every editor frame by the owning tab while listening. Accepts a few connections and serves a few
## requests, then returns — it must NEVER block, because it runs on the editor's main thread.
func poll() -> void:
	if _server == null:
		return
	_accept_new_peers()
	_service_pending()


func _accept_new_peers() -> void:
	var accepted := 0
	while accepted < MAX_ACCEPTS_PER_POLL and _server.is_connection_available():
		accepted += 1
		var peer := _server.take_connection()
		if peer == null:
			continue
		peer.set_no_delay(true)  # one tiny line each way: Nagle's delay would buy nothing and cost latency
		_pending.append({
			"peer": peer,
			"buf": PackedByteArray(),
			"deadline": Time.get_ticks_msec() + PEER_TIMEOUT_MS,
		})


## Walk the pending peers BACKWARDS so a finished/dropped entry can be removed in place while iterating.
func _service_pending() -> void:
	var now := Time.get_ticks_msec()
	var served := 0
	var i := _pending.size() - 1
	while i >= 0:
		var entry: Dictionary = _pending[i]
		var peer: StreamPeerTCP = entry.get("peer")
		var finished := false

		if peer == null:
			finished = true
		else:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				# The client hung up before completing its request — nothing to answer, just let it go.
				peer.disconnect_from_host()
				finished = true
			elif served < MAX_SERVES_PER_POLL:
				if _take_line(entry):
					_serve(peer, str(entry.get("line", "")))
					peer.disconnect_from_host()  # one request per connection, by contract
					served += 1
					finished = true
				elif _buffered_size(entry) > MAX_REQUEST_BYTES:
					_respond(peer, error_response("request too large (max %d bytes on one line)" % MAX_REQUEST_BYTES))
					peer.disconnect_from_host()
					request_served.emit("(rejected)", false, "oversized request dropped")
					finished = true

		# The deadline applies to every un-finished peer, including one that was only deferred by the serve budget.
		# Without it a half-open connection would sit in this list forever.
		if not finished and int(entry.get("deadline", 0)) <= now:
			if peer != null:
				peer.disconnect_from_host()
			request_served.emit("(timeout)", false, "dropped a peer that never sent a complete line")
			finished = true

		if finished:
			_pending.remove_at(i)
		i -= 1


## Drain whatever bytes the socket already has; on success park the FIRST complete line (newline stripped) in
## entry["line"] and return true. Never blocks — it only ever reads bytes that are already buffered. Returns a
## BOOL rather than the line itself so an empty line is still "a request arrived" (it gets a proper error response)
## instead of being indistinguishable from "nothing yet".
func _take_line(entry: Dictionary) -> bool:
	var peer: StreamPeerTCP = entry.get("peer")
	if peer == null:
		return false
	# PackedByteArray is VALUE-typed (copy-on-write), so this is a COPY — it must be written back into the entry.
	var buf: PackedByteArray = entry.get("buf")
	var avail := peer.get_available_bytes()
	if avail > 0:
		var chunk: Array = peer.get_data(avail)  # exactly what is buffered, so this cannot block
		if int(chunk[0]) == OK:
			var got: PackedByteArray = chunk[1]
			buf.append_array(got)
			entry["buf"] = buf
	var nl := buf.find(NEWLINE_BYTE)
	if nl < 0:
		return false
	# Decode ONLY the completed line. A multi-byte UTF-8 sequence can straddle two reads, so the bytes are
	# accumulated raw and converted once the terminator proves the line is whole.
	entry["line"] = buf.slice(0, nl).get_string_from_utf8()
	return true


## Bytes buffered so far for a pending peer — the guard against a client that never sends its newline.
static func _buffered_size(entry: Dictionary) -> int:
	var buf: PackedByteArray = entry.get("buf", PackedByteArray())
	return buf.size()


## Gate one request line, run it, answer it, and log it. Rejections answer with the same response shape as a
## success so the external proxy always parses one thing.
func _serve(peer: StreamPeerTCP, line: String) -> void:
	var gate := validate_request(line, _token)
	if not bool(gate.get("ok", false)):
		var msg := str(gate.get("error", "bad request"))
		_respond(peer, error_response(msg))
		# The log's tool column is a FIXED literal on this path, never the name the caller asked for. Two reasons:
		# every validate_request() failure is an error_response(), which deliberately carries no `tool` key at all;
		# and the tab paints THIS argument into a bbcode RichTextLabel while escaping only `detail`
		# (bridge_view.format_log_row), so an attacker-chosen tool name here would be markup injected straight into
		# the audit trail. The name the caller asked for still reaches the log inside `msg`, where it IS escaped.
		request_served.emit("(rejected)", false, msg)
		return
	var tool_name := str(gate.get("tool", ""))
	var args: Dictionary = gate.get("args", {})
	var resp := _dispatch(tool_name, args)
	_respond(peer, resp)
	request_served.emit(tool_name, bool(resp.get("ok", false)), summarize(resp))


func _respond(peer: StreamPeerTCP, resp: Dictionary) -> void:
	if peer == null:
		return
	# put_data blocks until the bytes are handed to the OS. Every response this server produces is ONE short line,
	# far under the loopback send buffer, so it completes immediately and the editor never stalls here. If a future
	# tool ever returns a large payload, this must become put_partial_data against the peer's deadline.
	peer.put_data(encode_response(resp).to_utf8_buffer())


# --- pure request handling (no socket, no EditorInterface — this is what the GUT test drives) ---------------------

## Decode one request line into its parts. Returns either an error_response() (malformed input) or
## {"ok": true, "data": null, "error": "", "token":, "tool":, "args":}. Never throws, never pushes an error —
## a hostile or truncated line is normal input for a socket server.
static func parse_request(line: String) -> Dictionary:
	var trimmed := line.strip_edges()  # also eats a "\r" from a CRLF client
	if trimmed == "":
		return error_response("empty request")
	# JSON.parse_string() PUSHES an engine error on malformed input. A socket server's input is arbitrary
	# bytes from another process, so a bad line is normal traffic, not an exceptional case — the noise makes
	# the docstring above a lie and fails GUT, which treats an unexpected engine error as a test failure.
	# The instanced parser reports the same condition as a return code and stays silent. Do not "simplify"
	# this back to JSON.parse_string().
	var json := JSON.new()
	if json.parse(trimmed) != OK:
		return error_response("malformed request: expected one line of JSON object")
	# Still reachable on success: a literal `null` body parses as OK with a null result.
	var parsed: Variant = json.data
	if parsed == null or not (parsed is Dictionary):
		return error_response("malformed request: expected one line of JSON object")
	var obj: Dictionary = parsed
	var raw_args: Variant = obj.get("args", {})
	if raw_args == null:
		raw_args = {}
	if not (raw_args is Dictionary):
		return error_response("malformed request: `args` must be a JSON object")
	return {
		"ok": true,
		"data": null,
		"error": "",
		"token": str(obj.get("token", "")),
		"tool": str(obj.get("tool", "")),
		"args": raw_args,
	}


## The full gate: parse, authenticate, and check the tool name against TOOLS. Same return shape as
## parse_request(); a failure is already a well-formed response dict, ready to send back.
static func validate_request(line: String, expected_token: String) -> Dictionary:
	var parsed := parse_request(line)
	if not bool(parsed.get("ok", false)):
		return parsed
	# No server token means we are not started (or mid-stop): refuse rather than accept anything. A server with no
	# secret must never be an open door.
	if expected_token == "":
		return error_response("bad token")
	# Deliberately the SAME message for "absent" and "wrong": a caller should learn nothing about the secret.
	if str(parsed.get("token", "")) != expected_token:
		return error_response("bad token")
	var tool_name := str(parsed.get("tool", ""))
	if tool_name == "":
		return error_response("missing `tool`")
	if not TOOLS.has(tool_name):
		return error_response("unknown tool: %s (known: %s)" % [tool_name, ", ".join(TOOLS)])
	return parsed


## The success half of the wire response shape.
static func ok_response(data: Variant) -> Dictionary:
	return {"ok": true, "data": data, "error": ""}


## The failure half. Every key is always present so the caller parses one shape, always.
static func error_response(message: String) -> Dictionary:
	return {"ok": false, "data": null, "error": message}


## Serialise a response for the wire. The trailing newline IS the frame delimiter the client reads to.
static func encode_response(resp: Dictionary) -> String:
	return JSON.stringify(resp) + "\n"


## The handshake file's contents: how an external process finds this editor's port and secret. `pid` lets a
## caller tell a live editor from a stale file left by a crash.
static func handshake_payload(bound_port: int, secret: String, pid: int) -> Dictionary:
	return {"port": bound_port, "token": secret, "pid": pid}


## One short log line for the tab: the error on failure, otherwise a truncated echo of the payload.
static func summarize(resp: Dictionary) -> String:
	if not bool(resp.get("ok", false)):
		return str(resp.get("error", "failed"))
	var s := JSON.stringify(resp.get("data"))
	return s if s.length() <= LOG_DETAIL_CHARS else s.substr(0, LOG_DETAIL_CHARS) + "..."


# --- handshake file ----------------------------------------------------------------------------------------------

static func _new_token() -> String:
	# Crypto, NOT randi(): a seeded/predictable token is guessable by any other local process, which would make the
	# whole auth step decorative.
	return Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()


## Returns "" on success, else the error message start() should report.
func _write_handshake() -> String:
	var f := FileAccess.open(HANDSHAKE_PATH, FileAccess.WRITE)
	if f == null:
		return "Couldn't write the handshake file %s — %s. The external tool has no way to find this port, so the Bridge stays off." % [
			HANDSHAKE_PATH, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(handshake_payload(_port, _token, OS.get_process_id())))
	f.close()
	return ""


func _delete_handshake() -> void:
	if not FileAccess.file_exists(HANDSHAKE_PATH):
		return
	var err := DirAccess.remove_absolute(HANDSHAKE_PATH)
	if err != OK:
		# Worth a warning, not silence: a stale handshake points the MCP proxy at a port nobody is listening on,
		# which is the exact confusing failure this design is built to avoid.
		push_warning("CYBER SUNDAY Bridge: couldn't delete %s (%s) — delete it by hand so no tool dials a dead port." % [
			HANDSHAKE_PATH, error_string(err)])


# --- the three tools (editor-only: these are the parts that need EditorInterface) --------------------------------
# All READ-ONLY as far as project content goes. fs_sync refreshes the editor's FILE CACHE; the other two only read
# editor state or move the user's focus. Nothing here writes a scene, a resource, or a project setting.

func _dispatch(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		TOOL_FS_SYNC:
			return _tool_fs_sync(args)
		TOOL_EDITOR_STATE:
			return _tool_editor_state()
		TOOL_REVEAL:
			return _tool_reveal(args)
	# Unreachable while validate_request() gates the name — kept so a future tool added to TOOLS but not to this
	# match fails as a clean error instead of silently answering ok with nothing.
	return error_response("unknown tool: %s" % tool_name)


## THE HIGHEST-VALUE TOOL. An external process wrote a .tres; the open editor still holds its own stale copy and
## will overwrite the file on the next Ctrl+S. update_file() re-reads that one file's metadata so the editor sees
## the new bytes; with no paths at all we fall back to a full scan().
func _tool_fs_sync(args: Dictionary) -> Dictionary:
	var efs := EditorInterface.get_resource_filesystem()
	if efs == null:
		return error_response("no EditorFileSystem available (is this an editor session?)")
	var supplied: Variant = args.get("paths", [])
	if supplied == null:
		supplied = []  # an explicit JSON null means "no paths", same as omitting the key
	# A malformed `paths` is REFUSED, not quietly ignored: falling through to the empty case would turn a caller's
	# typo into a FULL project scan() and still answer ok:true, which reads as "the files you named were synced".
	if not (supplied is Array):
		return error_response("godot_fs_sync: `paths` must be an array of res:// paths (got %s)" % type_string(typeof(supplied)))
	var raw: Array = supplied

	if raw.is_empty():
		efs.scan()
		return ok_response({"scanned": true, "refreshed": [], "missing": [], "rejected": []})

	var refreshed: Array[String] = []
	var missing: Array[String] = []
	var rejected: Array[String] = []
	for p in raw:
		# An OS path is accepted ONLY because localize_path() folds one that lives inside the project back to res://.
		# Anything that does not fold — a path outside the project, a blank entry, a non-String — is REJECTED here
		# instead of being handed on: EditorFileSystem only tracks res://, so update_file() would do nothing while
		# file_exists() still answered true, and the path would be reported "refreshed" after the editor never
		# looked at it. That false green is precisely the failure this tool exists to prevent.
		var path := ProjectSettings.localize_path(str(p))
		if not path.begins_with("res://"):
			rejected.append(path)
			continue
		# Calling update_file() on a path that no longer exists is also correct: it drops the stale cache entry.
		# So a missing path is REPORTED, never silently skipped — a green result over an unread file is a trap
		# this project has hit before.
		efs.update_file(path)
		if FileAccess.file_exists(path):
			refreshed.append(path)
		else:
			missing.append(path)
	return ok_response({"scanned": false, "refreshed": refreshed, "missing": missing, "rejected": rejected})


## What the human is currently looking at. Every lookup is null-guarded: there may be no open scene, no selection,
## and no inspected object, and none of those is an error.
func _tool_editor_state() -> Dictionary:
	var out := {
		"edited_scene": null,
		"edited_scene_root": null,
		"selection": [],
		"inspected_resource": null,
		"unsaved": null,
	}
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		# A brand-new unsaved scene has an empty scene_file_path — report null, not "".
		out["edited_scene"] = root.scene_file_path if root.scene_file_path != "" else null
		out["edited_scene_root"] = String(root.name)

	var sel := EditorInterface.get_selection()
	if sel != null:
		var picked: Array[String] = []
		for n in sel.get_selected_nodes():
			picked.append(_node_ref(n, root))
		out["selection"] = picked

	var inspector := EditorInterface.get_inspector()
	if inspector != null:
		out["inspected_resource"] = _object_ref(inspector.get_edited_object(), root)

	# "unsaved" is best-effort by contract ("<bool if obtainable>"). The editor does not expose a stable
	# unsaved-changes query across versions, so probe for it rather than pin this file to one engine build; a
	# missing method leaves the field null, which the caller reads as "unknown", not as "saved".
	if EditorInterface.has_method("has_unsaved_changes"):
		out["unsaved"] = bool(EditorInterface.call("has_unsaved_changes"))
	return ok_response(out)


## Put a resource in the Inspector (and reveal it in the FileSystem dock), or select a node in the edited scene.
## Navigation only — it deliberately does NOT open a scene tab, because opening a scene is an editor-state change
## the user did not ask for. A missing target answers ok:false with a message; it never throws.
func _tool_reveal(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "")).strip_edges()
	var node_path := str(args.get("node", "")).strip_edges()
	if path == "" and node_path == "":
		return error_response("godot_reveal needs either `path` (a res:// file) or `node` (a node path in the edited scene)")
	# EXACTLY ONE — the same rule cyber_mcp.py enforces before it ever dials this socket (its schema cannot express
	# "one of", so both ends check). Silently preferring one would move the user's focus somewhere they did not ask
	# for and report success for the target that was ignored.
	if path != "" and node_path != "":
		return error_response("godot_reveal takes either `path` or `node`, not both")

	if path != "":
		# localize_path() folds an OS path that lives INSIDE the project back to res:// (the MCP caller lives in
		# Windows-path land). One that does not fold is outside the project, where "reveal" is meaningless: the
		# FileSystem dock cannot select it, so answering ok would be a success report for a no-op.
		var localized := ProjectSettings.localize_path(path)
		if not localized.begins_with("res://"):
			return error_response("not a project path: %s — godot_reveal only reaches files under res://" % localized)
		if not FileAccess.file_exists(localized):
			return error_response("no such file: %s" % localized)
		var res := load(localized)
		if res == null:
			# Do NOT half-reveal: report the failure instead of moving the user's focus somewhere meaningless.
			# The editor briefly yields null for a file it is reimporting, so say so — retrying usually works.
			return error_response("couldn't load %s (not a Resource, or a reimport is in flight — try again in a moment)" % localized)
		EditorInterface.edit_resource(res)   # a .tres lands in the Inspector; a .gd opens in the script editor
		EditorInterface.select_file(localized)  # ...and reveal it in the FileSystem dock
		return ok_response({"revealed": "resource", "path": localized, "type": res.get_class()})

	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return error_response("no scene is open, so `%s` can't be revealed" % node_path)
	var target := root.get_node_or_null(NodePath(node_path))
	if target == null and node_path == String(root.name):
		target = root  # naming the root by its own name is the obvious thing a caller tries
	if target == null:
		return error_response("no node at `%s` under %s" % [node_path, root.name])
	var sel := EditorInterface.get_selection()
	if sel != null:
		sel.clear()
		sel.add_node(target)
	EditorInterface.edit_node(target)  # and show it in the Inspector, so "reveal" means one obvious thing
	return ok_response({"revealed": "node", "node": _node_ref(target, root), "type": target.get_class()})


## A node's identity as a caller can use it again: a path RELATIVE to the edited scene root (what `node` accepts on
## the way back in), falling back to the absolute tree path, and to the bare name for an off-tree node.
static func _node_ref(n: Node, root: Node) -> String:
	if n == null:
		return ""
	if root != null and (n == root or root.is_ancestor_of(n)):
		return String(root.get_path_to(n))
	if n.is_inside_tree():
		return String(n.get_path())
	return String(n.name)


## What the Inspector is showing, as JSON-safe text: a resource path when there is one, otherwise a short label
## (a built-in/embedded resource has no path, and the Inspector may be showing a Node instead).
static func _object_ref(obj: Object, root: Node) -> Variant:
	if obj == null:
		return null
	if obj is Resource:
		var rp := (obj as Resource).resource_path
		return rp if rp != "" else "(built-in %s)" % obj.get_class()
	if obj is Node:
		return _node_ref(obj as Node, root)
	return "(%s)" % obj.get_class()
