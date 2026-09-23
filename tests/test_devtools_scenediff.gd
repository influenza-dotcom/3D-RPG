extends GutTest

## The CYBER SUNDAY Scene Diff tab: the PURE .tscn parse + diff are unit-tested with in-memory scene text, the tab's
## own pure helpers (selection plan, field refusals, row labels) on plain strings, and the file-read -> diff -> tree
## render path end-to-end over two throwaway scenes written to user://. The double-click handler is driven up to the
## point it would call the editor (EditorInterface does not exist headless); Use Selected / Use Open Scene read the
## editor's selection and are covered through their pure plan_selection / field_problem halves. The height + width
## contract is measured on the tab in the tree. No scene is ever instantiated — it's a structural text diff — and
## nothing here touches a project file.

const SceneDiff := preload("res://addons/cybersunday_tools/dock_scenediff/scene_diff.gd")
const SceneDiffView := preload("res://addons/cybersunday_tools/dock_scenediff/scene_diff_view.gd")
const ScanWiring := preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")

const VIEW_PATH := "res://addons/cybersunday_tools/dock_scenediff/scene_diff_view.gd"
const REAL_SCENE := "res://scenes/levels/LevelTemplate.tscn"

const BEFORE_TEXT := "[gd_scene format=3]\n" \
	+ "[node name=\"Root\" type=\"Node3D\"]\n" \
	+ "[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\nvisible = true\n" \
	+ "[node name=\"Area\" type=\"Area3D\" parent=\".\"]\n"
const AFTER_TEXT := "[gd_scene format=3]\n" \
	+ "[node name=\"Root\" type=\"Node3D\"]\nvisible = false\n" \
	+ "[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\nvisible = true\n" \
	+ "[node name=\"Light\" type=\"OmniLight3D\" parent=\".\"]\n"


# ================================================================================================================
# scene_diff.gd — pure parse + diff
# ================================================================================================================

func test_parse_scene_keys_nodes_by_path() -> void:
	var text := "[gd_scene format=3]\n[ext_resource type=\"Script\" path=\"res://x.gd\" id=\"1\"]\n" \
		+ "[node name=\"Root\" type=\"Node3D\"]\n" \
		+ "[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\nvisible = true\n" \
		+ "[node name=\"Box\" type=\"CollisionShape3D\" parent=\"Mesh\"]\n"
	var m := SceneDiff.parse_scene(text)
	assert_true(m.has("."), "the root node is keyed as '.'")
	assert_eq(String(m["."]["name"]), "Root", "the root's own name is recorded beside its fixed '.' key (the tab renders 'Root (root)')")
	assert_eq(String(m["."]["type"]), "Node3D", "root type captured")
	assert_true(m.has("Mesh"), "a child of root is keyed by its name")
	assert_eq(String(m["Mesh"]["name"]), "Mesh", "a child records its name too")
	assert_eq(String(m["Mesh"]["props"]["visible"]), "true", "a node property line is captured")
	assert_true(m.has("Mesh/Box"), "a grandchild is keyed parent/name")
	assert_eq(String(m["Mesh/Box"]["type"]), "CollisionShape3D", "grandchild type captured")
	assert_false(m.has("res://x.gd"), "ext_resource blocks are NOT modelled as nodes")


func test_diff_scenes_added_removed_changed() -> void:
	var a := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\nvisible = true\n[node name=\"Area\" type=\"Area3D\" parent=\".\"]\n")
	var b := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\nvisible = false\n[node name=\"Light\" type=\"OmniLight3D\" parent=\".\"]\n")
	var d := SceneDiff.diff_scenes(a, b)
	assert_eq(d["added"], ["Light"], "Light is in B only")
	assert_eq(d["removed"], ["Area"], "Area is in A only")
	assert_eq((d["changed"] as Array).size(), 1, "only Mesh changed")
	assert_eq(String(d["changed"][0]["key"]), "Mesh", "the changed node is Mesh")
	assert_true("visible: true -> false" in d["changed"][0]["props_changed"], "the property delta is reported")


