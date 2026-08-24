extends SceneTree

## CYBER CLI — the headless, MACHINE-READABLE front door to the CYBER SUNDAY tooling. Every check an author
## reaches today by clicking a tab in the editor's bottom panel (audit, back-references, dialogue/quest graph,
## weapon/loot balance, the component catalog, the content browser) is reachable from one command that answers
## in JSON. The point is an AGENT (or CI, or a shell script) that can ask the project what it actually contains
## instead of guessing — the same "give the pure validators a home outside the editor" move validate_all.gd made
## for the pass/fail gate, extended to the QUERY side.
##
## This file is the ARGUMENT PARSER + STDOUT FRAMER only. All real work lives in scripts/tools/cyber_cmds.gd,
## which reuses the existing modules (scan_disk / scan_text / scan_menu_sound / ref_scan / graph_data /
## inspector_calc / loottable_inspector / browse_scan / catalog) — nothing here reimplements a check.
##
## READ-ONLY BY CONSTRUCTION: it never writes a project file, never touches .godot/, never runs `--import`
## (the user keeps the editor open all day; an import from a second process is how you get empty PackedScenes).
## The ONE write it can do is `--out=<absolute path>`, an explicit, caller-named report file OUTSIDE res://.
##
## ── Run it ────────────────────────────────────────────────────────────────────────────────────────────────
## Windows PowerShell (the project path CONTAINS A SPACE, so quote it; `--path .` silently fails on this project
## — always pass the ABSOLUTE project root):
##   & "C:\Users\dalla\bin\godot.cmd" --headless --path "C:\Users\dalla\3D RPG\rpg" -s scripts/tools/cyber.gd -- --verb=audit
##   & "C:\Users\dalla\bin\godot.cmd" --headless --path "C:\Users\dalla\3D RPG\rpg" -s scripts/tools/cyber.gd -- --verb=audit --arg:severity=ERROR --arg:limit=40
##   & "C:\Users\dalla\bin\godot.cmd" --headless --path "C:\Users\dalla\3D RPG\rpg" -s scripts/tools/cyber.gd -- --verb=refs --arg:path=res://scripts/items/item.gd
##   & "C:\Users\dalla\bin\godot.cmd" --headless --path "C:\Users\dalla\3D RPG\rpg" -s scripts/tools/cyber.gd -- --batch="C:\tmp\q.json" --out="C:\tmp\out.json" --pretty
## From the project root (cmd.exe / a .cmd wrapper), the short form works too:
##   godot --headless -s scripts/tools/cyber.gd -- --verb=catalog
##
## Everything after the bare `--` is a USER arg (OS.get_cmdline_user_args()); everything before it belongs to Godot.
##
## ── Flags ─────────────────────────────────────────────────────────────────────────────────────────────────
##   --verb=<name>              run ONE command. Verb names are cyber_cmds.gd's business, not this file's.
##   --arg:<key>=<value>        repeatable; one argument for that verb. Values are coerced (see _coerce).
##   --batch=<abs .json path>   run MANY: a JSON ARRAY of {"verb": "...", "args": {...}} objects.
##   --out=<abs path>           write the JSON result THERE; stdout still gets the framed summary. Must be OUTSIDE
##                              res:// — the project is open in the editor and this tool never writes into it.
##   --pretty                   indent the JSON (default is one dense line).
## --verb and --batch are mutually exclusive (and --arg: belongs to --verb only — a batch entry carries its own
## "args"), and any unknown/malformed flag is a USAGE ERROR (exit 2) with the usage block printed — never a silent
## ignore, because a silently-dropped filter reads back as a confident "0 findings, all clear".
##
## ── STDOUT FRAMING (non-negotiable) ───────────────────────────────────────────────────────────────────────
## Godot's banner plus ~20 UI autoloads print into stdout before we ever get a frame, so the payload is fenced:
##   <<<CYBER-JSON
##   {"ok":true,"results":[ ... ]}
##   CYBER-JSON>>>
## A caller takes what's BETWEEN the sentinels and JSON-parses it; it never has to guess where the noise ends.
## With --out= the fence still prints, carrying {"ok":...,"out":"<path>","count":N} — so ONE parse path always
## works. Diagnostics (usage errors, per-command failures) go to STDERR so they can never corrupt the fence,
## and the payload is printed with print(), never print_rich() (BBCode in a resource name would be eaten).
##
## ── EXIT CODES (the script-able contract) ─────────────────────────────────────────────────────────────────
##   0  every command returned ok:true
##   1  at least one command returned ok:false (or the result wasn't JSON-serialisable / cyber_cmds wouldn't load)
##   2  usage error: unknown flag, neither --verb nor --batch, unreadable/ill-shaped batch file, unwritable --out
##
## ── COST ──────────────────────────────────────────────────────────────────────────────────────────────────
## A headless boot of this project measures ~7.7 s before the first frame. That is per-INVOCATION, not
## per-command, which is exactly why --batch exists: ask five questions in one boot, not five boots.

