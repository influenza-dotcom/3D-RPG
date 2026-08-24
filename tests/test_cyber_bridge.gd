extends GutTest

## The CYBER CLI + editor Bridge (scripts/tools/cyber_cmds.gd, scripts/tools/cyber.gd,
## addons/cybersunday_tools/dock_bridge/*). Both halves exist so an EXTERNAL process (tools/mcp/cyber_mcp.py) can
## ask this project questions, so the thing that actually has to hold is the CONTRACT AT THE EDGE: one fixed
## envelope shape, a clean ok:false for every bad input, and a payload that survives JSON in both directions.
## Those are exactly what this file pins.
##
## WHAT IS DELIBERATELY NOT TESTED HERE, and why — do not "improve" these in:
##  - No socket. bridge_server.start() binds a real TCP port; a test that opened one would fight the user's own
##    running Bridge for port 8975 and leave a listener behind on a failed assert. The request path is split into
##    PURE statics (parse_request / validate_request / *_response / summarize) precisely so the whole gate can be
##    driven with plain Strings, which is what happens below.
##  - No EditorInterface. The three tools (fs_sync / editor_state / reveal) are instance methods for that reason:
##    EditorInterface has no instance in a headless GUT run, so calling them would crash the suite, not fail it.
##  - bridge_server.stop() is NEVER called, and bridge_view is NEVER instantiated. stop() DELETES
##    res://.godot/cyber_bridge.json, and bridge_view's NOTIFICATION_PREDELETE calls stop() — so a routine
##    `.new()` + free of the tab (the usual house "does the addon script compile?" check) would silently strand a
##    Bridge the user has running in their open editor, from a different process. The view is compile-checked by
##    load()ing it and driving its pure log statics instead.
##  - No full `audit` / `list` / `refs` walk. Those scan the whole project (and are already covered by
##    tests/test_devtools_audit.gd, test_devtools_browser.gd, test_devtools_refs.gd). Every audit/graph/balance
##    case below is an ARGUMENT-validation path that returns before any scanner loads, so this file stays fast.
##
## Every script here is reached with a runtime load() rather than a preload: cyber_cmds.gd is written to be loaded
## from a `godot --headless -s` script whose compile chain runs BEFORE the autoloads exist (the ItemDb/GameSettings
## trap documented in its header), and the test mirrors how the CLI itself reaches it rather than inventing a second,
## friendlier path that the shipping tool never takes.
##
## THE ASSERTIONS MUST DEGRADE TOO. This file tests a toolchain whose entire contract is "answer ok:false, never
## throw", so it must never answer a bad result with an ENGINE error of its own: no `var d: Dictionary = <null>`,
## no rows[0] on a list an assert just reported empty. GUT turns an engine error into a suite-level failure, which
## buries the one assert that names the real cause. _data_of() / the is_empty() bails below exist for that.

const CMDS_PATH := "res://scripts/tools/cyber_cmds.gd"
const CLI_PATH := "res://scripts/tools/cyber.gd"
const BRIDGE_PATH := "res://addons/cybersunday_tools/dock_bridge/bridge_server.gd"
const BRIDGE_VIEW_PATH := "res://addons/cybersunday_tools/dock_bridge/bridge_view.gd"
## Read as TEXT, never executed: it is Python, and its tool table is the surface a verb rename silently misses.
const MCP_PATH := "res://tools/mcp/cyber_mcp.py"

## Held as untyped Variants on purpose: these are duck-typed static call surfaces (`_cmds.run(...)`), and a
## `: GDScript` annotation would make the compiler reject every call because GDScript-the-class has no run().
var _cmds
var _cli
var _bridge
var _bridge_view


## cyber.gd `extends SceneTree` — it is load()ed for its CONSTANTS only and never instantiated. Constructing it
## would hand GUT a second main loop.
func before_all() -> void:
	_cmds = load(CMDS_PATH)
	_cli = load(CLI_PATH)
	_bridge = load(BRIDGE_PATH)
	_bridge_view = load(BRIDGE_VIEW_PATH)


func after_all() -> void:
	_cmds = null
	_cli = null
	_bridge = null
	_bridge_view = null


## Script constants are NOT visible through Object.get() — get_script_constant_map() is the engine-native read
## (the same idiom cyber_cmds._catalog() uses to pull COMPONENTS off the catalog script).
func _script_const(script, key: String) -> Variant:
	var gd := script as GDScript
	if gd == null:
		return null  # the "did it compile?" tests own that verdict; don't stack an engine error on top of it
	return gd.get_script_constant_map().get(key, null)


