@tool
class_name ArchScan
extends RefCounted

## Pure architecture-annotation SCANNER + RENDERER. NO editor APIs, NO scene tree -- it reads .gd source text under
## a set of roots, extracts `## @system / @seam / @risk / @test` annotation blocks, and renders a deterministic
## Markdown "System Map". Kept pure (like panel_graph/graph_data.gd) so the GUT drift-guard test can feed it the real
## source roots and compare the render against the committed docs/SYSTEM_MAP.md with NO editor -- and so the CLI
## generator (scripts/tools/gen_arch_doc.gd) and the editor viewer tab share one code path.
##
## ANNOTATION FORMAT -- a `##` doc-comment block (usually the top-of-file block above `class_name` / `extends`) whose
## lines carry `@tag value` markers. A block that contains no `@system` is ignored, so ordinary doc comments never
## show up here:
##   ## @system NPC Brain                                 REQUIRED. Grouping key + entry title. First one in a block wins.
##   ## @seam GOAP is the sole NPC decision layer; ...     the cross-system contract (joined with a space if repeated).
##   ## @risk Scene wiring can regress silently ...        a silent-regression risk (0..n lines).
##   ## @test res://tests/test_goap_executor.gd            pointer to the contract test that locks the seam (0..n lines).
##
## One .gd file is one logical unit: every block is anchored to that file's `class_name` (if any), else its autoload
## name (resolved from project.godot [autoload]), else its basename. A file may carry MORE than one block (two blank-
## line-separated `##` blocks, each with its own `@system`) -- each becomes its own entry.
##
## Shapes (plain Dictionaries so the test + view read them without a class dep):
##   entry = { system: String, file: String, anchor: String, seam: String, risks: Array[String], tests: Array[String] }

## Game-source roots scanned by default (no addons/ — GUT + third-party carry no @system blocks). `resources/` is
## included so resource-defining classes that own a seam (e.g. SettingSpec, the data-driven Options row) are covered.
const DEFAULT_ROOTS: Array[String] = ["res://scripts", "res://managers", "res://resources"]
const ROOTS_LABEL := "scripts/, managers/ + resources/"
const DOC_PATH := "res://docs/SYSTEM_MAP.md"
const PROJECT_FILE := "res://project.godot"


## Scan all .gd under `roots`, returning a deterministic Array of entry Dictionaries (see file header for the shape).
## Sorted by (system, file, seam) so the render -- and therefore the drift-guard comparison -- is stable.
static func scan(roots: Array = DEFAULT_ROOTS) -> Array:
	var autoloads := autoload_by_path()
	var files := _collect_gd_files(roots)
	files.sort()
	var entries: Array = []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue  # missing / empty / mid-reimport -- skip, don't crash (editor-open reimport can hand back "")
		for e in parse_file(path, text, autoloads):
			entries.append(e)
	entries.sort_custom(_entry_less)
	return entries


## Parse one file's source text into 0..n entries. `autoload_map` maps a res:// script path -> its autoload name.
## Pure + dependency-free so the unit test can feed synthetic text + a fake autoload map.
static func parse_file(path: String, text: String, autoload_map: Dictionary) -> Array:
	var out: Array = []
	var anchor := _anchor_for(path, text, autoload_map)
	var lines := text.split("\n")
	var n := lines.size()
	var i := 0
	while i < n:
		if not _is_doc_line(lines[i]):
			i += 1
			continue
		# Start of a `##` doc-comment block: consume its maximal contiguous run.
		var block: Array = []
		while i < n and _is_doc_line(lines[i]):
			block.append(String(lines[i]))
			i += 1
		var e := _block_to_entry(block, path, anchor)
		if not e.is_empty():
			out.append(e)
	return out