## RUNTIME load, never preload — the trap this project keeps re-learning. A `-s` script's compile chain runs
## BEFORE autoloads are registered, and cyber_cmds.gd transitively reaches modules that reach autoload globals
## (loot_table.gd -> GameSettings, ItemDb), so a compile-time preload dies at boot with "Identifier not found:
## GameSettings". Deferring to load() inside the first _process frame fixes BOTH halves: the autoloads are
## registered (so the compile succeeds) and their _ready has run (so ItemDb's index is populated instead of
## empty). Same reasoning validate_all.gd and text_debt.gd document for their scanners.
const CYBER_CMDS_PATH := "res://scripts/tools/cyber_cmds.gd"

## The stdout fence. Keep these two literals in sync with tools/mcp/cyber_mcp.py, which slices between them.
const JSON_BEGIN := "<<<CYBER-JSON"
const JSON_END := "CYBER-JSON>>>"

const EXIT_OK := 0
const EXIT_COMMAND_FAILED := 1
const EXIT_USAGE := 2

const VERB_FLAG := "--verb="
const ARG_FLAG := "--arg:"
const BATCH_FLAG := "--batch="
const OUT_FLAG := "--out="
const PRETTY_FLAG := "--pretty"

## DOCUMENTATION ONLY — printed in the usage block so a human isn't left guessing. This file deliberately does
## NOT validate the verb: cyber_cmds.run() owns the verb table and answers ok:false with a real message for an
## unknown one. Gating here too would mean every new verb needs an edit in two files, and the two lists would drift.
const KNOWN_VERBS := "catalog | audit | refs | graph | balance | list | describe"

## The ONLY Variant types JSON.stringify renders as REAL JSON. Everything absent from this list (StringName,
## Vector*, Color, NodePath, RID, Object, and the packed byte/vector/colour arrays) falls to json.cpp's default
## branch, which coerces it to a QUOTED STRING — see _first_non_json_value for why that matters so much.
## The packed int/float/String arrays ARE grouped with TYPE_ARRAY by the engine, so they emit as JSON arrays.
const JSON_NATIVE_TYPES: Array[int] = [
	TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING,
	TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
]

var _done := false


func _process(_delta: float) -> bool:
	# One-frame defer, the validate_all.gd idiom: by the first process frame the autoloads exist AND their _ready
	# has run, so the runtime load() of cyber_cmds.gd compiles and the content indexes it reads are populated.
	# quit(code) drives termination with the exit code; returning false leaves the loop to the quit request.
	if not _done:
		_done = true
		quit(_run())
	return false