## Walk a decoded payload and return a description of the FIRST value JSON cannot represent, or "" when the whole
## tree is clean. Round-tripping alone is not enough proof: JSON.stringify happily flattens a Vector3 or an Object
## into a string that re-parses fine but means nothing to the caller, so the leaf TYPES are checked directly.
func _json_offender(v: Variant, where: String) -> String:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(v) else "%s is a non-finite float (JSON writes a bare inf/nan)" % where
		TYPE_DICTIONARY:
			for k in (v as Dictionary):
				if typeof(k) != TYPE_STRING:
					return "%s has a non-String key %s (%s)" % [where, str(k), type_string(typeof(k))]
				var bad_v := _json_offender((v as Dictionary)[k], "%s.%s" % [where, str(k)])
				if bad_v != "":
					return bad_v
			return ""
		TYPE_ARRAY:
			for i in (v as Array).size():
				var bad_e := _json_offender((v as Array)[i], "%s[%d]" % [where, i])
				if bad_e != "":
					return bad_e
			return ""
	return "%s is a %s, which JSON cannot represent" % [where, type_string(typeof(v))]


## The `data` payload as a Dictionary, or {} when the verb failed (a failure carries `data: null` BY CONTRACT).
## Every payload read goes through here rather than `var d: Dictionary = res.get("data")`: assigning null to a
## TYPED local is a hard ENGINE error, not a failed assert, and this project's GUT build turns an engine error into
## a suite-level failure — which buries the assertion that would have named the real cause. A tool whose whole job
## is "degrade, never throw" must be tested by a file that does the same.
func _data_of(res: Dictionary) -> Dictionary:
	var d: Variant = res.get("data")
	return d if d is Dictionary else {}


## VERBS off cyber_cmds, asserted BEFORE use for the same reason as _data_of: `var v: Array = <null>` errors out
## before the assert that would explain why.
func _verbs() -> Array:
	var v: Variant = _script_const(_cmds, "VERBS")
	assert_true(v is Array, "cyber_cmds exposes its VERBS const (the CLI usage line and the MCP tool list both derive from it)")
	return v if v is Array else []


## TOOLS off bridge_server — the complete authenticated surface.
func _tools() -> Array:
	var v: Variant = _script_const(_bridge, "TOOLS")
	assert_true(v is Array, "bridge_server exposes its TOOLS const")
	return v if v is Array else []


## Every rejection on the bridge's request path must come back as the FULL wire response shape, never a bare flag:
## the external proxy parses ONE shape for success and failure alike, so a missing key there is a caller-side crash.
func _assert_error_response(res: Dictionary, what: String) -> void:
	assert_false(bool(res.get("ok", true)), "%s is ok:false" % what)
	for key in ["ok", "data", "error"]:
		assert_true(res.has(key), "%s still answers in the full response shape (missing '%s')" % [what, key])
	assert_true(String(res.get("error", "")) != "", "%s carries a non-empty error" % what)


# ── cyber_cmds: the envelope contract ────────────────────────────────────────────────────────────────────────

func test_cmds_script_loads() -> void:
	# If this fails nothing else in the file is meaningful — the CLI's whole verb layer is this one script.
	assert_not_null(_cmds, "cyber_cmds.gd loads and compiles from %s" % CMDS_PATH)


func test_unknown_verb_fails_cleanly_instead_of_crashing() -> void:
	var res: Dictionary = _cmds.run("frobnicate", {})
	assert_false(bool(res.get("ok", true)), "an unknown verb is ok:false, not a crash and not a silent success")
	assert_true(String(res.get("error", "")) != "", "the failure carries a human-readable error string")
	assert_true(String(res.get("error", "")).contains("frobnicate"), "the error quotes the verb the caller actually typed")
	assert_eq(String(res.get("verb", "")), "frobnicate", "the envelope echoes the requested verb even on failure")
	assert_null(res.get("data"), "a failed unknown verb has no payload")


func test_unknown_verb_error_lists_the_real_verbs() -> void:
	# The unknown-verb error doubles as the menu: a caller that typos gets told what exists, instead of burning
	# another ~7.7s headless boot guessing.
	var res: Dictionary = _cmds.run("", {})
	var err := String(res.get("error", ""))
	for v in _verbs():
		assert_true(err.contains(String(v)), "the unknown-verb error names the '%s' verb" % String(v))


