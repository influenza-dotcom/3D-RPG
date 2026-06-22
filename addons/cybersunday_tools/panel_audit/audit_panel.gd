@tool
extends VBoxContainer

## Project audit bottom panel: one Re-scan button runs Domain A (the edited scene tree -- every node's config
## warnings + typed level checks) and Domain B (a res:// file scan -- dead group literals, broken ext_resource refs,
## dead LootTable / out-of-range Dialogue entries) and lists the findings, errors first. Catches the silent stuff
## per-node warnings never surface (the dead lowercase-"player" group, a <null> ext_resource, an unbaked navmesh).

const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")

var _out: RichTextLabel = null


func _init() -> void:
	name = "Audit"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	var rescan := Button.new()
	rescan.text = "Re-scan"
	rescan.pressed.connect(_rescan)
	bar.add_child(rescan)
	var hint := Label.new()
	hint.text = "  scene + project"
	hint.modulate = Color(1, 1, 1, 0.6)
	bar.add_child(hint)
	add_child(bar)

	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.scroll_active = true
	_out.selection_enabled = true
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out.custom_minimum_size = Vector2(0, 120)
	_out.text = "[i]Click Re-scan to audit the open scene + the project.[/i]"
	add_child(_out)


func _rescan() -> void:
	var findings: Array = []
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		findings.append_array(ScanScene.run(root))
	findings.append_array(ScanDisk.run())
	_render(findings)


func _render(findings: Array) -> void:
	if findings.is_empty():
		_out.text = "[color=lime]No issues found.[/color]"
		return
	var errs: Array = []
	var warns: Array = []
	for f in findings:
		if f["severity"] == "ERROR":
			errs.append(f)
		else:
			warns.append(f)
	var lines := PackedStringArray()
	lines.append("[b]%d issue(s)[/b] — [color=#ff6b6b]%d error[/color] / [color=#ffd24d]%d warn[/color]" % [findings.size(), errs.size(), warns.size()])
	for f in errs:
		lines.append("[color=#ff6b6b]ERROR[/color]  %s\n      %s" % [str(f["source"]), str(f["message"])])
	for f in warns:
		lines.append("[color=#ffd24d]WARN[/color]   %s\n      %s" % [str(f["source"]), str(f["message"])])
	_out.text = "\n".join(lines)
