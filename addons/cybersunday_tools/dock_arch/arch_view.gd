@tool
extends VBoxContainer

## READ-ONLY viewer for the living System Map. Groups the same `## @system / @seam / @risk / @test` annotation index
## that scripts/tools/gen_arch_doc.gd writes to docs/SYSTEM_MAP.md, and shows whether that committed file is in sync
## with the current code. Read-only BY DESIGN (per docs/CYBER_SUNDAY_PLUGIN_QA.md): this tab never writes a file --
## regeneration is the headless CLI generator (the status line shows the command), so there is no file-write guard to
## get wrong here. Shares the pure ArchScan builder with the CLI + the drift-guard test.

const ArchScan := preload("res://scripts/tools/arch_scan.gd")

var _status: Label
var _tree: Tree


func _init() -> void:
	name = "Architecture"

	var header := HBoxContainer.new()
	add_child(header)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_status)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.pressed.connect(_populate)
	header.add_child(rescan)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.columns = 1
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 160)  # height floor so the map stays usable when the panel is short
	add_child(_tree)

	_populate()


## Scan the source, rebuild the tree, and report sync status vs the committed docs/SYSTEM_MAP.md.
func _populate() -> void:
	var entries := ArchScan.scan()
	var rendered := ArchScan.render(entries)
	var committed := ArchScan.read_doc()
	var sys_count := _system_count(entries)
	var head := "%d system(s), %d entr%s.  " % [sys_count, entries.size(), ("y" if entries.size() == 1 else "ies")]
	if committed == "":
		_status.text = head + "docs/SYSTEM_MAP.md not generated yet - run:  godot --headless --path . -s scripts/tools/gen_arch_doc.gd"
	elif committed == rendered:
		_status.text = head + "docs/SYSTEM_MAP.md is IN SYNC."
	else:
		_status.text = head + "docs/SYSTEM_MAP.md is STALE - regenerate:  godot --headless --path . -s scripts/tools/gen_arch_doc.gd"

	_tree.clear()
	var root := _tree.create_item()
	var current_system := ""
	var sys_item: TreeItem = null
	for e in entries:
		var s := String(e.get("system", ""))
		if s != current_system or sys_item == null:
			current_system = s
			sys_item = _tree.create_item(root)
			sys_item.set_text(0, s)
		var it := _tree.create_item(sys_item)
		it.set_text(0, "%s  -  %s" % [String(e.get("anchor", "")), String(e.get("file", "")).trim_prefix("res://")])
		var seam := String(e.get("seam", ""))
		if seam != "":
			_tree.create_item(it).set_text(0, "seam: " + seam)
		for r in _as_array(e.get("risks")):
			_tree.create_item(it).set_text(0, "risk: " + String(r))
		var tests := _as_array(e.get("tests"))
		if tests.is_empty():
			_tree.create_item(it).set_text(0, "test: (none - playtest-only)")
		else:
			for t in tests:
				_tree.create_item(it).set_text(0, "test: " + String(t).trim_prefix("res://"))


static func _system_count(entries: Array) -> int:
	var seen := {}
	for e in entries:
		seen[String(e.get("system", ""))] = true
	return seen.size()


static func _as_array(v: Variant) -> Array:
	return v if v is Array else []