func test_verb_list_matches_the_cli_contract() -> void:
	# Seven verbs, exactly. This pins the DISPATCH TABLE itself; the two tests below pin the other surfaces each
	# verb also has to reach, so an eighth verb fails here first and tells you the rest of the checklist.
	var verbs := _verbs()
	var expected := ["catalog", "audit", "refs", "graph", "balance", "list", "describe"]
	assert_eq(verbs.size(), expected.size(), "the verb surface is still the seven documented commands")
	for v in expected:
		assert_true(verbs.has(v), "the '%s' verb is still exposed" % v)


func test_every_verb_reaches_the_cli_usage_text_and_the_mcp_tool_list() -> void:
	# THE FOURTH-SURFACE TRAP, in this toolchain's shape (the ActionCatalog keybind lesson, again). A verb is not
	# one list, it is four: cyber_cmds.VERBS (the dispatch), cyber.gd's KNOWN_VERBS usage line, cyber_mcp.py's
	# "cyber_<verb>" MCP tool NAME, and that tool's _cli("<verb>") shell-out. NOTHING at runtime cross-checks them,
	# and both drift directions fail silently: a verb added to the dispatch alone never becomes an MCP tool at all,
	# and a verb RENAMED in the dispatch alone leaves an MCP tool that shells out to an unknown verb and answers
	# ok:false forever — after a full ~7.7s boot, every time.
	var verbs := _verbs()
	var usage := String(_script_const(_cli, "KNOWN_VERBS"))
	var mcp := FileAccess.get_file_as_string(MCP_PATH)
	assert_true(mcp != "", "the MCP server source reads back from %s (it is a shipped surface of every verb)" % MCP_PATH)
	for v in verbs:
		var verb := String(v)
		assert_true(usage.contains(verb), "cyber.gd's KNOWN_VERBS usage line still names the '%s' verb" % verb)
		assert_true(mcp.contains("\"cyber_%s\"" % verb), "cyber_mcp.py still exposes the 'cyber_%s' MCP tool" % verb)
		assert_true(mcp.contains("_cli(\"%s\")" % verb), "cyber_mcp.py's cyber_%s tool still shells out to --verb=%s" % [verb, verb])
	# The reverse direction: a verb DELETED from the dispatch but left in the usage line would advertise a command
	# that now answers "unknown verb". KNOWN_VERBS is one pipe-separated line, so its part count is the whole check.
	assert_eq(usage.split("|").size(), verbs.size(), "cyber.gd's usage line lists exactly the %d dispatched verbs — no extras left behind" % verbs.size())


func test_every_bridge_tool_reaches_the_mcp_tool_list() -> void:
	# Same drift, the editor half: bridge_server.TOOLS is the authenticated allow-list, cyber_mcp.py's _bridge("…")
	# is what actually goes on the wire. A rename on one side alone produces "unknown tool" over a port that IS open
	# and a Bridge tab that logs a rejection — a failure that looks like a security problem instead of a typo.
	var mcp := FileAccess.get_file_as_string(MCP_PATH)
	assert_true(mcp != "", "the MCP server source reads back from %s" % MCP_PATH)
	for t in _tools():
		assert_true(mcp.contains("_bridge(\"%s\")" % String(t)), "cyber_mcp.py still dials the '%s' bridge tool by that exact name" % String(t))


func test_envelope_always_carries_the_five_contract_keys() -> void:
	# The external proxy parses ONE shape for success and failure alike; a missing key there is a caller-side crash.
	for res: Dictionary in [_cmds.run("catalog", {}), _cmds.run("nope_not_a_verb", {})]:
		for key in ["ok", "verb", "data", "error", "warnings"]:
			assert_true(res.has(key), "the result envelope always carries '%s'" % key)
		assert_typeof(res["ok"], TYPE_BOOL, "'ok' is a real bool")
		assert_typeof(res["verb"], TYPE_STRING, "'verb' is a String")
		assert_typeof(res["error"], TYPE_STRING, "'error' is a String (empty on success), never null")
		assert_typeof(res["warnings"], TYPE_ARRAY, "'warnings' is always an Array, even when empty")


# ── cyber_cmds: catalog (the cheap verb — it reads one const, no project walk) ────────────────────────────────

