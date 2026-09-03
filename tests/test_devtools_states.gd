extends GutTest

## THE DISABLED-STATE AND HANDOFF CONTRACTS of the CYBER SUNDAY tool tabs.
##
## Two seams the editor drives and nothing else can see:
##
##   on_scene_changed(root)  cyber_panel forwards EditorPlugin.scene_changed (and fires once at enable) to every tab
##                           that implements it. With no scene open, a button that would place into / check the open
##                           scene must be GREY and its tooltip must say what is missing -- BEFORE the designer
##                           clicks, not after. With a scene it must come back (or, where a second gate applies,
##                           say what the OTHER missing thing is; a stale "Open a scene first" on an open scene is
##                           worse than no tooltip, because the designer goes looking for the wrong problem).
##   select_path(path)       cyber_panel.open_in_editor hands a content file to the tab that edits it. A tab that
##                           cannot find the file must answer false so the host falls back to the Inspector -- and it
##                           must do that OFF-TREE without touching EditorInterface, because that is exactly the
##                           state a bare-constructed tab is in before its first reveal.
##
## Both tables are data, not twenty near-identical functions: adding a tab means adding a row.
##
## ENGINE TRAP this file is written around: assigning a widget's value off-tree (Range.value, OptionButton.selected,
## LineEdit.text) does NOT emit its changed signal, so a test that assigns and then expects a write-through handler
## to have run asserts nothing. Nothing here assigns a widget to provoke a handler -- the handoff methods are called
## directly, exactly the way the panel calls them.

## A path no content file will ever occupy: every select_path must REFUSE it, not crash and not half-open something.
const MISSING := "res://addons/cybersunday_tools/no_such_file_for_the_gut_suite.tres"

## The scene gate. `buttons` are member names holding one Button; `lists` are member names holding an Array of them.
## `enables_with_a_scene` is false where a SECOND gate applies off-tree (nothing picked in the list, no spawner in the
## editor selection): the button stays grey, but its tooltip must move on to naming that second missing thing.
const SCENE_GATED := [
	{
		"path": "res://addons/cybersunday_tools/dock_level/level_dock.gd",
		"tab": "Level",
		"buttons": ["_check_btn", "_bake_btn", "_validate_level_btn"],
		"lists": [],
		"enables_with_a_scene": true,
	},
	{
		"path": "res://addons/cybersunday_tools/dock_place/scene_placer.gd",
		"tab": "Place",
		"buttons": [],
		"lists": ["_scene_buttons"],
		"enables_with_a_scene": true,
	},
	{
		"path": "res://addons/cybersunday_tools/dock_scenediff/scene_diff_view.gd",
		"tab": "Scene Diff",
		"buttons": ["_use_open_btn"],
		"lists": [],
		"enables_with_a_scene": true,
	},
	{
		"path": "res://addons/cybersunday_tools/dock_palette/palette_dock.gd",
		"tab": "Palette",
		"buttons": ["_add_btn"],
		"lists": [],
		"enables_with_a_scene": false,  # second gate: no component row picked in the catalog tree
	},
	{
		"path": "res://addons/cybersunday_tools/placer/item_placer_dock.gd",
		"tab": "Items",
		"buttons": ["_place_btn"],
		"lists": [],
		"enables_with_a_scene": false,  # second gate: no item picked (the list is empty until the first reveal)
	},
	{
		"path": "res://addons/cybersunday_tools/dock_encounter/encounter_view.gd",
		"tab": "Encounter",
		"buttons": ["_preview_btn"],
		"lists": [],
		"enables_with_a_scene": false,  # second gate: no EncounterSpawner selected (never, outside the editor)
	},
]

## Every tab the panel can hand a file to. Loot Edit refuses off-tree by design (its picker rows must never outlive
## the scan they index, and it cannot re-ask the designer without a window), which is still `false` to the host.
const SELECT_PATH_TABS := [
	{"path": "res://addons/cybersunday_tools/dock_browser/content_browser.gd", "tab": "Browse"},
	{"path": "res://addons/cybersunday_tools/dock_dialogue/dialogue_editor.gd", "tab": "Dialogue Edit"},
	{"path": "res://addons/cybersunday_tools/dock_loot/loot_editor.gd", "tab": "Loot Edit"},
	{"path": "res://addons/cybersunday_tools/dock_place/scene_placer.gd", "tab": "Place"},
	{"path": "res://addons/cybersunday_tools/dock_quest/quest_editor.gd", "tab": "Quest Edit"},
	{"path": "res://addons/cybersunday_tools/dock_refs/ref_viewer.gd", "tab": "Refs"},
	{"path": "res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd", "tab": "Tuning"},
	{"path": "res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd", "tab": "Graphs"},
	{"path": "res://addons/cybersunday_tools/placer/item_placer_dock.gd", "tab": "Items"},
]


# --- helpers ----------------------------------------------------------------------------------------------------

## Build one tool tab off-tree. Returns null (after a failed assert) when the script will not load or is not a Control.
func _build(path: String) -> Control:
	var gds := load(path) as GDScript
	assert_not_null(gds, "tab script should load: %s" % path)
	if gds == null:
		return null
	var c := gds.new() as Control
	assert_not_null(c, "tab script should build a Control in _init, off-tree: %s" % path)
	return c