func _run() -> int:
	var parsed := _parse_cmdline(OS.get_cmdline_user_args())
	var parse_error := String(parsed["error"])
	if not parse_error.is_empty():
		return _emit_usage_error(parse_error)

	var verb := String(parsed["verb"])
	var batch := String(parsed["batch"])
	if verb.is_empty() and batch.is_empty():
		return _emit_usage_error("nothing to do — pass --verb=<name> or --batch=<file.json>")
	if not verb.is_empty() and not batch.is_empty():
		return _emit_usage_error("--verb= and --batch= are mutually exclusive — pass exactly one")
	# In --batch mode every entry carries its OWN "args" object, so a command-line --arg: has no owner and would
	# be dropped on the floor. That is the same failure an unknown flag is rejected for: a silently-dropped filter
	# reads back to the caller as a confident "asked with severity=ERROR, got 0 findings, all clear".
	var cli_args: Dictionary = parsed["args"]
	if not batch.is_empty() and not cli_args.is_empty():
		return _emit_usage_error("--arg: cannot be combined with --batch= — put them in the batch entry's \"args\" object")

	# Build the command list. Both entry forms converge on the SAME shape ({"verb": String, "args": Dictionary}),
	# so the run loop below has one path and a single-verb run is just a batch of one.
	var commands: Array = []
	if batch.is_empty():
		commands.append({"verb": verb, "args": cli_args})
	else:
		var loaded := _read_batch(batch)
		var batch_error := String(loaded["error"])
		if not batch_error.is_empty():
			return _emit_usage_error(batch_error)
		commands = loaded["commands"]

	var cmds: GDScript = load(CYBER_CMDS_PATH)  # runtime load: see the const comment (autoload timing at boot)
	if cmds == null:
		# Don't bail early — emit one properly-shaped error PER requested command so the caller's results array
		# still lines up 1:1 with what it asked for, and it parses the failure exactly like any other failure.
		printerr("cyber: could not load ", CYBER_CMDS_PATH, " (missing, or it failed to compile — see the parse errors above)")

	var results: Array = []
	var all_ok := true
	for cmd: Dictionary in commands:
		var result := _run_one(cmds, cmd)
		results.append(result)
		if not bool(result.get("ok", false)):
			all_ok = false
			# Human-readable echo on STDERR only: stdout belongs to the fenced payload.
			printerr("cyber: %s -> %s" % [String(result.get("verb", "?")), String(result.get("error", "failed"))])

	return _emit(results, all_ok, String(parsed["out"]), bool(parsed["pretty"]))


## Run one command through cyber_cmds.run() and normalise whatever comes back to the five-key contract shape
## {ok, verb, data, error, warnings}. cyber_cmds is contracted never to crash or push_error, but this layer is
## the one a machine parses, so it defends against a null script, a non-Dictionary return, and missing keys
## rather than letting a caller read `result["ok"]` off something that isn't there.
func _run_one(cmds: GDScript, cmd: Dictionary) -> Dictionary:
	var verb := String(cmd.get("verb", ""))
	var args: Dictionary = cmd.get("args", {})
	if cmds == null:
		return _error_result(verb, "could not load %s — is the file present and does it compile?" % CYBER_CMDS_PATH)
	# A GDScript whose PARSE failed can still come back non-null from load(); calling run() on that object is an
	# "Invalid call" crash — precisely the shape this layer exists to convert into a parsable failure. The same
	# guard covers the integration break where run() is renamed or its `static` is dropped.
	# has_method() is the right call here even though run() is STATIC: GDScript overrides it to answer from the
	# script's own function table, so a static is visible. (`Script.has_static_method` does NOT exist in 4.7.1 —
	# it fails with "Nonexistent function 'has_static_method' in base 'GDScript'". Verified, don't "fix" it back.)
	if not cmds.has_method(&"run"):
		return _error_result(verb, "%s exposes no `static func run(verb, args)` — did it fail to compile, or was run() renamed?" % CYBER_CMDS_PATH)

	var raw: Variant = cmds.run(verb, args)
	if typeof(raw) != TYPE_DICTIONARY:
		return _error_result(verb, "cyber_cmds.run() returned %s, expected a Dictionary" % type_string(typeof(raw)))

	var result: Dictionary = raw
	if not result.has("ok"):
		result["ok"] = false
		result["error"] = "command returned no \"ok\" field"
	if not result.has("verb"):
		result["verb"] = verb
	if not result.has("data"):
		result["data"] = null
	if not result.has("error"):
		result["error"] = ""
	if not result.has("warnings"):
		result["warnings"] = []
	return result


func _error_result(verb: String, message: String) -> Dictionary:
	return {"ok": false, "verb": verb, "data": null, "error": message, "warnings": []}


