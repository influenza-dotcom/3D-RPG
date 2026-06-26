@tool
extends VBoxContainer

## CYBER SUNDAY → Scene Diff: a READ-ONLY structural comparison of two .tscn files. Pick scene A (before) and B
## (after) — by path or from the FileSystem selection — and Diff: it lists nodes ADDED in B, REMOVED from B, and
## CHANGED (type or properties), with the per-property differences under each changed node. For "what did this scene
## edit actually touch?" without eyeballing the raw text. READ-ONLY — it never merges or writes; apply changes by hand.

const SceneDiff := preload("res://addons/cybersunday_tools/dock_scenediff/scene_diff.gd")

const COLOR_ADD := Color(0.4, 1.0, 0.5)
const COLOR_REMOVE := Color(1.0, 0.45, 0.45)
const COLOR_CHANGE := Color(1.0, 0.82, 0.3)
const COLOR_DETAIL := Color(1, 1, 1, 0.65)

var _a: LineEdit = null
var _b: LineEdit = null
var _tree: Tree = null
var _summary: Label = null


func _init() -> void:
	name = "Scene Diff"
	add_theme_constant_override("separation", 4)
	_a = _path_row("Scene A (before) — res://...…")
	_b = _path_row("Scene B (after) — res://...…")
	var bar := HBoxContainer.new()
	var diff := Button.new()
	diff.text = "Diff"
	diff.tooltip_text = "Compare the two .tscn files structurally (read-only)."
	diff.pressed.connect(_diff)
	bar.add_child(diff)
	_summary = Label.new()
	_summary.modulate = Color(1, 1, 1, 0.7)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_summary)
	add_child(bar)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)
	add_child(_tree)
	_summary.text = "Pick two .tscn files, then Diff. Structural compare only — no merge."


## A path LineEdit + a "Use selected" button (fills from the FileSystem selection). Returns the LineEdit.
func _path_row(placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var use := Button.new()
	use.text = "Use selected"
	use.pressed.connect(func(): _use_selected(edit))
	row.add_child(use)
	add_child(row)
	return edit


func _use_selected(into: LineEdit) -> void:
	var sel := EditorInterface.get_selected_paths()
	if sel.is_empty():
		_summary.text = "Select a .tscn in the FileSystem dock first."
		return
	into.text = sel[0]


func _diff() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var pa := _a.text.strip_edges()
	var pb := _b.text.strip_edges()
	for p in [pa, pb]:
		if not p.ends_with(".tscn") or not FileAccess.file_exists(p):
			_summary.text = "Both A and B must be existing .tscn files."
			return
	if pa == pb:
		_summary.text = "A and B are the same file — pick two different scenes."
		return
	var d := SceneDiff.diff_scenes(SceneDiff.parse_scene(FileAccess.get_file_as_string(pa)), SceneDiff.parse_scene(FileAccess.get_file_as_string(pb)))
	var added: Array = d["added"]
	var removed: Array = d["removed"]
	var changed: Array = d["changed"]
	if added.is_empty() and removed.is_empty() and changed.is_empty():
		_summary.text = "No structural differences (same nodes, types, and properties)."
		return
	_section(root, "Added in B (%d)" % added.size(), added, COLOR_ADD)
	_section(root, "Removed from B (%d)" % removed.size(), removed, COLOR_REMOVE)
	if not changed.is_empty():
		var head := _tree.create_item(root)
		head.set_text(0, "Changed (%d)" % changed.size())
		head.set_custom_color(0, COLOR_CHANGE)
		for c in changed:
			var ni := _tree.create_item(head)
			ni.set_text(0, str(c["key"]))
			ni.set_custom_color(0, COLOR_CHANGE)
			if str(c["type_change"]) != "":
				_detail(ni, c["type_change"])
			for p in c["props_changed"]:
				_detail(ni, "~ " + str(p))
			for p in c["props_added"]:
				_detail(ni, "+ " + str(p))
			for p in c["props_removed"]:
				_detail(ni, "- " + str(p))
	_summary.text = "%d added, %d removed, %d changed." % [added.size(), removed.size(), changed.size()]


func _section(root: TreeItem, title: String, keys: Array, col: Color) -> void:
	if keys.is_empty():
		return
	var head := _tree.create_item(root)
	head.set_text(0, title)
	head.set_custom_color(0, col)
	for k in keys:
		var it := _tree.create_item(head)
		it.set_text(0, str(k))
		it.set_custom_color(0, col)


func _detail(parent: TreeItem, text: String) -> void:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	it.set_custom_color(0, COLOR_DETAIL)
	it.set_tooltip_text(0, text)