## Render entries to the deterministic SYSTEM_MAP.md text. Ends with exactly one trailing newline. Sorts a COPY of
## the input (so callers keep their order) -> render() is self-contained + deterministic regardless of input order.
static func render(entries_in: Array) -> String:
	var entries := entries_in.duplicate()  # shallow copy: reorder without mutating the caller's array
	entries.sort_custom(_entry_less)
	# Systems in first-seen order over the sorted entries -> TOC order == section order, no second sort to drift.
	var systems: Array = []
	for e in entries:
		var s := String(e.get("system", ""))
		if not systems.has(s):
			systems.append(s)

	var total := entries.size()
	var out := PackedStringArray()
	out.append("# System Map")
	out.append("")
	out.append("<!-- GENERATED FILE - DO NOT EDIT BY HAND.")
	out.append("     Regenerate:  godot --headless --path . -s scripts/tools/gen_arch_doc.gd")
	out.append("     Source of truth: `## @system / @seam / @risk / @test` blocks above class_name / autoload scripts")
	out.append("     under %s. tests/test_arch_doc_sync.gd fails if this file is stale." % ROOTS_LABEL)
	out.append("     Companion to the hand-written ARCHITECTURE_REVIEW.md + docs/CURRENT_ARCHITECTURE.md. -->")
	out.append("")
	out.append("This index is generated from `@system` annotations in the code, so it cannot drift from the source.")
	out.append("For the deep narrative see [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md); for current rough edges")
	out.append("see [ARCHITECTURE_REVIEW.md](../ARCHITECTURE_REVIEW.md).")
	out.append("")
	out.append("_%d system(s), %d %s - scanned %s._" % [systems.size(), total, ("entry" if total == 1 else "entries"), ROOTS_LABEL])
	out.append("")
	for s in systems:
		out.append("- [%s](#%s)" % [s, _anchor_slug(s)])
	out.append("")

	for s in systems:
		out.append("## %s" % s)
		out.append("")
		for e in entries:
			if String(e.get("system", "")) != s:
				continue
			out.append("### `%s` - `%s`" % [String(e.get("anchor", "")), _display_path(String(e.get("file", "")))])
			out.append("")
			var seam := String(e.get("seam", ""))
			if seam != "":
				out.append(seam)
				out.append("")
			for r in _as_string_array(e.get("risks", [])):
				out.append("- **Risk:** %s" % r)
			var tests := _as_string_array(e.get("tests", []))
			if tests.is_empty():
				out.append("- **Test:** _none - playtest-only seam_")
			else:
				var parts := PackedStringArray()
				for t in tests:
					parts.append("`%s`" % _display_path(t))
				out.append("- **Test:** %s" % " ".join(parts))
			out.append("")

	var body := "\n".join(out)
	if not body.ends_with("\n"):
		body += "\n"
	return body


## scan() + render() in one call.
static func generate(roots: Array = DEFAULT_ROOTS) -> String:
	return render(scan(roots))


## Read the committed doc, normalizing CRLF -> LF (git/editor may rewrite line endings on Windows) so the drift-guard
## compares content, not line-ending style. Returns "" if the file is missing.
static func read_doc(doc_path: String = DOC_PATH) -> String:
	if not FileAccess.file_exists(doc_path):
		return ""
	return FileAccess.get_file_as_string(doc_path).replace("\r\n", "\n")


# --- internals -------------------------------------------------------------------------------------------------------

static func _is_doc_line(line: Variant) -> bool:
	return String(line).strip_edges().begins_with("##")


## Turn one `##` block into an entry, or {} if it carries no @system. First @system wins; @seam joins; @risk/@test list.
static func _block_to_entry(block: Array, path: String, anchor: String) -> Dictionary:
	var system := ""
	var seams := PackedStringArray()
	var risks: Array = []
	var tests: Array = []
	for raw in block:
		var after := String(raw).strip_edges()
		while after.begins_with("#"):
			after = after.substr(1)
		after = after.strip_edges()
		if not after.begins_with("@"):
			continue
		after = after.substr(1)  # drop the '@'
		var ws := _first_ws(after)
		var tag := (after if ws < 0 else after.substr(0, ws)).to_lower()
		var val := ("" if ws < 0 else after.substr(ws)).strip_edges()
		match tag:
			"system":
				if system == "" and val != "":
					system = val
			"seam":
				if val != "":
					seams.append(val)
			"risk":
				if val != "":
					risks.append(val)
			"test":
				if val != "":
					tests.append(val)
	if system == "":
		return {}
	return {
		"system": system,
		"file": path,
		"anchor": anchor,
		"seam": " ".join(seams),
		"risks": risks,
		"tests": tests,
	}