## Serialise, optionally write, and always print the fenced block. Returns the process exit code.
func _emit(results: Array, all_ok: bool, out_path: String, pretty: bool) -> int:
	var indent := "\t" if pretty else ""
	var payload := {"ok": all_ok, "results": results}

	# LAST LINE OF DEFENCE on the wire format. cyber_cmds is contracted to emit only JSON-native values, and this
	# is where that contract is actually CHECKED — an unconverted StringName / Vector3 deep inside a command's data
	# is the "green gauge over an unread file" failure in JSON form: the caller gets a document that parses and
	# looks like success while carrying "(1, 2, 3)" where it asked for an array. Fail honestly instead.
	var leak := _first_non_json_value(payload, "$")
	if not leak.is_empty():
		printerr("cyber: refusing to emit — a command produced a value JSON cannot represent: ", leak)
		_print_block(JSON.stringify({
			"ok": false,
			"results": [],
			"error": "result was not JSON-serialisable: %s" % leak,
		}, indent))
		return EXIT_COMMAND_FAILED

	var text := JSON.stringify(payload, indent)
	# Backstop for whatever the type walk above can't model (a String carrying a lone surrogate, a stringify quirk
	# in a future engine build). It costs one parse against a ~7.7 s boot, so keeping it is free honesty.
	if text.is_empty() or JSON.parse_string(text) == null:
		printerr("cyber: the result did not survive JSON.stringify/parse — the emitted document is not parsable.")
		_print_block(JSON.stringify({
			"ok": false,
			"results": [],
			"error": "result was not JSON-serialisable (the emitted document is not parsable)",
		}, indent))
		return EXIT_COMMAND_FAILED

	if out_path.is_empty():
		_print_block(text)
		return EXIT_OK if all_ok else EXIT_COMMAND_FAILED

	# --out= is the ONLY write this tool performs, and it is an explicit caller-named path outside res://
	# (a report file, never a project file). FileAccess takes an absolute OS path fine on Windows.
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		var why := error_string(FileAccess.get_open_error())
		printerr("cyber: cannot open --out path for writing (%s): %s" % [why, out_path])
		_print_block(JSON.stringify({
			"ok": false,
			"out": out_path,
			"count": results.size(),
			"error": "cannot open --out path for writing (%s)" % why,
		}, indent))
		return EXIT_USAGE
	f.store_string(text)
	f.close()
	# Same fence, tiny summary inside — so a caller ALWAYS parses the block the same way and then decides whether
	# to read the file. `ok` here is the real aggregate, not a hardcoded true: a failed command must stay visible.
	_print_block(JSON.stringify({"ok": all_ok, "out": out_path, "count": results.size()}, indent))
	return EXIT_OK if all_ok else EXIT_COMMAND_FAILED


## Find the FIRST value in the payload that JSON cannot represent, as "<path> -> <Type>" ("" when clean).
## THIS EXISTS BECAUSE JSON.stringify NEVER FAILS. json.cpp's default branch coerces any Variant it doesn't model
## — StringName, Vector3, NodePath, Color, RID, an Object, a packed byte/vector/colour array — into a QUOTED
## STRING, so the document parses perfectly and a stringify/parse round trip sees nothing wrong. Only a type walk
## can see the leak, and naming the exact path is what turns "something wasn't serialisable" into a fixable bug
## report against the one command that leaked it. Non-String DICTIONARY keys are deliberately NOT flagged: JSON
## object keys are strings by definition and every JSON reader receives them as such, so that coercion is lossless
## for the caller. Recursion depth is the payload's own nesting (a handful of levels), not user-controlled.
func _first_non_json_value(value: Variant, path: String) -> String:
	var t := typeof(value)
	if t in JSON_NATIVE_TYPES:
		return ""
	match t:
		TYPE_FLOAT:
			# JSON has no NaN/Infinity literal — a non-finite float is the one leak that does break the parse.
			var f: float = value
			return "" if is_finite(f) else "%s -> non-finite float" % path
		TYPE_DICTIONARY:
			var d: Dictionary = value
			for k: Variant in d:
				var bad := _first_non_json_value(d[k], "%s.%s" % [path, k])
				if not bad.is_empty():
					return bad
			return ""
		TYPE_ARRAY:
			var arr: Array = value
			for i in arr.size():
				var bad := _first_non_json_value(arr[i], "%s[%d]" % [path, i])
				if not bad.is_empty():
					return bad
			return ""
	return "%s -> %s" % [path, type_string(t)]


## print(), never print_rich(): print_rich would interpret BBCode that happens to appear inside a payload string
## (a dialogue line, a resource name) and silently mangle the JSON.
func _print_block(text: String) -> void:
	print(JSON_BEGIN)
	print(text)
	print(JSON_END)


