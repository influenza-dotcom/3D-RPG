@tool
extends VBoxContainer

## CYBER SUNDAY → Refs: a READ-ONLY back-reference (owners) viewer. Enter a res:// resource (or pick one in the
## FileSystem dock and hit "Use selected"), Find refs, and it lists every project file that references it — by path
## OR uid — with the referring line(s) as the "where". This IS the delete/rename impact preview: see what breaks
## BEFORE you remove a .tres/.tscn/.gd. Unlike Godot's native View Owners it also catches .gd load()/preload() refs.
## It only READS; the scan logic lives in ref_scan.gd.

const RefScan := preload("res://addons/cybersunday_tools/dock_refs/ref_scan.gd")

const COLOR_FILE := Color(0.6, 0.85, 1.0)
const COLOR_LINE := Color(1, 1, 1, 0.6)

var _target: LineEdit = null
var _tree: Tree = null
var _summary: Label = null


func _init() -> void:
	name = "Refs"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	_target = LineEdit.new()
	_target.placeholder_text = "res://path/to/resource.tres"
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.tooltip_text = "The resource to find owners of. Type a res:// path or use 'Use selected'."
	_target.text_submitted.connect(func(_t): _find())
	bar.add_child(_target)
	var use_sel := Button.new()
	use_sel.text = "Use selected"
	use_sel.tooltip_text = "Fill from the file currently selected in the FileSystem dock."
	use_sel.pressed.connect(_use_selected)
	bar.add_child(use_sel)
	var find := Button.new()
	find.text = "Find refs"
	find.tooltip_text = "Scan the project for files that reference this resource (read-only)."
	find.pressed.connect(_find)
	bar.add_child(find)
	add_child(bar)

	_summary = Label.new()
	_summary.modulate = Color(1, 1, 1, 0.7)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)
	_tree.item_activated.connect(_on_activated)
	add_child(_tree)

	_summary.text = "Enter a res:// path (or pick one in FileSystem + Use selected), then Find refs."


## Fill the target from the FileSystem dock selection; clear, non-throwing message when nothing is selected.
func _use_selected() -> void:
	var sel := EditorInterface.get_selected_paths()
	if sel.is_empty():
		_summary.text = "Select a file in the FileSystem dock first, then 'Use selected'."
		return
	_target.text = sel[0]
	_summary.text = "Target set to %s — press Find refs." % sel[0]


## Scan + render. Fails soft: empty/missing target just updates the summary, never errors.
func _find() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var path := _target.text.strip_edges()
	if path.is_empty():
		_summary.text = "Enter a res:// path first (or pick one in FileSystem + Use selected)."
		return
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		_summary.text = "%s — not a res:// file on disk." % path
		return
	var refs := RefScan.find_referencers(path)
	for entry in refs:
		var file := String(entry["file"])
		var file_item := _tree.create_item(root)
		file_item.set_text(0, file)
		file_item.set_custom_color(0, COLOR_FILE)
		file_item.set_metadata(0, file)  # double-click opens the FILE
		for line in (entry["lines"] as PackedStringArray):
			var line_item := _tree.create_item(file_item)
			line_item.set_text(0, line)
			line_item.set_custom_color(0, COLOR_LINE)
			line_item.set_tooltip_text(0, line)
			line_item.set_metadata(0, file)  # double-click a context line opens its file too
	if refs.is_empty():
		_summary.text = "%s — NO references found by path/uid scanning. Likely safe to delete/rename (verify; the scan is text-based)." % path
	else:
		_summary.text = "%s — referenced by %d file(s). Double-click to open. Review ALL before deleting/renaming." % [path, refs.size()]


## Double-click a row: open the referring file (scene / resource / script) and reveal it in the FileSystem dock.
func _on_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var p := str(it.get_metadata(0))
	if not p.begins_with("res://"):
		return
	if p.get_extension() == "tscn":
		EditorInterface.open_scene_from_path(p)
	elif ResourceLoader.exists(p):
		EditorInterface.edit_resource(load(p))  # .gd opens in the script editor; a .tres in the Inspector
	EditorInterface.select_file(p)