func test_catalog_returns_the_component_rows() -> void:
	var res: Dictionary = _cmds.run("catalog", {})
	assert_true(bool(res.get("ok", false)), "catalog succeeds with no args")
	var data := _data_of(res)
	assert_false(data.is_empty(), "catalog returns a payload")
	var rows: Array = data.get("components", [])
	assert_gt(rows.size(), 0, "the droppable-component catalog is non-empty (this list is what stops an agent inventing a component)")
	assert_eq(int(data.get("count", -1)), rows.size(), "'count' matches the rows actually returned")
	assert_eq(int(data.get("total", -1)), rows.size(), "with no filter, count == total (nothing was dropped)")
	# Bail before indexing: catalog.gd is a live addon file, so an empty list IS reachable (a reimport in flight).
	# The assert above is the verdict; rows[0] on an empty Array would be an engine error that hides it.
	if rows.is_empty():
		return
	var first: Dictionary = rows[0]
	assert_true(String(first.get("class_name", "")) != "", "each row names its component class")
	assert_true(String(first.get("script_path", "")).begins_with("res://"), "each row points at the real script on disk, so the caller can go read it")


func test_catalog_filter_narrows_and_ignores_case() -> void:
	var all := _data_of(_cmds.run("catalog", {}))
	var lower := _data_of(_cmds.run("catalog", {"filter": "player"}))
	var upper := _data_of(_cmds.run("catalog", {"filter": "PLAYER"}))
	assert_gt(int(lower.get("count", 0)), 0, "'player' matches at least the Player-category rows")
	assert_eq(int(upper.get("count", -1)), int(lower.get("count", -2)), "the filter is case-insensitive — same rows either way")
	assert_lte(int(lower.get("count", 0)), int(all.get("total", 0)), "a filtered result is never larger than the unfiltered catalog")


func test_catalog_filter_matching_nothing_is_a_warning_not_a_failure() -> void:
	# "no components match" is a legitimate ANSWER. Failing it would make the caller think the tool broke.
	var res: Dictionary = _cmds.run("catalog", {"filter": "zzz_no_such_component_zzz"})
	assert_true(bool(res.get("ok", false)), "a zero-match filter still succeeds")
	var data := _data_of(res)
	assert_eq(int(data.get("count", -1)), 0, "no rows survive the filter")
	assert_gt((res.get("warnings", []) as Array).size(), 0, "but a warning says so, so an empty list is never read as 'this project has no components'")


func test_catalog_rejects_a_non_string_filter() -> void:
	var res: Dictionary = _cmds.run("catalog", {"filter": 42})
	assert_false(bool(res.get("ok", true)), "a non-String filter is a clean ok:false, not a coerced '42' that silently matches nothing")
	assert_true(String(res.get("error", "")).contains("filter"), "the error names the offending arg")


func test_unknown_arg_key_warns_but_still_answers() -> void:
	# A typo'd key would otherwise be dropped in silence and the caller would spend a whole headless boot wondering
	# why their filter did nothing.
	var res: Dictionary = _cmds.run("catalog", {"fliter": "player"})
	assert_true(bool(res.get("ok", false)), "an unknown arg key does not fail the command")
	var warns: Array = res.get("warnings", [])
	assert_gt(warns.size(), 0, "the ignored key is warned about")
	if warns.is_empty():
		return  # the assert above is the verdict; warns[0] would be an engine error on top of it
	assert_typeof(warns[0], TYPE_STRING, "warnings are Strings, per the envelope contract")
	assert_true(String(warns[0]).contains("fliter"), "the warning quotes the key that was ignored")


# ── cyber_cmds: the required-argument / bad-argument degrade paths ────────────────────────────────────────────
# Each of these returns BEFORE any scanner or resource load, so the whole group costs nothing and can never be
# flaky against a reimport in flight.

func test_refs_without_the_required_path_arg_fails_cleanly() -> void:
	var res: Dictionary = _cmds.run("refs", {})
	assert_false(bool(res.get("ok", true)), "refs with no 'path' is ok:false, not a crash and not a whole-project scan for nothing")
	assert_true(String(res.get("error", "")).contains("path"), "the error names the missing arg")


func test_refs_rejects_a_non_res_path() -> void:
	# The MCP caller lives in Windows-path land; handing an OS path straight through would scan the project and
	# return zero owners, which reads as "nothing references this" — the most dangerous wrong answer this tool has.
	var res: Dictionary = _cmds.run("refs", {"path": "C:/Users/dalla/3D RPG/rpg/scripts/world/groups.gd"})
	assert_false(bool(res.get("ok", true)), "an OS path is refused rather than answered with a misleading empty result")