func _emit_usage_error(message: String) -> int:
	printerr("cyber: ", message)
	printerr(_usage_text())
	# Still fenced: a machine caller that fat-fingered a flag gets a parsable answer instead of having to
	# distinguish "no output" from "crashed".
	_print_block(JSON.stringify({"ok": false, "results": [], "error": message, "usage": true}))
	return EXIT_USAGE


## Strict, order-independent flag parsing. Every branch that can't be honoured EXACTLY returns an error string —
## a tolerated typo (--arg=path=... instead of --arg:path=...) would run the verb unfiltered and report a
## confident, wrong answer.
func _parse_cmdline(argv: PackedStringArray) -> Dictionary:
	var out := {"error": "", "verb": "", "args": {}, "batch": "", "out": "", "pretty": false}
	for a: String in argv:
		if a == PRETTY_FLAG:
			out["pretty"] = true
		elif a.begins_with(VERB_FLAG):
			if not String(out["verb"]).is_empty():
				out["error"] = "--verb= given more than once — use --batch= to run several commands"
				return out
			var verb := a.substr(VERB_FLAG.length()).strip_edges()
			if verb.is_empty():
				out["error"] = "--verb= needs a name, e.g. --verb=audit"
				return out
			out["verb"] = verb
		elif a.begins_with(BATCH_FLAG):
			if not String(out["batch"]).is_empty():
				out["error"] = "--batch= given more than once"
				return out
			var batch := a.substr(BATCH_FLAG.length()).strip_edges()
			if batch.is_empty():
				out["error"] = "--batch= needs a path to a .json file"
				return out
			out["batch"] = batch
		elif a.begins_with(OUT_FLAG):
			if not String(out["out"]).is_empty():
				out["error"] = "--out= given more than once"
				return out
			var dest := a.substr(OUT_FLAG.length()).strip_edges()
			if dest.is_empty():
				out["error"] = "--out= needs a file path"
				return out
			if dest.begins_with("res://"):
				# ENFORCES the header's "never writes a project file" promise instead of merely asserting it.
				# The user keeps the editor open all day, so a report dropped inside res:// is an un-imported
				# orphan the editor then has to notice — exactly the class of second-process write into the
				# live project that this toolchain refuses to make.
				out["error"] = "--out= must point OUTSIDE the project — res:// is the live project the editor has open"
				return out
			out["out"] = dest
		elif a.begins_with(ARG_FLAG):
			var body := a.substr(ARG_FLAG.length())
			var eq := body.find("=")
			if eq <= 0:  # -1 = no '=' at all, 0 = empty key ("--arg:=value")
				out["error"] = "malformed argument %s — expected %s<key>=<value>" % [a, ARG_FLAG]
				return out
			var key := body.substr(0, eq)
			var args: Dictionary = out["args"]
			if args.has(key):
				# Last-wins would silently drop the first filter; say so instead.
				out["error"] = "--arg:%s given more than once" % key
				return out
			args[key] = _coerce(body.substr(eq + 1))
		else:
			out["error"] = "unknown argument: %s" % a
			return out
	return out


## The command line carries only strings, but the verbs take typed args (`limit` is an int, `severity` a String),
## and a String where an int is expected is a runtime comparison error inside a command. So coerce the obvious
## literals: true/false -> bool, 42 -> int, 1.5 -> float, everything else stays a String (res:// paths and ids
## never look numeric, so this is safe in practice). Escape hatch for the case that isn't: a `str:` prefix takes
## the rest VERBATIM as a String — `--arg:filter=str:404` searches for the text "404", not the number.
func _coerce(raw: String) -> Variant:
	if raw.begins_with("str:"):
		return raw.substr(4)
	if raw == "true":
		return true
	if raw == "false":
		return false
	if raw.is_valid_int():
		return raw.to_int()
	if raw.is_valid_float():
		return raw.to_float()
	return raw