func test_diff_flags_type_change_and_identical() -> void:
	var a := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n[node name=\"N\" type=\"Area3D\" parent=\".\"]\n")
	var b := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n[node name=\"N\" type=\"StaticBody3D\" parent=\".\"]\n")
	var d := SceneDiff.diff_scenes(a, b)
	assert_eq((d["changed"] as Array).size(), 1, "the retyped node is a change")
	assert_true(String(d["changed"][0]["type_change"]).contains("Area3D -> StaticBody3D"), "the type change is reported")
	var same := SceneDiff.diff_scenes(a, a)
	assert_true(same["added"].is_empty() and same["removed"].is_empty() and same["changed"].is_empty(), "a scene vs itself has no differences")


func test_diff_reports_a_root_rename_and_tolerates_nameless_models() -> void:
	# Children key by name, so a child rename is one removed + one added key. The ROOT keys as "." on both sides —
	# without the recorded name its rename would be invisible; it is reported as a "name: ..." property delta.
	var a := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n")
	var b := SceneDiff.parse_scene("[node name=\"Level\" type=\"Node3D\"]\n")
	var d := SceneDiff.diff_scenes(a, b)
	assert_eq((d["changed"] as Array).size(), 1, "a root rename is a change on '.'")
	assert_eq(String(d["changed"][0]["key"]), ".", "keyed on the root")
	assert_true("name: Root -> Level" in d["changed"][0]["props_changed"], "reported as a name delta: %s" % str(d["changed"][0]["props_changed"]))
	# A model built without `name` (an older caller, a hand-made fixture) still diffs — no crash, no phantom rename.
	var bare_a := {".": {"type": "Node3D", "props": {}}}
	var bare_b := {".": {"type": "Node3D", "props": {}}}
	var same := SceneDiff.diff_scenes(bare_a, bare_b)
	assert_true(same["changed"].is_empty(), "two nameless roots are not a rename")


# ================================================================================================================
# scene_diff_view.gd — construction, disabled states, wording
# ================================================================================================================

func test_scene_diff_view_constructs() -> void:
	# Off-tree, no editor: _init builds the widgets and writes the idle status; nothing reads a file or the editor.
	var v = SceneDiffView.new()
	assert_not_null(v, "the Scene Diff tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Scene Diff", "the Control name is pinned — cyber_panel keys tabs by it (the painted title is separate)")
	assert_eq(v._status.text, SceneDiffView.MSG_IDLE, "idle status is the duplicate -> fill -> Compare walkthrough")
	assert_true(v._status.text.contains("Use Open Scene") and v._status.text.contains("Compare"), "the idle line names the buttons it points at")
	assert_eq(v._status.tooltip_text, v._status.text, "the status tooltip mirrors the text from the first write")
	var labels := _label_texts(v)
	assert_true("Before" in labels, "the first field is labelled Before (not 'A'): %s" % str(labels))
	assert_true("After" in labels, "the second field is labelled After (not 'B'): %s" % str(labels))
	assert_false("Scene Diff" in labels, "no heading Label repeating the tab name")
	assert_not_null(_find_button(v, "Compare"), "the one action verb is Compare")
	assert_null(_find_button(v, "Diff"), "the old Diff button is gone")
	assert_not_null(_find_button(v, "Use Open Scene"), "Use Open Scene fills After from the editor")
	assert_not_null(_find_button(v, "Use Selected"), "Use Selected fills a field from the FileSystem dock")
	v.free()


func test_scene_diff_view_compare_sits_on_the_after_row() -> void:
	# Layout contract (a): Compare shares the After row with Use Open Scene instead of a row of its own — one head
	# row less of panel height. The After LineEdit and the Compare button must share a parent HBox.
	var v = SceneDiffView.new()
	var compare := _find_button(v, "Compare")
	assert_not_null(compare, "Compare exists")
	assert_eq(compare.get_parent(), v._after.get_parent(), "Compare is on the After row")
	assert_eq(_find_button(v, "Use Open Scene").get_parent(), v._after.get_parent(), "so is Use Open Scene")
	assert_ne(v._before.get_parent(), v._after.get_parent(), "Before and After are separate rows")
	v.free()