func test_describe_requires_a_path_and_refuses_a_missing_resource() -> void:
	var missing: Dictionary = _cmds.run("describe", {})
	assert_false(bool(missing.get("ok", true)), "describe with no 'path' is ok:false")
	var gone: Dictionary = _cmds.run("describe", {"path": "res://resources/zzz_no_such_resource_zzz.tres"})
	assert_false(bool(gone.get("ok", true)), "describing a file that does not exist fails instead of reporting an empty resource as read")
	assert_true(String(gone.get("error", "")) != "", "and it says which path it could not find")


func test_audit_rejects_a_bad_severity_and_a_bad_limit() -> void:
	var sev: Dictionary = _cmds.run("audit", {"severity": "CRITICAL"})
	assert_false(bool(sev.get("ok", true)), "an unknown severity is refused (silently returning everything would hide the filter's failure)")
	assert_true(String(sev.get("error", "")).contains("ERROR"), "the error lists the severities that do exist")
	var limit: Dictionary = _cmds.run("audit", {"limit": "twenty"})
	assert_false(bool(limit.get("ok", true)), "a non-numeric limit is refused rather than quietly treated as 0/no-cap")


func test_graph_rejects_an_unknown_kind() -> void:
	var res: Dictionary = _cmds.run("graph", {"kind": "npcs"})
	assert_false(bool(res.get("ok", true)), "graph only builds 'dialogue' or 'quests'")
	assert_true(String(res.get("error", "")).contains("dialogue"), "the error names the kinds that work")


func test_balance_rejects_non_positive_rolls() -> void:
	# rolls drives a Monte-Carlo loot tally; 0 would produce a table of confident-looking zeroes.
	var res: Dictionary = _cmds.run("balance", {"rolls": 0})
	assert_false(bool(res.get("ok", true)), "0 rolls is refused, not run")
	assert_true(String(res.get("error", "")).contains("rolls"), "the error names the offending arg")


# ── cyber_cmds: JSON survivability (the CLI frames this straight onto stdout) ─────────────────────────────────

func test_result_is_json_round_trippable() -> void:
	# cyber.gd prints run()'s output between the <<<CYBER-JSON sentinels and the MCP server json.loads() it. A value
	# that stringifies but does not parse back (a bare inf, an Object) breaks the caller with no clue where.
	for res: Dictionary in [_cmds.run("catalog", {}), _cmds.run("still_not_a_verb", {})]:
		var text := JSON.stringify(res)
		var back: Variant = JSON.parse_string(text)
		assert_not_null(back, "the envelope survives JSON.stringify -> JSON.parse_string")
		assert_true(back is Dictionary, "and comes back as an object, not a mangled string")
		var round_trip: Dictionary = back if back is Dictionary else {}
		assert_eq(String(round_trip.get("verb", "")), String(res.get("verb", "")), "the verb survives the round trip intact")
		assert_typeof(round_trip.get("ok"), TYPE_BOOL, "'ok' comes back as a real bool, not the string \"true\"")
		assert_eq(bool(round_trip.get("ok")), bool(res.get("ok", false)), "the verdict survives the round trip")


func test_catalog_payload_contains_only_json_native_types() -> void:
	# The catalog rows carry Array[String] key_exports and StringName-ish fields upstream; run() passes everything
	# through _json_safe(), and this asserts that gate actually held rather than trusting the round trip.
	var res: Dictionary = _cmds.run("catalog", {})
	assert_eq(_json_offender(res.get("data"), "data"), "", "every leaf of the catalog payload is a JSON-native type")
	assert_eq(_json_offender(res.get("warnings"), "warnings"), "", "warnings are plain Strings")


# ── bridge_server: the pure request gate (no socket, no editor) ───────────────────────────────────────────────

func test_bridge_server_script_loads() -> void:
	assert_not_null(_bridge, "bridge_server.gd loads and compiles from %s" % BRIDGE_PATH)


func test_parse_request_rejects_malformed_lines() -> void:
	# A socket server's input is arbitrary bytes from another process. Every one of these is normal traffic, not an
	# exceptional case, so each must come back as a well-formed error dict.
	var bad_lines := {
		"   ": "an empty/whitespace line",
		"not json at all": "a non-JSON line",
		"[1, 2, 3]": "a JSON array (the request must be an object)",
		"\"just a string\"": "a bare JSON string",
		"{\"tool\": \"godot_fs_sync\", \"args\": 5}": "a non-object `args`",
	}
	for line in bad_lines:
		_assert_error_response(_bridge.parse_request(line), String(bad_lines[line]))


