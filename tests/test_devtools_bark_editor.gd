extends GutTest

## Bark Edit tab — the pure model (`dock_bark/bark_edit_ops.gd`) plus the dock's off-tree construction.
##
## Everything here runs headless: the ops are statics over a bare `BarkSet.new()`, and the dock is built with
## `.new()` and never added to the tree, which is exactly how `cyber_panel` would fail if `_init` reached for
## `EditorInterface` or the scene tree.
##
## The load-bearing test is `test_categories_match_every_bark_array_declared_in_the_script`: the tab derives its
## category list from the resource rather than a hand-copied list, so a new `@export var x: Array[String]` in
## `scripts/npc/bark_set.gd` must appear in the tab with no plugin edit. That drift check is what keeps the
## promise honest.

const Ops := preload("res://addons/cybersunday_tools/dock_bark/bark_edit_ops.gd")
const BarkEditor := preload("res://addons/cybersunday_tools/dock_bark/bark_editor.gd")
const BARK_SET_SRC := "res://scripts/npc/bark_set.gd"


func test_bark_dock_constructs_off_tree() -> void:
	var d = BarkEditor.new()
	assert_not_null(d, "bark tab should construct (compiles + builds its widgets off-tree)")
	assert_eq(d.name, "Bark Edit", "dock tab name -- cyber_panel routes show_tab / open_in_editor by this exact name")
	d.free()


func test_categories_are_read_off_the_resource_in_declaration_order() -> void:
	var bs := BarkSet.new()
	var cats := Ops.categories(bs)
	assert_true(cats.size() >= 21, "BarkSet should expose at least its 21 authored categories, found %d" % cats.size())
	var names: Array = []
	for c in cats:
		names.append(String(c.get("name", "")))
	assert_eq(names[0], "spot", "the first category should be the first @export on the script (declaration order)")
	assert_true(names.has("pardon_fleeing"), "a late category must not be dropped")
	assert_true(names.has("music_great"), "the last-added group must be present -- a hand-copied list is what would miss it")
	assert_eq(String(cats[0].get("group", "")), "Combat", "categories carry their @export_group so the tab can head them")
	bs = null


## The drift guard: every `@export var <name>: Array[String]` in bark_set.gd must be a category the tab shows.
func test_categories_match_every_bark_array_declared_in_the_script() -> void:
	var src := FileAccess.get_file_as_string(BARK_SET_SRC)
	assert_ne(src, "", "bark_set.gd should be readable")
	var declared: Array = []
	var re := RegEx.new()
	re.compile("^@export var ([a-z_0-9]+)\\s*:\\s*Array\\[String\\]")
	for line in src.split("\n"):
		var m := re.search(String(line))
		if m != null:
			declared.append(m.get_string(1))
	assert_true(declared.size() >= 21, "expected the script to declare at least 21 bark arrays, found %d" % declared.size())
	var bs := BarkSet.new()
	var found: Array = []
	for c in Ops.categories(bs):
		found.append(String(c.get("name", "")))
	for name in declared:
		assert_true(found.has(name), "category '%s' is declared in bark_set.gd but the Bark tab would not show it" % name)
	bs = null


func test_lines_to_array_drops_blanks_and_trims() -> void:
	var out := Ops.lines_to_array("  Contact!  \n\n Enemy spotted! \n   \n")
	assert_eq(out.size(), 2, "blank and whitespace-only lines are not barks")
	assert_eq(out[0], "Contact!", "leading and trailing whitespace is trimmed")
	assert_eq(out[1], "Enemy spotted!", "second line survives")


## An untyped Array assigned to a typed `Array[String]` export fails the assignment outright, which would make Save
## write nothing while reporting success. Pin the element type.
func test_lines_to_array_is_typed_so_the_save_actually_assigns() -> void:
	var out := Ops.lines_to_array("one\ntwo")
	assert_eq(out.get_typed_builtin(), TYPE_STRING, "the array must be typed Array[String] to assign to a BarkSet field")
	var bs := BarkSet.new()
	bs.set("spot", out)
	assert_eq((bs.get("spot") as Array).size(), 2, "the typed array assigns onto the resource")
	bs = null


