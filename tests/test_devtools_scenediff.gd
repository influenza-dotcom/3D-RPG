extends GutTest

## The CYBER SUNDAY Scene Diff tab: the PURE .tscn parse + diff are unit-tested with in-memory scene text, the tab's
## own pure helpers (selection plan, field refusals, row labels) on plain strings, and the file-read -> diff -> tree
## render path end-to-end over two throwaway scenes written to user://. Only the handlers that need a live editor
## (Use Selected / Use Open Scene / the double-click handoff) are pinned by source-scan. No scene is ever
## instantiated — it's a structural text diff — and nothing here touches a project file.

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
	assert_eq(v._status.max_lines_visible, 2, "the status Label is clamped to two lines (the tooltip carries the rest)")
	assert_eq(v._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "and autowraps")
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
	assert_eq(v._status.modulate.a, 0.75, "while the modulate alpha stays the panel-wide 0.75")
	v._after.text = twin_path
	v._compare()
	assert_false(v._status.has_theme_color_override("font_color"), "a successful compare clears the tint")
	v.free()
	_remove_temp(before_path)
	_remove_temp(twin_path)


# ================================================================================================================
# scene_diff_view.gd — source-scanned contracts (editor-only handlers, height, read-only)
# ================================================================================================================

func test_scene_diff_view_double_click_opens_the_scene_and_selects_the_node() -> void:
	# The handoff needs a live editor, so it is pinned by source-scan like the other tabs' contracts.
	var src := FileAccess.get_file_as_string(VIEW_PATH)
	assert_ne(src, "", "scene_diff_view.gd source should be readable")
	assert_true(src.contains("_tree.item_activated.connect(_on_activated)"), "double-click / Enter on a row is wired")
	assert_true(src.contains("EditorInterface.open_scene_from_path("), "a row opens its scene AS the edited scene")
	assert_true(src.contains("get_node_or_null(NodePath(node))"), "then finds the node by its key from the root")
	assert_true(src.contains("EditorInterface.get_selection()"), "and selects it in the Scene dock")
	assert_true(src.contains("EditorInterface.get_edited_scene_root()") and src.contains("root.scene_file_path"),
		"Use Open Scene reads the edited scene root's file path")


func test_scene_diff_view_bounds_its_own_height() -> void:
	# A TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps whatever height it
	# grew to — so one tall tab, once shown, leaves the panel tall for every tab after it. Source-scanned: an
	# off-tree Control has no layout pass to measure; what must not regress is the STRUCTURE.
	var src := FileAccess.get_file_as_string(VIEW_PATH)
	assert_ne(src, "", "scene_diff_view.gd source should be readable")
	assert_true(src.contains("ScrollContainer.SCROLL_MODE_DISABLED"), "a long path or row must never widen the bottom panel")
	assert_true(src.contains("custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)"), "the scrolled body carries the tab's only vertical minimum")
	assert_lte(SceneDiffView.BODY_MIN_HEIGHT, 120.0, "the body floor stays small (mirrors reach_view / stats_view)")
	var v = SceneDiffView.new()
	assert_true(v._tree.get_parent() is ScrollContainer, "the Tree lives INSIDE the ScrollContainer")
	assert_eq(v._status.get_parent(), v, "the status Label is a direct child of the tab, outside the scroll")
	v.free()


func test_scene_diff_view_is_read_only() -> void:
	# Scene Diff is on the QA doc's read-only list: it compares, never merges or writes. Scanned over MASKED source —
	# the file's own comments name the things it does not do, and a raw grep would trip on the promise.
	var code := ScanWiring._mask_comments(FileAccess.get_file_as_string(VIEW_PATH))
	assert_ne(code, "", "scene_diff_view.gd source should be readable")
	assert_false(code.contains("ResourceSaver"), "never saves a resource")
	assert_false(code.contains("FileAccess.WRITE"), "never opens a file for writing")
	assert_false(code.contains("DirAccess"), "never touches the file system beyond reading two scenes")
	assert_false(code.contains("get_editor_undo_redo"), "never mutates the open scene — no merge, so no undo entry to get wrong")
	assert_false(code.contains("text = \"Diff\""), "the verb is Compare; Diff is retired")
	assert_false(code.contains("\"Scene A"), "the fields are Before / After, not A / B")
	var pure := ScanWiring._mask_comments(FileAccess.get_file_as_string("res://addons/cybersunday_tools/dock_scenediff/scene_diff.gd"))
	assert_false(pure.contains("FileAccess") or pure.contains("ResourceSaver"), "the pure module never reads or writes a file")


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