func test_parse_request_reads_a_well_formed_line() -> void:
	var res: Dictionary = _bridge.parse_request("{\"token\": \"abc\", \"tool\": \"godot_fs_sync\", \"args\": {\"paths\": [\"res://a.tres\"]}}\n")
	assert_true(bool(res.get("ok", false)), "a well-formed request parses")
	assert_eq(String(res.get("token", "")), "abc", "the token is extracted")
	assert_eq(String(res.get("tool", "")), "godot_fs_sync", "the tool name is extracted")
	var args: Dictionary = res.get("args", {})
	assert_eq((args.get("paths", []) as Array).size(), 1, "the args object is carried through untouched")


func test_parse_request_defaults_missing_args_to_an_empty_dict() -> void:
	# godot_editor_state takes no args at all, so a caller legitimately omits the key; it must not be an error.
	var res: Dictionary = _bridge.parse_request("{\"token\": \"abc\", \"tool\": \"godot_editor_state\"}")
	assert_true(bool(res.get("ok", false)), "an argless request is valid")
	assert_typeof(res.get("args"), TYPE_DICTIONARY, "a missing `args` becomes {}, so the handler never type-checks it")


func test_validate_request_refuses_a_missing_or_wrong_token() -> void:
	var line_no_token := "{\"tool\": \"godot_editor_state\"}"
	var line_wrong := "{\"token\": \"nope\", \"tool\": \"godot_editor_state\"}"
	var missing: Dictionary = _bridge.validate_request(line_no_token, "secret")
	var wrong: Dictionary = _bridge.validate_request(line_wrong, "secret")
	_assert_error_response(missing, "an absent token")
	_assert_error_response(wrong, "a wrong token")
	# Same message for absent and wrong on purpose: a caller must learn nothing about the secret from the reply.
	assert_eq(String(missing.get("error", "")), String(wrong.get("error", "x")), "absent and wrong tokens give the IDENTICAL error — the reply leaks nothing about the secret")


func test_validate_request_refuses_everything_when_the_server_has_no_token() -> void:
	# A stopped/half-started server has token() == "". If an empty expected token matched an empty supplied token,
	# the door would stand open exactly when nobody is guarding it.
	var res: Dictionary = _bridge.validate_request("{\"token\": \"\", \"tool\": \"godot_editor_state\"}", "")
	assert_false(bool(res.get("ok", true)), "a server with no secret accepts nothing, not everything")


func test_validate_request_refuses_an_unknown_tool() -> void:
	var res: Dictionary = _bridge.validate_request("{\"token\": \"secret\", \"tool\": \"godot_delete_project\"}", "secret")
	_assert_error_response(res, "a tool outside the served list (it never reaches the dispatch)")
	var err := String(res.get("error", ""))
	assert_true(err.contains("godot_delete_project"), "the error quotes the tool that was asked for")
	assert_true(err.contains("godot_fs_sync"), "and lists the tools that do exist")


func test_validate_request_accepts_every_served_tool() -> void:
	# TOOLS is the whole authenticated surface — if a name here stops validating, an MCP tool silently 404s.
	var tools := _tools()
	assert_eq(tools.size(), 3, "exactly three READ-ONLY tools are served (fs_sync, editor_state, reveal)")
	for t in tools:
		var line := "{\"token\": \"secret\", \"tool\": \"%s\"}" % String(t)
		var res: Dictionary = _bridge.validate_request(line, "secret")
		assert_true(bool(res.get("ok", false)), "'%s' passes the gate with the right token" % String(t))


func test_response_helpers_produce_one_parseable_line() -> void:
	var ok_res: Dictionary = _bridge.ok_response({"refreshed": ["res://a.tres"]})
	var err_res: Dictionary = _bridge.error_response("no such file")
	for r: Dictionary in [ok_res, err_res]:
		for key in ["ok", "data", "error"]:
			assert_true(r.has(key), "the wire response always carries '%s' so the client parses ONE shape" % key)
	assert_true(bool(ok_res["ok"]), "ok_response is ok:true")
	assert_false(bool(err_res["ok"]), "error_response is ok:false")
	assert_eq(String(err_res["error"]), "no such file", "the message is carried verbatim")

	var encoded := String(_bridge.encode_response(err_res))
	assert_true(encoded.ends_with("\n"), "the trailing newline IS the frame delimiter the client reads to")
	assert_eq(encoded.count("\n"), 1, "a response is exactly ONE line — an embedded newline would desync the reader")
	var back: Variant = JSON.parse_string(encoded)
	assert_not_null(back, "the encoded line parses back as JSON")
	var decoded: Dictionary = back if back is Dictionary else {}
	assert_false(bool(decoded.get("ok", true)), "and still reports the failure after the round trip")