func test_array_to_lines_round_trips() -> void:
	var arr: Array[String] = ["Contact!", "Enemy spotted!"]
	var text := Ops.array_to_lines(arr)
	assert_eq(text, "Contact!\nEnemy spotted!", "one bark per line, no trailing newline")
	assert_eq(Ops.lines_to_array(text), arr, "round trip returns the same lines")


func test_array_to_lines_degrades_on_a_non_array() -> void:
	assert_eq(Ops.array_to_lines(null), "", "a missing field renders an empty box rather than erroring")
	assert_eq(Ops.array_to_lines(7), "", "a non-array field renders an empty box")


## Dirty must ignore cosmetic whitespace, or the writer gets an unsaved-changes guard they cannot clear by undoing
## what they typed.
func test_differs_ignores_whitespace_only_edits() -> void:
	var arr: Array[String] = ["Contact!"]
	assert_false(Ops.differs("Contact!", arr), "identical text is not a change")
	assert_false(Ops.differs("  Contact!  \n\n", arr), "padding and blank lines are not a change")
	assert_true(Ops.differs("Contact!\nFreeze!", arr), "an added bark IS a change")
	assert_true(Ops.differs("", arr), "clearing the box IS a change")


func test_counts_report_what_is_written() -> void:
	var bs := BarkSet.new()
	assert_eq(Ops.filled_count(bs), 0, "a fresh BarkSet has no written category")
	assert_eq(Ops.line_count(bs), 0, "and no lines")
	bs.set("spot", Ops.lines_to_array("Contact!\nFreeze!"))
	bs.set("flee", Ops.lines_to_array("Forget this!"))
	assert_eq(Ops.filled_count(bs), 2, "two categories now carry lines")
	assert_eq(Ops.line_count(bs), 3, "three lines across them")
	bs = null


func test_save_report_uses_real_singular_and_plural() -> void:
	var one := Ops.save_report("raider_barks.tres", 1, 1, "")
	assert_true(one.contains("1 line "), "one line is singular, got: %s" % one)
	assert_true(one.contains("1 category"), "one category is singular, got: %s" % one)
	var many := Ops.save_report("raider_barks.tres", 14, 5, "")
	assert_true(many.contains("14 lines"), "plural lines, got: %s" % many)
	assert_true(many.contains("5 categories"), "plural categories, got: %s" % many)
	assert_false(many.contains(".bak"), "no backup is named when the file was new")
	var with_bak := Ops.save_report("raider_barks.tres", 2, 1, "raider_barks.tres.bak")
	assert_true(with_bak.contains("raider_barks.tres.bak"), "an overwrite names the kept backup, got: %s" % with_bak)


## The tab reads a folder because `ItemDb`-style autoloads are empty inside the editor. Pin that the folder it
## reads is the one the shipped bark sets actually live in.
func test_scan_finds_the_shipped_bark_sets() -> void:
	var paths := BarkEditor.scan_paths()
	assert_true(paths.size() >= 2, "expected the shipped bark sets under %s, found %d" % [Ops.BARK_DIR, paths.size()])
	for p in paths:
		assert_true(String(p).begins_with(Ops.BARK_DIR), "scan must stay inside the bark folder, got %s" % p)
		assert_true(ResourceLoader.exists(String(p)), "scanned path should be loadable: %s" % p)


## Off-tree, the handoff entry point must refuse rather than half-open a file — `cyber_panel.open_in_editor`
## duck-types the return and falls back to the Inspector on false.
func test_select_path_refuses_off_tree() -> void:
	var d = BarkEditor.new()
	assert_false(d.select_path(""), "a blank path is refused")
	assert_false(d.select_path("res://resources/barks/does_not_exist.tres"), "a missing file is refused")
	d.free()