## [name, Button] pairs for every button a SCENE_GATED row names, directly or through a Button array.
func _gated(tab: Control, row: Dictionary) -> Array:
	var out: Array = []
	var singles: Array = row.get("buttons", [])
	var lists: Array = row.get("lists", [])
	for member: String in singles:
		var b := tab.get(member) as Button
		assert_not_null(b, "%s should hold a Button in %s" % [row["tab"], member])
		if b != null:
			out.append([member, b])
	for member: String in lists:
		var arr: Array = tab.get(member)
		assert_false(arr.is_empty(), "%s: %s should collect the scene-bound buttons" % [row["tab"], member])
		for i in arr.size():
			var b := arr[i] as Button
			if b != null:
				out.append(["%s[%d] '%s'" % [member, i, b.text], b])
	return out


## Every ACTION button under `node`, depth-first. Exact class only: CheckBox / CheckButton / OptionButton also extend
## Button, but those are FIELDS -- greying them because nothing is loaded is correct and needs no tooltip. This
## contract is about the buttons that DO something.
func _action_buttons(node: Node, out: Array) -> void:
	if node.get_class() == "Button":
		out.append(node)
	for child in node.get_children():
		_action_buttons(child, out)


## Checklist (f): an action button that cannot apply right now is grey AND says what is missing. A greyed button with
## no tooltip is a dead end -- the designer has nothing to hover and no message to read.
func _assert_grey_buttons_say_why(tab: Control, what: String) -> void:
	var buttons: Array = []
	_action_buttons(tab, buttons)
	var mute := PackedStringArray()
	for entry in buttons:
		var b: Button = entry as Button
		if b != null and b.disabled and b.tooltip_text.strip_edges().is_empty():
			mute.append("'%s'" % b.text)
	assert_eq(mute.size(), 0, "%s: a greyed button must name what is missing in its tooltip (%s) -- %s" % [String(tab.name), what, ", ".join(mute)])


# --- the scene gate ---------------------------------------------------------------------------------------------

func test_scene_bound_buttons_grey_out_with_no_scene_and_name_what_is_missing() -> void:
	for row: Dictionary in SCENE_GATED:
		var tab := _build(String(row["path"]))
		if tab == null:
			continue
		assert_eq(String(tab.name), String(row["tab"]), "the Control name is how cyber_panel routes on_scene_changed")
		assert_true(tab.has_method("on_scene_changed"), "%s should take the scene handoff" % row["tab"])
		var pairs := _gated(tab, row)

		# 1. Every scene closed. plugin.gd forwards a null root, and the tab must not wait for a click to say so.
		tab.call("on_scene_changed", null)
		var live := PackedStringArray()
		var mute := PackedStringArray()
		var no_scene_tips := {}
		for entry in pairs:
			var label: String = entry[0]
			var b: Button = entry[1]
			no_scene_tips[label] = b.tooltip_text
			if not b.disabled:
				live.append(label)
			elif b.tooltip_text.strip_edges().is_empty():
				mute.append(label)
		assert_eq(live.size(), 0, "%s: with no scene open every scene-bound button must be greyed -- still clickable: %s" % [row["tab"], ", ".join(live)])
		assert_eq(mute.size(), 0, "%s: a greyed scene-bound button must say a scene has to be open -- no tooltip on: %s" % [row["tab"], ", ".join(mute)])

		# 2. A scene is open again. is_instance_valid(root) is the gate, so a bare Node3D is a faithful stand-in.
		var root := Node3D.new()
		tab.call("on_scene_changed", root)
		var enables: bool = row["enables_with_a_scene"]
		var stuck := PackedStringArray()
		for entry in pairs:
			var label: String = entry[0]
			var b: Button = entry[1]
			if enables:
				if b.disabled:
					stuck.append("%s stayed grey" % label)
			elif not b.disabled:
				stuck.append("%s went live with nothing picked" % label)
			elif b.tooltip_text.strip_edges().is_empty() or b.tooltip_text == String(no_scene_tips[label]):
				stuck.append("%s still asks for a scene that IS open" % label)
		assert_eq(stuck.size(), 0, "%s: with a scene open the gate must move on -- %s" % [row["tab"], ", ".join(stuck)])
		_assert_grey_buttons_say_why(tab, "a scene is open")
		root.free()
		tab.free()


# --- the file handoff -------------------------------------------------------------------------------------------

func test_select_path_refuses_a_file_that_is_not_there_and_leaves_no_dead_buttons() -> void:
	for row: Dictionary in SELECT_PATH_TABS:
		var tab := _build(String(row["path"]))
		if tab == null:
			continue
		assert_eq(String(tab.name), String(row["tab"]), "the Control name is how cyber_panel.open_in_editor finds this tab")
		assert_true(tab.has_method("select_path"), "%s should accept the file handoff" % row["tab"])
		var got: Variant = tab.call("select_path", MISSING)
		assert_eq(typeof(got), TYPE_BOOL, "%s.select_path must answer the host with true/false so open_in_editor can fall back to the Inspector" % row["tab"])
		assert_false(got, "%s.select_path should refuse a file that is not on disk -- and refuse it off-tree, without EditorInterface" % row["tab"])
		# A refusal is an EXIT PATH: a scan that greys its buttons and then returns early would leave them grey
		# forever. Nothing here should be left disabled without a reason the designer can read.
		_assert_grey_buttons_say_why(tab, "after a refused handoff")
		tab.free()
