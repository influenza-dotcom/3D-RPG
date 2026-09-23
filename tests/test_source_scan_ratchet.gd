extends GutTest

## RATCHET: the number of tests that read a production .gd script's SOURCE TEXT may only go down.
##
## A source pin ("player.gd still contains `_claim_budget(`") passes while the behaviour is broken and fails on a
## harmless rename. This file counts such tests with a deliberately small text scan. The count only has to be STABLE
## and go UP when somebody adds a new scan; it is not a proof, and its blind spots are listed below.
##
## HOW A TEST IS COUNTED (every res://tests/**/test_*.gd except this file: the walk GUT's include_subdirs does)
##   1. Comment lines (first non-space char `#`) are dropped. The file is cut into top-level blocks at column-0
##      `func`, `static func`, `const`, `var` and `class` lines; a `class` block (a test double) is ignored.
##   2. A STATEMENT is one line plus the deeper-indented lines under it, except that an if/elif/else/for/while/match
##      header keeps its body out. String contents are blanked before calls and names are matched.
##   3. READ CALL: `get_file_as_string(`, `.get_as_text(`, `get_source_code(`, or `source_code` that is not being
##      assigned (writing `source_code = "..."` compiles a surrogate; it reads nothing).
##   4. GD EVIDENCE: a "res://....gd" literal; a const, var or local declared from one (or from another such name);
##      or a name holding a preload/load of a .gd, but only as `Name.resource_path`, `Name.source_code`,
##      `Name.get_source_code` or `Name.SOME_PATH`. A preloaded script's other constants are not evidence.
##   5. A helper WITH parameters that has a READ CALL, or calls such a helper, is a PATH READER. A statement READS GD
##      TEXT when it has GD EVIDENCE plus a READ CALL or a PATH READER call, or calls a GD READER, or names a TAINTED
##      var. A helper with such a statement is a GD READER. A file-scope var is TAINTED when its declaration, or an
##      assignment to it in before_all / before_each / _init / setup*, reads GD text. This runs to a fixed point.
##   6. A test_ func COUNTS when any of its statements reads GD text, whether or not the text reaches an assert.
##
## KNOWN LIMITS (deliberate; re-measure CEILING if you change a rule)
##   - A directory walk that picks scripts by extension (`ends_with(".gd")`) is not counted, so the tree-wide lint
##     guards (test_player_text, test_menu_sound_coverage, test_global_node_added_listeners) sit outside the ratchet.
##   - A path glued from pieces with no whole "res://....gd" literal (DIR + "player.gd") is not counted.
##   - Evidence and read only have to share a statement, so an unrelated .gd path in that statement over-counts.
##   - A trailing `# comment` is still scanned, and a local that shadows a tainted member still counts.
##   - Reads of .gdshader / .tscn / .tres / .cfg / .json / .md never count. A surrogate that recompiles REAL .gd text
##     read from disk does count (test_tool_scripts_load).

const CEILING := 58
## How far the count may sit under CEILING before the floor test asks for a lower ceiling.
const SLACK := 5
const TESTS_DIR := "res://tests"
const SELF_PATH := "res://tests/test_source_scan_ratchet.gd"
const MIN_TEST_FILES := 100
## Every detector fixture row is appended to this file: one of each kind of name and helper the rules resolve.
const FIXTURE_HEAD := "const GD := \"res://a/player.gd\"\nconst SCENE := \"res://a/player.tscn\"\n" \
	+ "const Ops := preload(\"res://a/ops.gd\")\nconst Ink := preload(\"res://a/ink.gd\")\n" \
	+ "var _src := \"\"\nfunc before_all() -> void:\n\t_src = FileAccess.get_file_as_string(GD)\n" \
	+ "func _player_source() -> String:\n\treturn FileAccess.get_file_as_string(GD)\n" \
	+ "func _read(path: String) -> String:\n\treturn FileAccess.open(path, FileAccess.READ).get_as_text()\n"

var _rx_decl := RegEx.create_from_string(r"^(?:static\s+)?(func|const|var|class)\s+([A-Za-z_]\w*)")
var _rx_read := RegEx.create_from_string(
	r"get_file_as_string\s*\(|\.get_as_text\s*\(|get_source_code\s*\(|\bsource_code\b(?!\s*=(?!=))")
var _rx_gd_literal := RegEx.create_from_string(r"[\"']res://[^\"'\n]*\.gd[\"']")
var _rx_string := RegEx.create_from_string(r"\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'")
var _rx_word := RegEx.create_from_string(r"(?<![\w.])(?:self\.)?([A-Za-z_]\w*)(\s*\()?")
var _rx_script_path := RegEx.create_from_string(
	r"(?<![\w.])([A-Za-z_]\w*)\s*\.\s*(?:resource_path|source_code|get_source_code|[A-Z0-9_]*PATH)\b")