func test_handshake_payload_carries_port_token_and_pid() -> void:
	# This file is the ONLY way the external proxy finds the port and secret; pid is how it tells a live editor
	# from a stale file a crash left behind.
	var payload: Dictionary = _bridge.handshake_payload(8975, "deadbeef", 4242)
	assert_eq(int(payload.get("port", 0)), 8975, "the bound port is recorded")
	assert_eq(String(payload.get("token", "")), "deadbeef", "the session secret is recorded")
	assert_eq(int(payload.get("pid", 0)), 4242, "the owning process id is recorded")
	assert_not_null(JSON.parse_string(JSON.stringify(payload)), "the handshake is plain JSON — Python reads this file")


func test_summarize_reports_the_error_and_truncates_a_long_payload() -> void:
	assert_eq(String(_bridge.summarize(_bridge.error_response("bad token"))), "bad token", "a failed request logs its error, not an empty payload")
	var line := String(_bridge.summarize(_bridge.ok_response({"blob": "x".repeat(200)})))
	assert_lte(line.length(), int(_script_const(_bridge, "LOG_DETAIL_CHARS")) + 4, "a huge payload is truncated before it reaches the tab's log row")
	assert_true(line.ends_with("..."), "and the truncation is visible rather than pretending to be the whole answer")


func test_a_fresh_bridge_server_is_off_and_never_self_starts() -> void:
	# The tab's Start button is the ONLY thing that may open a port. Construction must not.
	# NOTE: stop() is deliberately not called on this instance — it deletes res://.godot/cyber_bridge.json, which
	# would strand a Bridge the user has running in their editor right now. A never-started server owns nothing to
	# release, and bridge_server has no _notification hook, so dropping the reference is complete cleanup.
	var server = _bridge.new()
	assert_false(server.is_listening(), "a freshly constructed server is NOT listening")
	assert_eq(int(server.port()), 0, "no port is claimed until start() succeeds")
	assert_eq(String(server.token()), "", "no secret exists until start() mints one")
	assert_true(server.has_signal("request_served"), "the tab's live audit-trail signal is present")
	server = null


# ── bridge_view: compile check + its pure log formatters ──────────────────────────────────────────────────────
# The tab itself is NOT instantiated here (see the header): its NOTIFICATION_PREDELETE stops the server, which
# deletes the handshake file the user's running editor may own. load() is still a full compile of the script,
# which is the real value of a construct test for an addon-only file.

func test_bridge_view_script_compiles() -> void:
	assert_not_null(_bridge_view, "bridge_view.gd loads and compiles from %s" % BRIDGE_VIEW_PATH)


func test_log_row_escapes_bbcode_so_a_path_is_never_markup() -> void:
	# `detail` is arbitrary text off the request path (paths, JSON fragments) painted into a RichTextLabel. An
	# unescaped "[" would eat the rest of the row — the audit trail must show exactly what was asked for.
	assert_eq(String(_bridge_view.bb_escape("[color=red]x[/color]")), "[lb]color=red]x[lb]/color]", "every opening bracket is escaped")
	assert_eq(String(_bridge_view.bb_escape("res://a.tres")), "res://a.tres", "ordinary text is untouched")

	var row := String(_bridge_view.format_log_row("12:00:00", "godot_fs_sync", true, "[\"res://a.tres\"]"))
	assert_true(row.contains("12:00:00"), "the row is timestamped")
	assert_true(row.contains("godot_fs_sync"), "the row names the tool that was served")
	assert_true(row.contains("[lb]\"res://a.tres\"]"), "the payload's brackets are escaped inside the row")
	var failed := String(_bridge_view.format_log_row("12:00:01", "godot_reveal", false, "no such file"))
	assert_true(failed.contains("FAIL"), "a rejected request is visibly marked FAIL in the log")
	assert_false(failed.contains("OK  "), "and is not also tagged OK")