func test_scene_diff_view_use_open_scene_follows_on_scene_changed() -> void:
	# Host seam: cyber_panel forwards EditorPlugin.scene_changed (and fires once at enable). With no scene the
	# button is greyed and its tooltip names what is missing; with one it re-arms and gets its real tooltip.
	var v = SceneDiffView.new()
	assert_true(v._use_open_btn.disabled, "no scene at construction -> Use Open Scene is greyed")
	assert_eq(v._use_open_btn.tooltip_text, SceneDiffView.MSG_NO_SCENE, "and the tooltip says 'Open a scene first'")
	var root := Node.new()
	v.on_scene_changed(root)
	assert_false(v._use_open_btn.disabled, "a scene root re-arms the button")
	assert_eq(v._use_open_btn.tooltip_text, SceneDiffView.TIP_USE_OPEN, "with its real tooltip")
	v.on_scene_changed(null)
	assert_true(v._use_open_btn.disabled, "null root (scene closed) greys it again")
	root.free()
	v.free()


func test_scene_diff_view_compare_is_greyed_until_both_fields_hold_a_path() -> void:
	# Disabled-state rule: Compare cannot apply with a blank field, so it is greyed with a tooltip naming which one.
	var v = SceneDiffView.new()
	assert_true(v._compare_btn.disabled, "both blank -> Compare greyed")
	assert_eq(v._compare_btn.tooltip_text, "Fill Before and After first")
	v._before.text = "res://a.tscn"
	v._update_compare_state()
	assert_true(v._compare_btn.disabled, "only Before -> still greyed")
	assert_eq(v._compare_btn.tooltip_text, "Fill After first")
	v._before.text = ""
	v._after.text = "res://b.tscn"
	v._update_compare_state()
	assert_eq(v._compare_btn.tooltip_text, "Fill Before first")
	v._before.text = "res://a.tscn"
	v._update_compare_state()
	assert_false(v._compare_btn.disabled, "both filled -> Compare live")
	assert_eq(v._compare_btn.tooltip_text, SceneDiffView.TIP_COMPARE, "with its action tooltip")
	v.free()


func test_scene_diff_view_button_tooltips_say_read_only() -> void:
	# Every action button: '<What it does>. <Writes X | Read-only>.' — at most two sentences, and this tab writes
	# nothing, so every one ends on Read-only.
	var v = SceneDiffView.new()
	var root := Node.new()
	v.on_scene_changed(root)  # arm Use Open Scene so its real tooltip is on
	v._before.text = "x.tscn"
	v._after.text = "y.tscn"
	v._update_compare_state()
	for text in ["Compare", "Use Open Scene", "Use Selected"]:
		var b := _find_button(v, text)
		assert_true(b.tooltip_text.contains("Read-only"), "%s's tooltip declares Read-only: %s" % [text, b.tooltip_text])
	assert_true(v._before.tooltip_text.length() > 0 and v._after.tooltip_text.length() > 0, "both fields explain themselves on hover")
	root.free()
	v.free()


# ================================================================================================================
# scene_diff_view.gd — pure helpers
# ================================================================================================================

func test_plan_selection_refuses_nothing_and_non_scenes() -> void:
	var empty := SceneDiffView.plan_selection(PackedStringArray(), "Before")
	assert_eq(String(empty["error"]), SceneDiffView.MSG_SELECT_FIRST, "nothing selected -> the guard template")
	assert_eq(String(empty["before"]), "", "and nothing is filled")
	var png := SceneDiffView.plan_selection(PackedStringArray(["res://icon.png"]), "After")
	assert_eq(String(png["error"]), "Couldn't fill After: icon.png is not a scene file (.tscn).", "a non-scene names the field and the file")
	assert_eq(String(png["after"]), "", "and fills nothing")