var _rx_loads := RegEx.create_from_string(r"\b(?:pre)?load\s*\(")
var _rx_header := RegEx.create_from_string(r"^\s*(?:if|elif|else|for|while|match)\b.*:\s*$")
var _rx_local := RegEx.create_from_string(r"^\s*(?:var|for)\s+([A-Za-z_]\w*)")
var _rx_assign := RegEx.create_from_string(r"^\s*(?:self\.)?([A-Za-z_]\w*)\s*(?:\+=|=(?!=))")
var _rx_setup := RegEx.create_from_string(r"^(?:before_all|before_each|_init|_?setup\w*)$")
var _rx_no_params := RegEx.create_from_string(r"^(?:static\s+)?func\s+\w+\s*\(\s*\)")

var _counted: PackedStringArray = []
var _scanned := 0
var _empty: PackedStringArray = []


func before_all() -> void:
	var files := _find_test_files(TESTS_DIR)
	_scanned = files.size()
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			_empty.append(path)
		for test_name: String in _counted_tests(text):
			_counted.append("%s::%s" % [path.trim_prefix("res://"), test_name])
	_counted.sort()


func test_source_text_scans_never_grow_past_the_ceiling() -> void:
	_assert_the_walk_read_the_suite()
	assert_true(_counted.size() <= CEILING,
		("%d tests read a production .gd script's source text, but CEILING is %d.\n"
		+ "A source pin passes while the behaviour is broken and fails on a harmless rename. Write a driven test "
		+ "instead: drive the code and assert the outcome. If the scan is truly unavoidable (e.g. a Player._ready "
		+ "wiring the unit tests cannot run), raise CEILING in tests/test_source_scan_ratchet.gd in the same change "
		+ "and say why in the commit.\nEvery counted test:\n%s") % [_counted.size(), CEILING, "\n".join(_counted)])


func test_the_ceiling_tracks_the_real_count() -> void:
	_assert_the_walk_read_the_suite()
	assert_true(_counted.size() >= CEILING - SLACK,
		("only %d tests read .gd source text, but CEILING is %d. If you converted source scans into driven tests, "
		+ "lower CEILING to %d. If you did not, the detector or the file walk regressed, so do NOT lower CEILING; "
		+ "check test_the_detector_tells_gd_source_reads_from_look_alikes first.")
		% [_counted.size(), CEILING, _counted.size()])


## Each row is the body of a `test_case` appended to FIXTURE_HEAD and fed through the SAME detector the census uses,
## so a detector that went blind (counts nothing) or trigger-happy (counts every read) fails here, not in the census.
func test_the_detector_tells_gd_source_reads_from_look_alikes() -> void:
	var cases := [
		["a direct read of a .gd literal", true, 'assert_true(FileAccess.get_file_as_string("res://a/npc.gd") != "")'],
		["a helper that reads a const .gd path", true, 'assert_true(_player_source().contains("x"))'],
		["a path-reading helper called with a .gd literal", true, 'assert_true(_read("res://a/npc.gd").contains("x"))'],
		["a member var filled in before_all", true, 'assert_true(_src.contains("x"))'],
		["a local holding the .gd file, read on a later line", true,
			'var f := FileAccess.open(GD, FileAccess.READ)\n\tassert_true(f.get_as_text().contains("x"))'],
		["a path constant read off a preloaded script", true, 'assert_false(_read(Ops.SOURCE_PATH).is_empty())'],
		["a .tscn read that names a script", false, 'assert_true(_read(SCENE).contains("player.gd"))'],
		["a .gdshader read next to a preloaded script's constant", false,
			'var span: int = Ink.TINT_ID_SPAN\n\tassert_true(_read("res://a/ink.gdshader").contains(str(span)))'],
		["a read call that only appears in a comment", false,
			'# assert_true(_read(GD).contains("x"))\n\tassert_true(load(GD) != null)'],
		["a reader named only inside a string", false, 'assert_true(load(GD) != null, "see _player_source()")'],
		["a surrogate compiled from literal source_code", false,
			'var gd := GDScript.new()\n\tgd.source_code = "var p := \'res://a/player.gd\'"'],
		["a test that never reads any text", false, 'assert_eq(load(GD).new().get("hp"), 100)'],
	]
	for row: Array in cases:
		var body: String = row[2]
		var counted := _counted_tests(FIXTURE_HEAD + "func test_case() -> void:\n\t" + body).has("test_case")
		assert_eq(counted, bool(row[1]), "%s must %s:\n%s" % [row[0], "count" if row[1] else "not count", body])


# --- the detector -----------------------------------------------------------------------------------------------