## Read + validate a --batch file. Returns {"error": String, "commands": Array}; a non-empty error is a usage
## error (exit 2), because the file IS the argument — a half-understood batch must not run half its commands.
func _read_batch(path: String) -> Dictionary:
	var out := {"error": "", "commands": []}
	if not FileAccess.file_exists(path):
		out["error"] = "batch file not found: %s" % path
		return out
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		out["error"] = "batch file is empty or unreadable (%s): %s" % [error_string(FileAccess.get_open_error()), path]
		return out

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		out["error"] = "batch file is not valid JSON: %s" % path
		return out
	if typeof(parsed) != TYPE_ARRAY:
		out["error"] = "batch file must hold a JSON ARRAY of {\"verb\": ..., \"args\": {...}} objects: %s" % path
		return out

	var rows: Array = parsed
	var commands: Array = []
	for i in rows.size():
		var row: Variant = rows[i]
		if typeof(row) != TYPE_DICTIONARY:
			out["error"] = "batch entry %d is not an object — expected {\"verb\": ..., \"args\": {...}}" % i
			return out
		var entry: Dictionary = row
		var verb := String(entry.get("verb", "")).strip_edges()
		if verb.is_empty():
			out["error"] = "batch entry %d has no \"verb\"" % i
			return out
		var args: Variant = entry.get("args", {})
		if typeof(args) != TYPE_DICTIONARY:
			out["error"] = "batch entry %d: \"args\" must be an object" % i
			return out
		commands.append({"verb": verb, "args": _whole_floats_to_int(args)})

	if commands.is_empty():
		out["error"] = "batch file holds an empty array — nothing to run: %s" % path
		return out
	out["commands"] = commands
	return out


## JSON has ONE number type, so `{"limit": 40}` parses as the float 40.0 — and a float handed to something that
## wants an index (Array.slice) or an int-typed parameter is either a narrowing warning or an outright error.
## Re-integerise whole floats so a batch arg arrives typed exactly like the CLI's `--arg:limit=40` equivalent.
## Recursive so nested arg structures (an array of paths, a nested filter object) get the same treatment.
func _whole_floats_to_int(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			# The magnitude guard keeps a huge/NaN/INF float from wrapping when cast; those stay floats.
			return int(f) if is_finite(f) and absf(f) < 9.0e15 and f == floorf(f) else f
		TYPE_DICTIONARY:
			var src: Dictionary = value
			var copy := {}
			for k: Variant in src:
				copy[k] = _whole_floats_to_int(src[k])
			return copy
		TYPE_ARRAY:
			var arr: Array = value
			var listed := []
			for e: Variant in arr:
				listed.append(_whole_floats_to_int(e))
			return listed
	return value


## Backslashes are DOUBLED here because GDScript reads \U as a unicode escape — "C:\Users" would not compile.
func _usage_text() -> String:
	return """
cyber.gd — the CYBER SUNDAY headless query CLI (read-only; it never writes a project file and never imports).

  ONE COMMAND
    -- --verb=<name> [--arg:<key>=<value> ...]
  MANY COMMANDS (one ~7.7s boot instead of several — prefer this)
    -- --batch=<absolute path to .json>        JSON array of {"verb": "...", "args": {...}}
       (each entry brings its OWN "args" — a command-line --arg: has no owner here and is rejected)
  OUTPUT
    --out=<absolute path>   write the JSON there; stdout still gets the fenced summary.
                            Must be OUTSIDE res:// — the editor has the project open; this tool never writes into it.
    --pretty                indent the JSON (default: one line)

  VERBS (owned by scripts/tools/cyber_cmds.gd): """ + KNOWN_VERBS + """

  ARG VALUES are coerced: true/false -> bool, 42 -> int, 1.5 -> float, else String.
  Prefix with str: to force a String, e.g. --arg:filter=str:404

  WINDOWS POWERSHELL (quote the project path — it contains a space; --path . silently fails here):
    & "C:\\Users\\dalla\\bin\\godot.cmd" --headless --path "C:\\Users\\dalla\\3D RPG\\rpg" -s scripts/tools/cyber.gd -- --verb=audit --arg:severity=ERROR

  STDOUT is FENCED: the payload sits between a "<<<CYBER" opener line and its matching closer — the JSON_BEGIN /
  JSON_END constants at the top of this file, mirrored in tools/mcp/cyber_mcp.py. They are deliberately NOT
  reprinted verbatim here: this usage text is written to STDERR, and a caller that merges the two streams
  (2>&1, or Python's stderr=STDOUT) slices on the FIRST marker it finds — so an illustration carrying the
  literal markers around a sample "ok":true body would let a fat-fingered flag parse as a successful run.

  EXIT CODES: 0 = every command ok, 1 = a command returned ok:false, 2 = usage error.
"""