func test_plan_selection_fills_one_field_or_both() -> void:
	var one := SceneDiffView.plan_selection(PackedStringArray(["res://a.tscn"]), "After")
	assert_eq(String(one["error"]), "", "one scene is accepted")
	assert_eq(String(one["after"]), "res://a.tscn", "and lands in the pressed row's field")
	assert_eq(String(one["before"]), "", "leaving the other alone")
	var one_before := SceneDiffView.plan_selection(PackedStringArray(["res://a.tscn"]), "Before")
	assert_eq(String(one_before["before"]), "res://a.tscn", "Before's button fills Before")
	var two := SceneDiffView.plan_selection(PackedStringArray(["res://a.tscn", "res://b.tscn"]), "After")
	assert_eq(String(two["before"]), "res://a.tscn", "two scenes: the first fills Before whichever row was pressed")
	assert_eq(String(two["after"]), "res://b.tscn", "and the second fills After")
	var mixed := SceneDiffView.plan_selection(PackedStringArray(["res://a.tscn", "res://notes.txt", "res://b.tscn"]), "Before")
	assert_eq(String(mixed["error"]), "", "a non-scene beside two scenes is skipped, not refused")
	assert_eq(String(mixed["after"]), "res://b.tscn", "the two scenes still fill both")


func test_field_problem_and_compare_refusal() -> void:
	assert_eq(SceneDiffView.field_problem("Before", ""), "Before: empty", "a blank field")
	assert_eq(SceneDiffView.field_problem("After", "res://does_not_exist.tscn"), "After: not an existing .tscn", "a missing scene")
	assert_eq(SceneDiffView.field_problem("Before", "res://project.godot"), "Before: not an existing .tscn", "an existing non-scene")
	assert_eq(SceneDiffView.field_problem("After", REAL_SCENE), "", "a real scene passes")
	var blank := SceneDiffView.compare_refusal("", REAL_SCENE)
	assert_true(blank.begins_with("Couldn't compare -- Before: empty."), "the refusal grammar leads: %s" % blank)
	assert_true(blank.ends_with(SceneDiffView.HINT_BEFORE), "and ends with how to fill that field: %s" % blank)
	var missing_after := SceneDiffView.compare_refusal(REAL_SCENE, "res://nope.tscn")
	assert_true(missing_after.contains("After: not an existing .tscn"), "After is checked once Before passes: %s" % missing_after)
	assert_true(missing_after.ends_with(SceneDiffView.HINT_AFTER), "with After's own hint")
	var same := SceneDiffView.compare_refusal(REAL_SCENE, REAL_SCENE)
	assert_true(same.begins_with("Couldn't compare: Before and After are the same file"), "the same file twice is refused: %s" % same)
	assert_eq(SceneDiffView.compare_refusal(REAL_SCENE, "res://project.godot"), "Couldn't compare -- After: not an existing .tscn. " + SceneDiffView.HINT_AFTER,
		"the whole refusal line, verbatim")


func test_node_label_renders_the_root_by_name() -> void:
	var m := SceneDiff.parse_scene("[node name=\"Level\" type=\"Node3D\"]\n[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\n")
	assert_eq(SceneDiffView.node_label(".", m), "Level (root)", "the root row reads '<RootName> (root)'")
	assert_eq(SceneDiffView.node_label("Mesh", m), "Mesh", "a child row is its path from the root")
	assert_eq(SceneDiffView.node_label(".", {}), "(root)", "a model with no root still labels the row")


# ================================================================================================================
# scene_diff_view.gd — Compare end-to-end over throwaway scenes (read -> diff -> render -> status)
# ================================================================================================================

