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


func test_ref_viewer_constructs() -> void:
	var p = RefViewer.new()
	assert_not_null(p, "the Refs tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(p.name, "Refs")
	p.free()