## class_name (if declared) -> "class X"; else an autoload path -> "autoload Name"; else "file basename.gd".
static func _anchor_for(path: String, text: String, autoload_map: Dictionary) -> String:
	var cls := _class_name_of(text)
	if cls != "":
		return "class " + cls
	if autoload_map.has(path):
		return "autoload " + String(autoload_map[path])
	return "file " + path.get_file()


static func _class_name_of(text: String) -> String:
	for raw in text.split("\n"):
		var s := String(raw).strip_edges()
		if s.begins_with("class_name "):
			var rest := s.substr("class_name ".length()).strip_edges()
			var ws := _first_ws(rest)  # tolerate a trailing "extends Y" on the same line
			return (rest if ws < 0 else rest.substr(0, ws)).strip_edges()
	return ""


## project.godot [autoload] -> { res://script/path.gd: "AutoloadName" }. Resolves `*uid://...` entries to their path
## (guarded) so uid-registered autoloads (e.g. DialogueManager) still map to a name.
static func autoload_by_path() -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string(PROJECT_FILE)
	if text == "":
		return out
	var in_section := false
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line.begins_with("["):
			in_section = (line == "[autoload]")
			continue
		if not in_section or line == "" or line.begins_with(";"):
			continue
		var eq := line.find("=")
		if eq < 0:
			continue
		var autoload_name := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		if val.begins_with("\"") and val.ends_with("\"") and val.length() >= 2:
			val = val.substr(1, val.length() - 2)
		val = val.lstrip("*")  # autoloads are "*res://..." (the '*' enables the singleton)
		if val.begins_with("uid://"):
			val = _resolve_uid(val)
		if val.begins_with("res://"):
			out[val] = autoload_name
	return out


static func _resolve_uid(uid: String) -> String:
	var id := ResourceUID.text_to_id(uid)
	if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
		return ResourceUID.get_id_path(id)
	return uid  # unresolved -> leave as-is; caller ignores non-res:// values


static func _collect_gd_files(roots: Array) -> Array:
	var found: Array = []
	var dirs: Array = roots.duplicate()
	while not dirs.is_empty():
		var d := String(dirs.pop_back())
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var p := d.path_join(entry)
				if da.current_is_dir():
					dirs.append(p)
				elif entry.ends_with(".gd"):
					found.append(p)
			entry = da.get_next()
		da.list_dir_end()
	return found


## Composite sort key: system (case-folded for grouping) then file then seam -> fully deterministic ordering.
static func _entry_less(a: Variant, b: Variant) -> bool:
	return _entry_key(a) < _entry_key(b)


static func _entry_key(e: Variant) -> String:
	return "%s%s%s" % [
		String(e.get("system", "")).to_lower(),
		String(e.get("file", "")),
		String(e.get("seam", "")),
	]


static func _first_ws(s: String) -> int:
	var sp := s.find(" ")
	var tab := s.find("\t")
	if sp < 0:
		return tab
	if tab < 0:
		return sp
	return mini(sp, tab)


static func _display_path(p: String) -> String:
	return p.trim_prefix("res://")


## GitHub-style heading anchor: lowercase, spaces -> '-', drop everything but [a-z0-9-]. Keeps TOC links in sync with
## the `## <System>` headings (both derived from the same system string).
static func _anchor_slug(s: String) -> String:
	var res := ""
	for ch in s.to_lower():
		if ch == " ":
			res += "-"
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-":
			res += ch
	return res


static func _as_string_array(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is Array:
		for x in v:
			out.append(String(x))
	return out