func test_compare_renders_sections_rows_and_metadata() -> void:
	var before_path := _write_temp("cs_diff_before.tscn", BEFORE_TEXT)
	var after_path := _write_temp("cs_diff_after.tscn", AFTER_TEXT)
	var v = SceneDiffView.new()
	v._before.text = before_path
	v._after.text = after_path
	v._compare()
	assert_eq(v._status.text, "Compared cs_diff_before.tscn with cs_diff_after.tscn -- 1 new, 1 gone, 1 changed.",
		"the done status names both files by file name and the three counts")
	assert_eq(v._status.tooltip_text, v._status.text, "mirrored onto the tooltip")
	var heads := _child_texts(v._tree.get_root())
	assert_eq(heads, ["New in After (1)", "Gone in After (1)", "Changed (1)"], "three sections, in the designer's words")
	var new_row: TreeItem = v._tree.get_root().get_first_child().get_first_child()
	assert_eq(new_row.get_text(0), "Light", "the new node row")
	_assert_meta(new_row, after_path, "Light", "a NEW row opens from After")
	assert_true(new_row.get_tooltip_text(0).contains(after_path), "the path rides the tooltip, not the row")
	assert_false(new_row.get_text(0).contains("res://"), "and never the row text")
	var gone_row: TreeItem = v._tree.get_root().get_first_child().get_next().get_first_child()
	assert_eq(gone_row.get_text(0), "Area", "the gone node row")
	_assert_meta(gone_row, before_path, "Area", "a GONE row opens from Before — the only file it still exists in")
	var changed_row: TreeItem = v._tree.get_root().get_first_child().get_next().get_next().get_first_child()
	assert_eq(changed_row.get_text(0), "Root (root)", "the changed root renders as '<RootName> (root)'")
	_assert_meta(changed_row, after_path, ".", "a CHANGED row opens from After, keyed on the root")
	assert_eq(changed_row.get_first_child().get_text(0), "+ visible", "the property delta sits under the node")
	_assert_meta(changed_row.get_first_child(), after_path, ".", "a detail row carries the node's metadata so double-click lands on it too")
	v.free()
	_remove_temp(before_path)
	_remove_temp(after_path)


func test_compare_reports_no_differences_and_refuses_bad_fields() -> void:
	var before_path := _write_temp("cs_diff_same_a.tscn", BEFORE_TEXT)
	var twin_path := _write_temp("cs_diff_same_b.tscn", BEFORE_TEXT)
	var v = SceneDiffView.new()
	var resting_modulate: Color = v._status.modulate
	v._before.text = before_path
	v._after.text = twin_path
	v._compare()
	assert_eq(v._status.text, "Compared cs_diff_same_a.tscn with cs_diff_same_b.tscn -- no differences (same nodes, types and properties).",
		"identical content is a clean verdict, not an empty tree with no words")
	assert_null(v._tree.get_root().get_first_child(), "and no section rows")
	v._after.text = "res://nope.tscn"
	v._compare()
	assert_true(v._status.text.begins_with("Couldn't compare -- After: not an existing .tscn."), "a bad field refuses per field: %s" % v._status.text)
	assert_true(v._status.has_theme_color_override("font_color"), "a refusal is tinted through a theme colour override")
	assert_eq(v._status.modulate, resting_modulate, "while the status keeps the modulate it rests at -- the tint is the only thing a refusal changes")
	v._after.text = twin_path
	v._compare()
	assert_false(v._status.has_theme_color_override("font_color"), "a successful compare clears the tint")
	v.free()
	_remove_temp(before_path)
	_remove_temp(twin_path)


# ================================================================================================================
# scene_diff_view.gd — the double-click handoff, the height + width contract, read-only
# ================================================================================================================