## The names of the test_ funcs in one test file's text that read .gd source text (rules 1-6 in the header).
func _counted_tests(text: String) -> PackedStringArray:
	if _rx_read.search(text) == null:
		return PackedStringArray()  # every rule needs a READ CALL somewhere; this skips most files cheaply
	var blocks := _blocks(text)
	var paths := {}  # names holding a .gd path
	var scripts := {}  # names holding a preload/load of a .gd
	var member_vars := {}
	for b: Dictionary in blocks:
		b["whole"] = _statement_info("\n".join(PackedStringArray(b["lines"])))
		if b["kind"] == "const" or b["kind"] == "var":
			_declare(b["name"], b["whole"], paths, scripts)
		if b["kind"] == "var":
			member_vars[b["name"]] = true
	for b: Dictionary in blocks:
		if b["kind"] == "func":
			b["stmts"] = _statements(b["lines"].slice(1))
		else:
			b["stmts"] = [b["whole"]]
		b["paths"] = paths.duplicate()
		b["scripts"] = scripts.duplicate()
		for s: Dictionary in b["stmts"]:
			if s["local"] != "":
				_declare(s["local"], s, b["paths"], b["scripts"])
	var found := {"path_readers": {}, "gd_readers": {}, "tainted": {}}
	var changed := true
	while changed:
		changed = false
		for b: Dictionary in blocks:
			var symbol: String = b["name"]
			if b["kind"] == "var" and not found["tainted"].has(symbol) and _reads_gd(b["whole"], b, found):
				found["tainted"][symbol] = true
				changed = true
			if b["kind"] != "func" or symbol.begins_with("test_"):
				continue
			var whole: Dictionary = b["whole"]
			if not found["path_readers"].has(symbol) and _rx_no_params.search(b["lines"][0]) == null \
					and (whole["read"] or _any(whole["calls"], found["path_readers"])):
				found["path_readers"][symbol] = true
				changed = true
			for s: Dictionary in b["stmts"]:
				if not _reads_gd(s, b, found):
					continue
				if not found["gd_readers"].has(symbol):
					found["gd_readers"][symbol] = true
					changed = true
				var target: String = s["assigns"]
				if _rx_setup.search(symbol) and member_vars.has(target) and not found["tainted"].has(target):
					found["tainted"][target] = true
					changed = true
	var counted := PackedStringArray()
	for b: Dictionary in blocks:
		if b["kind"] == "func" and String(b["name"]).begins_with("test_"):
			for s: Dictionary in b["stmts"]:
				if _reads_gd(s, b, found):
					counted.append(b["name"])
					break
	return counted

func _reads_gd(s: Dictionary, block: Dictionary, found: Dictionary) -> bool:
	var evidence := _has_evidence(s, block["paths"], block["scripts"])
	return (evidence and (s["read"] or _any(s["calls"], found["path_readers"]))) \
		or _any(s["calls"], found["gd_readers"]) or _any(s["words"], found["tainted"])

func _has_evidence(s: Dictionary, paths: Dictionary, scripts: Dictionary) -> bool:
	return s["literal"] or _any(s["words"], paths) or _any(s["script_refs"], scripts)

## Records `symbol` as holding a .gd path, or a .gd script when it was loaded, if its declaring statement has evidence.
func _declare(symbol: String, s: Dictionary, paths: Dictionary, scripts: Dictionary) -> void:
	if not _has_evidence(s, paths, scripts):
		return
	var into: Dictionary = scripts if s["loads"] else paths
	into[symbol] = true

func _blocks(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: String in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		var m := _rx_decl.search(line)
		if m:
			out.append({"kind": m.get_string(1), "name": m.get_string(2), "lines": [line]})
		elif not out.is_empty():
			out.back()["lines"].append(line)
	return out

func _statements(lines: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in lines.size():
		var line: String = lines[i]
		if line.strip_edges().is_empty():
			continue
		var text := line
		if _rx_header.search(line) == null:
			for j in range(i + 1, lines.size()):
				var next: String = lines[j]
				if not next.strip_edges().is_empty() and _indent(next) <= _indent(line):
					break
				text += "\n" + next
		out.append(_statement_info(text))
	return out

func _statement_info(raw: String) -> Dictionary:
	var code := _rx_string.sub(raw, "\"\"", true)
	var words := {}
	var calls := {}
	for m: RegExMatch in _rx_word.search_all(code):
		words[m.get_string(1)] = true
		if m.get_string(2) != "":
			calls[m.get_string(1)] = true
	var script_refs := {}
	for m: RegExMatch in _rx_script_path.search_all(code):
		script_refs[m.get_string(1)] = true
	var local := _rx_local.search(code)
	var assign := _rx_assign.search(code)
	return {
		"literal": _rx_gd_literal.search(raw) != null, "read": _rx_read.search(code) != null,
		"loads": _rx_loads.search(code) != null, "words": words, "calls": calls, "script_refs": script_refs,
		"local": local.get_string(1) if local else "", "assigns": assign.get_string(1) if assign else "",
	}

func _any(names: Dictionary, of: Dictionary) -> bool:
	for n: String in names:
		if of.has(n):
			return true
	return false

func _indent(line: String) -> int:
	return line.length() - line.strip_edges(true, false).length()

func _find_test_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_find_test_files(dir.path_join(sub)))
	for file: String in DirAccess.get_files_at(dir):
		var path := dir.path_join(file)
		if file.begins_with("test_") and file.ends_with(".gd") and path != SELF_PATH:
			out.append(path)
	return out

func _assert_the_walk_read_the_suite() -> void:
	assert_true(_scanned >= MIN_TEST_FILES,
		"the ratchet found only %d test files under %s; the walk broke, so nothing was counted" % [_scanned, TESTS_DIR])
	assert_true(_empty.is_empty(), "these test files read back empty, so the census is wrong: %s" % ", ".join(_empty))
