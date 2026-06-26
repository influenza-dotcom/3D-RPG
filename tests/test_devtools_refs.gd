extends GutTest

## The CYBER SUNDAY Refs tab: the read-only resource back-reference (owners) viewer. The PURE matchers
## (references / matching_lines / uid_from_header) are unit-tested with in-memory text — no disk walk; the tab itself
## is a compile/construct check (its scan + UI are editor-verified, like the other dock construct tests).

const RefScan := preload("res://addons/cybersunday_tools/dock_refs/ref_scan.gd")
const RefViewer := preload("res://addons/cybersunday_tools/dock_refs/ref_viewer.gd")


func test_references_matches_path_or_uid_not_neither() -> void:
	var text := "[ext_resource type=\"Resource\" uid=\"uid://abc123\" path=\"res://resources/items/healthpack.tres\" id=\"1\"]"
	assert_true(RefScan.references(text, "res://resources/items/healthpack.tres", ""), "matches by path")
	assert_true(RefScan.references(text, "res://nope.tres", "uid://abc123"), "matches by uid when the path differs")
	assert_false(RefScan.references(text, "res://nope.tres", "uid://zzz"), "no match -> false")
	assert_false(RefScan.references(text, "", ""), "empty target never matches")


func test_references_ignores_empty_uid() -> void:
	# An empty uid must NOT match (else every file would 'reference' an empty string).
	assert_false(RefScan.references("any text with uid:// in it", "res://x.tres", ""), "empty uid is never used as a needle")


func test_matching_lines_returns_referring_lines_capped() -> void:
	var text := "line one res://a.tres\nunrelated line\nload(\"res://a.tres\")\n\tslot = res://a.tres\n"
	var lines := RefScan.matching_lines(text, "res://a.tres", "")
	assert_eq(lines.size(), 3, "the three lines mentioning the path are returned; the unrelated line is skipped")
	assert_eq(lines[1], "load(\"res://a.tres\")", "lines are trimmed of leading whitespace")
	# Cap: a file mentioning the target many times is capped so it can't flood the view.
	var many := ""
	for i in 20:
		many += "res://a.tres\n"
	assert_eq(RefScan.matching_lines(many, "res://a.tres", "", 8).size(), 8, "capped at the requested limit")


func test_matching_lines_matches_by_uid_too() -> void:
	var text := "ext_resource uid=\"uid://q9\"\nother\n"
	var lines := RefScan.matching_lines(text, "res://unrelated.tres", "uid://q9")
	assert_eq(lines.size(), 1, "a uid-only reference is found")


func test_uid_from_header_extracts_or_empty() -> void:
	assert_eq(RefScan.uid_from_header("[gd_resource type=\"Resource\" script_class=\"LootTable\" load_steps=2 uid=\"uid://cabc\"]"), "uid://cabc", "pulls the uid out of a header")
	assert_eq(RefScan.uid_from_header("[gd_scene format=3]"), "", "no uid -> empty string")


## --- find_referencers() fixture: exercise the real walk against temp files (NOT project content) ---

const TMP := "user://test_refs_fixture"


func after_each() -> void:
	var d := DirAccess.open(TMP)
	if d == null:
		return
	for e in d.get_files():
		d.remove(e)
	DirAccess.remove_absolute(TMP)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f = null


func test_find_referencers_walks_and_matches_path_and_uid() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var target := TMP + "/target.tres"
	_write(target, "[gd_resource type=\"Resource\" uid=\"uid://fixtureuid77\"]\n")
	_write(TMP + "/owner_by_path.tscn", "[ext_resource path=\"%s\" id=\"1\"]\n" % target)
	_write(TMP + "/owner_by_uid.tscn", "[ext_resource uid=\"uid://fixtureuid77\" id=\"1\"]\n")
	_write(TMP + "/unrelated.tscn", "[gd_scene format=3]\nnothing to see\n")
	var refs := RefScan.find_referencers(target, TMP)  # no trailing slash -> full path of the target matches for self-exclusion
	var files := []
	for r in refs:
		files.append(String(r["file"]).get_file())
	assert_eq(refs.size(), 2, "two owners found; the unrelated file and the target itself are excluded")
	assert_true("owner_by_path.tscn" in files, "the path reference is found")
	assert_true("owner_by_uid.tscn" in files, "the uid reference is found — uid_for() read the target's header uid")
	assert_false("target.tres" in files, "the target excludes itself")


func test_ref_viewer_constructs() -> void:
	var p = RefViewer.new()
	assert_not_null(p, "the Refs tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(p.name, "Refs")
	p.free()