func test_double_click_routes_each_row_to_the_file_that_holds_its_node() -> void:
	# The handoff's tail (open the scene, select the node) needs a live editor. Everything before it is driven here:
	# the Tree's item_activated reaches the handler, an empty selection or a section header does nothing, and each row
	# resolves to the file its node lives in -- a GONE row to Before (the only file it still exists in), NEW and CHANGED
	# rows and the property lines under them to After. Both scenes are deleted after the Compare, so every row stops
	# at the handler's missing-file refusal -- whose status names the file the row resolved to -- and never reaches
	# the editor.
	var before_path := _write_temp("cs_diff_route_before.tscn", BEFORE_TEXT)
	var after_path := _write_temp("cs_diff_route_after.tscn", AFTER_TEXT)
	var v = SceneDiffView.new()
	v._before.text = before_path
	v._after.text = after_path
	v._compare()
	_remove_temp(before_path)
	_remove_temp(after_path)
	var done: String = v._status.text
	var new_head: TreeItem = v._tree.get_root().get_first_child()
	var gone_head: TreeItem = new_head.get_next()
	var changed_head: TreeItem = gone_head.get_next()
	v._tree.item_activated.emit()
	assert_eq(v._status.text, done, "a double-click with no row selected does nothing")
	new_head.select(0)
	v._tree.item_activated.emit()
	assert_eq(v._status.text, done, "a section header opens nothing")
	assert_false(v._status.has_theme_color_override("font_color"), "…and raises no refusal")
	gone_head.get_first_child().select(0)
	v._tree.item_activated.emit()
	assert_true(v._status.text.contains("cs_diff_route_before.tscn") and not v._status.text.contains("cs_diff_route_after.tscn"),
		"a GONE row resolves to BEFORE -- opening After would land on a scene that no longer has the node: %s" % v._status.text)
	assert_true(v._status.has_theme_color_override("font_color"), "a missing file is a tinted refusal, never an editor error")
	v._set_status("")  # clear the last verdict so each row below must write its own
	new_head.get_first_child().select(0)
	v._tree.item_activated.emit()
	assert_true(v._status.text.contains("cs_diff_route_after.tscn") and not v._status.text.contains("cs_diff_route_before.tscn"), "a NEW row resolves to After: %s" % v._status.text)
	v._set_status("")
	changed_head.get_first_child().get_first_child().select(0)
	v._tree.item_activated.emit()
	assert_true(v._status.text.contains("cs_diff_route_after.tscn") and not v._status.text.contains("cs_diff_route_before.tscn"), "a property line under a CHANGED node resolves to After too: %s" % v._status.text)
	v.free()


