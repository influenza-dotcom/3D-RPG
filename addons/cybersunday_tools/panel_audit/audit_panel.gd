@tool
extends VBoxContainer

## Project audit bottom panel: Re-scan runs Domain A (the edited scene tree -- every node's config warnings + typed
## level checks) and Domain B (a res:// file scan -- dead group literals, broken ext_resource refs, dead LootTable /
## out-of-range Dialogue entries) and lists the findings ERRORS-FIRST in a Tree. Double-click a row to JUMP to it:
## a scene-node finding selects + opens the node; a file finding opens the resource + reveals it in FileSystem.

const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")

const COLOR_ERROR := Color(1.0, 0.42, 0.42)
const COLOR_WARN := Color(1.0, 0.82, 0.3)

var _tree: Tree = null
var _summary: Label = null


func _init() -> void:
	name = "Audit"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	var rescan := Button.new()
	rescan.text = "Re-scan"
	rescan.pressed.connect(_rescan)
	bar.add_child(rescan)
	_summary = Label.new()
	_summary.modulate = Color(1, 1, 1, 0.7)
	bar.add_child(_summary)
	add_child(bar)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 120)
	_tree.item_activated.connect(_on_item_activated)  # double-click / Enter
	add_child(_tree)

	_summary.text = "Click Re-scan to audit the open scene + the project."


func _rescan() -> void:
	var findings: Array = []
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		findings.append_array(ScanScene.run(root))
	findings.append_array(ScanDisk.run())
	_render(findings)


func _render(findings: Array) -> void:
	_tree.clear()
	var root_item := _tree.create_item()
	var errs := 0
	var warns := 0
	# Errors first, then warnings.
	for sev in ["ERROR", "WARN"]:
		for f in findings:
			if String(f.get("severity", "")) != sev:
				continue
			if sev == "ERROR":
				errs += 1
			else:
				warns += 1
			var it := _tree.create_item(root_item)
			it.set_text(0, "%s   %s — %s" % [sev, str(f.get("source", "")), str(f.get("message", ""))])
			it.set_custom_color(0, COLOR_ERROR if sev == "ERROR" else COLOR_WARN)
			it.set_tooltip_text(0, str(f.get("message", "")))
			it.set_metadata(0, f)
	if findings.is_empty():
		_summary.text = "No issues found."
	else:
		_summary.text = "%d issue(s): %d error / %d warn — double-click a row to jump." % [findings.size(), errs, warns]


## Double-click a finding: jump to the offending node (select + open it) or, for a file finding, open the resource
## and reveal it in the FileSystem dock.
func _on_item_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var f: Variant = it.get_metadata(0)
	if not (f is Dictionary):
		return
	var node: Variant = f.get("node")
	if node is Node and is_instance_valid(node):
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(node)
		EditorInterface.edit_node(node)
		return
	var src := str(f.get("source", ""))
	if src.begins_with("res://"):
		if ResourceLoader.exists(src):
			EditorInterface.edit_resource(load(src))
		EditorInterface.select_file(src)