func test_scene_diff_view_minimum_size_does_not_grow_with_a_big_diff() -> void:
	# A TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps whatever size it
	# grew to -- so one tall or wide tab, once shown, deforms the panel for every tab after it. Measured IN the tree
	# (an off-tree Control never recomputes its minimum): a Compare that paints hundreds of long rows and a status
	# naming two long file names must leave the tab's minimum size exactly where the idle tab had it.
	var stem := "cs_diff_wide_" + "x".repeat(90)
	var many := "[gd_scene format=3]\n[node name=\"Root\" type=\"Node3D\"]\n"
	for i in 300:
		many += "[node name=\"Node_%03d_%s\" type=\"Node3D\" parent=\".\"]\n" % [i, "y".repeat(120)]
	var before_path := _write_temp(stem + "_before.tscn", BEFORE_TEXT)
	var after_path := _write_temp(stem + "_after.tscn", many)
	var v = SceneDiffView.new()
	add_child_autofree(v)
	await wait_process_frames(2)
	var idle_min: Vector2 = v.get_combined_minimum_size()
	var idle_status_min: Vector2 = v._status.get_combined_minimum_size()
	v._before.text = before_path
	v._after.text = after_path
	v._compare()
	await wait_process_frames(2)
	assert_eq(v._tree.get_root().get_first_child().get_child_count(), 300, "precondition: the Compare painted 300 long rows")
	assert_true(v._status.text.contains(stem), "precondition: the status names the long file names")
	assert_eq(v.get_combined_minimum_size(), idle_min, "300 long rows and a long verdict leave the tab's minimum size unchanged")
	assert_eq(v._status.get_combined_minimum_size(), idle_status_min, "the status row in particular stays the height it rests at")
	# Controls: the same verdict in a plain Label would have outgrown the tab, and wrapped at the status's own width
	# without the two-line clamp it would be taller -- so the equalities above are held by the tab, not by a short line.
	var unwrapped := Label.new()
	unwrapped.text = v._status.text
	add_child_autofree(unwrapped)
	var unclamped := Label.new()
	unclamped.autowrap_mode = v._status.autowrap_mode
	unclamped.custom_minimum_size = Vector2(v._status.size.x, 0)
	unclamped.text = v._status.text
	add_child_autofree(unclamped)
	await wait_process_frames(2)
	assert_gt(unwrapped.get_combined_minimum_size().x, idle_min.x, "control: unwrapped, this verdict is wider than the whole idle tab")
	assert_gt(unclamped.get_combined_minimum_size().y, idle_status_min.y, "control: wrapped but unclamped, this verdict is taller than the status row")
	# The fence that keeps the body out of the tab's minimum: the Tree sits in a ScrollContainer that never scrolls
	# sideways and carries the body floor, with the Tree's own floor inside it.
	var scroll := v._tree.get_parent() as ScrollContainer
	assert_true(scroll != null, "the Tree lives INSIDE a ScrollContainer")
	if scroll != null:
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "a long row must never widen the bottom panel")
		assert_eq(scroll.custom_minimum_size.y, SceneDiffView.BODY_MIN_HEIGHT, "the scrolled body carries the tab's body floor")
		assert_true(scroll.custom_minimum_size.y <= 120.0, "the body floor stays under the bottom panel's shared 120 px ceiling (test_devtools_layout TALL_FLOOR; reach / refs / saves / stats hold their tabs to it)")
		assert_true(v._tree.custom_minimum_size.y <= scroll.custom_minimum_size.y, "the Tree's own floor fits inside the body floor, so the outer scroll never engages")
	assert_eq(v._status.get_parent(), v, "the status Label is a direct child of the tab, outside the scroll")
	_remove_temp(before_path)
	_remove_temp(after_path)


## The write surfaces a READ-ONLY tab must never name, as [label, RegEx] pairs matched over comment-MASKED code: saving
## a resource; a file handle (the tab reads through FileAccess.get_file_as_string / file_exists, so no handle that
## could be opened for WRITE ever exists in it) or a FileAccess attribute write; a file-system mutation on a
## DirAccess; a project-settings write; an editor scene save; an undo-able scene edit; sending a file to the trash.
## Call SHAPES rather than bare words, so the tab's own `_tree.clear()` / `sel.clear()` / FileAccess reads stay legal.
const READ_ONLY_WRITE_SURFACES := [
	["ResourceSaver", "\\bResourceSaver\\b"],
	["file handle", "\\bFileAccess\\s*\\.\\s*(open|open_compressed|open_encrypted|open_encrypted_with_pass|create_temp|WRITE|READ_WRITE|WRITE_READ)\\b"],
	["FileAccess attribute write", "\\bFileAccess\\s*\\.\\s*set_\\w+\\s*\\("],
	["file store", "\\.\\s*store_\\w+\\s*\\("],
	["DirAccess mutation", "\\b(make_dir|make_dir_recursive|make_dir_absolute|make_dir_recursive_absolute|remove|remove_absolute|rename|rename_absolute|copy|copy_absolute|create_link)\\s*\\("],
	["ProjectSettings write", "\\bProjectSettings\\s*\\.\\s*(save|save_custom|set_setting|set|clear|set_initial_value|set_order)\\s*\\("],
	["editor save", "\\b(save_scene|save_scene_as|save_all_scenes|mark_scene_as_unsaved)\\s*\\("],
	["undo-able edit", "\\b(get_editor_undo_redo|EditorUndoRedoManager|UndoRedo)\\b"],
	["trash", "\\bmove_to_trash\\s*\\("],
]


## Every write surface in `source`, as "label: matched text" lines. Comments are masked first with the audit panel's
## shared masker, so a docstring PROMISING "no ResourceSaver" is not read as a violation of that promise.
func _write_surfaces(source: String) -> Array:
	var code := ScanWiring._mask_comments(source)
	var out: Array = []
	for entry in READ_ONLY_WRITE_SURFACES:
		var pair := entry as Array
		var re := RegEx.create_from_string(str(pair[1]))
		for m in re.search_all(code):
			out.append("%s: %s" % [str(pair[0]), m.get_string()])
	return out


func test_scene_diff_view_is_read_only() -> void:
	# Scene Diff is on the QA doc's read-only list: it compares, never merges or writes. "Never writes" is not something
	# a driven test can observe — a write on a branch no fixture reaches still ships — so this is a POLICY LINT over
	# EVERY script the tab is made of: the glue, the pure parse/diff module, and any script added to the folder later.
	var dir := VIEW_PATH.get_base_dir()
	var scripts: Array = []
	for f in DirAccess.get_files_at(dir):
		if str(f).get_extension() == "gd":
			scripts.append(dir.path_join(str(f)))
	assert_has(scripts, VIEW_PATH, "the lint covers the tab's editor glue: %s" % str(scripts))
	assert_has(scripts, dir.path_join("scene_diff.gd"), "and the pure parse/diff module: %s" % str(scripts))
	# CONTROL: the lint catches a real write in code, and does not catch the same words inside a comment or the tab's
	# own reads.
	var violation := "func _merge(root: Node, path: String) -> void:\n\tvar packed := PackedScene.new()\n" \
		+ "\tpacked.pack(root)\n\tResourceSaver.save(packed, path)\n" \
		+ "\tvar f := FileAccess.open(path + \".diff\", FileAccess.WRITE)\n\tf.store_string(\"merged\")\n"
	var caught := _write_surfaces(violation)
	assert_eq(caught.size(), 4, "control: ResourceSaver.save, FileAccess.open, FileAccess.WRITE and store_string are all caught: %s" % str(caught))
	var legal := "## No ResourceSaver, no FileAccess.WRITE, no save_scene() anywhere below.\nfunc _read(p: String) -> String:\n" \
		+ "\tif not FileAccess.file_exists(p):\n\t\treturn \"\"\n\t_tree.clear()\n\treturn FileAccess.get_file_as_string(p)\n"
	assert_eq(_write_surfaces(legal), [], "control: a docstring promising no writes is masked, and a plain read is not flagged")
	for path in scripts:
		var source := FileAccess.get_file_as_string(str(path))
		assert_ne(source, "", "%s should be readable" % str(path))
		var found := _write_surfaces(source)
		assert_eq(found, [], "%s must stay read-only, but its code names a write surface: %s" % [str(path), str(found)])


# ================================================================================================================
# helpers
# ================================================================================================================

func _write_temp(file_name: String, text: String) -> String:
	var path := "user://" + file_name
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "temp scene should be writable at %s" % path)
	f.store_string(text)
	f.close()
	return path


func _remove_temp(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _find_button(root: Node, text: String) -> Button:
	for c in root.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
		var deeper := _find_button(c, text)
		if deeper != null:
			return deeper
	return null


func _label_texts(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Label:
			out.append((c as Label).text)
		out.append_array(_label_texts(c))
	return out


## A row's {file, node} metadata, checked field by field (a Dictionary assert_eq is not something to lean on).
func _assert_meta(item: TreeItem, file: String, node: String, why: String) -> void:
	var meta: Variant = item.get_metadata(0)
	assert_true(meta is Dictionary, "%s: the row carries a metadata Dictionary" % why)
	if not (meta is Dictionary):
		return
	assert_eq(String((meta as Dictionary).get("file", "")), file, "%s: file" % why)
	assert_eq(String((meta as Dictionary).get("node", "")), node, "%s: node" % why)


func _child_texts(parent: TreeItem) -> Array:
	var out: Array = []
	var it := parent.get_first_child()
	while it != null:
		out.append(it.get_text(0))
		it = it.get_next()
	return out
