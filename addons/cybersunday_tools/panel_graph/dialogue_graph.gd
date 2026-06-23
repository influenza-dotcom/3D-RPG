@tool
extends VBoxContainer

## "Graphs" bottom panel: a READ-ONLY visualizer for branching dialogue and quest chains. Pick a type
## (Dialogue vs Quest) + a resource, hit Build, and the GraphEdit fills with one GraphNode per dialogue
## line / quest, edges for choice targets + prereq/next links, and out-of-range / dangling targets called
## out in a status line. View-only -- connection editing, zoom-on-drag deletion etc. are all disabled.
##
## All graph BUILDING lives in graph_data.gd (pure, no editor APIs); this file is just the editor glue:
## resource discovery (a res:// scan), GraphNode rendering, layout-to-pixels, and FileSystem jump-back.
## Reuses graph_data for BOTH modes (the prompt's "one panel" option) so there's a single source of truth.

const GraphData := preload("res://addons/cybersunday_tools/panel_graph/graph_data.gd")

## Where authored content lives -- scanned to fill the resource picker. Free text fallback if a folder is absent.
const DIALOGUE_DIR := "res://resources/dialogue"
const QUEST_DIR := "res://resources/quests"

const COL_W := 320.0   # pixels between layout columns
const ROW_H := 150.0   # pixels between rows within a column
const PROBLEM_COLOR := Color(1.0, 0.42, 0.42)

var _mode: OptionButton = null
var _picker: OptionButton = null
var _status: Label = null
var _graph: GraphEdit = null
## Parallel to _picker items: the res:// path for each entry (so a selection maps back to a file).
var _paths: Array[String] = []


func _init() -> void:
	name = "Graphs"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	_mode = OptionButton.new()
	_mode.add_item("Dialogue")
	_mode.add_item("Quest")
	_mode.item_selected.connect(_on_mode_selected)
	bar.add_child(_mode)

	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.tooltip_text = "An authored resource to visualize. Refresh re-scans the folder."
	bar.add_child(_picker)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = "Re-scan the content folder for resources."
	refresh.pressed.connect(_refresh_picker)
	bar.add_child(refresh)

	var build := Button.new()
	build.text = "Build"
	build.pressed.connect(_build)
	bar.add_child(build)

	var reveal := Button.new()
	reveal.text = "Reveal"
	reveal.tooltip_text = "Open the selected resource + reveal it in the FileSystem dock."
	reveal.pressed.connect(_reveal_selected)
	bar.add_child(reveal)
	add_child(bar)

	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)

	_graph = GraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(0, 120)  # small floor so the bottom panel stays compact
	# View-only: no connecting, no right-click disconnect. (right_disconnects defaults false; be explicit.)
	_graph.right_disconnects = false
	_graph.show_grid = true
	add_child(_graph)

	_refresh_picker()
	_status.text = "Pick a resource and press Build."


## Mode flipped -- repopulate the picker from the matching folder.
func _on_mode_selected(_idx: int) -> void:
	_refresh_picker()


func _is_quest_mode() -> bool:
	return _mode != null and _mode.selected == 1


## Scan the active mode's folder and fill the resource picker. Quest mode lists individual quest .tres;
## Dialogue mode lists dialogue .tres. EditorInterface-free file IO so the scan itself stays testable-adjacent.
func _refresh_picker() -> void:
	_picker.clear()
	_paths.clear()
	var dir: String = QUEST_DIR if _is_quest_mode() else DIALOGUE_DIR
	var found: Array[String] = _scan_resources(dir)
	for p in found:
		_picker.add_item(p.get_file())
		_paths.append(p)
	if found.is_empty():
		_picker.add_item("(none found in %s)" % dir)
		_picker.set_item_disabled(0, true)


## Recursively collect *.tres / *.res under `dir`. Returns absolute res:// paths. Safe when the folder
## is missing (returns empty).
static func _scan_resources(dir: String, out: Array[String] = []) -> Array[String]:
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name == "." or name == "..":
			name = da.get_next()
			continue
		var full := dir.path_join(name)
		if da.current_is_dir():
			_scan_resources(full, out)
		elif name.ends_with(".tres") or name.ends_with(".res"):
			out.append(full)
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _selected_path() -> String:
	var idx := _picker.selected
	if idx < 0 or idx >= _paths.size():
		return ""
	return _paths[idx]


func _build() -> void:
	var path := _selected_path()
	if path == "" or not ResourceLoader.exists(path):
		_status.text = "No resource selected."
		return
	var res: Resource = load(path)
	if res == null:
		_status.text = "Failed to load %s" % path
		return
	var graph: Dictionary
	if _is_quest_mode():
		# Quest mode visualizes the selected quest PLUS any in the same folder (so prereq/next links resolve).
		graph = GraphData.build_quests(_load_quest_set(path))
	else:
		graph = GraphData.build_dialogue(res)
	_render(graph)


## Load every quest .tres in the selected quest's folder, so prereq_quest_id links can resolve to real nodes.
func _load_quest_set(selected_path: String) -> Array:
	var quests: Array = []
	var folder := selected_path.get_base_dir()
	for p in _scan_resources(folder):
		var r: Resource = load(p)
		# Duck-typed: a Quest has id + objectives. Skip non-quest resources sharing the folder.
		if r != null and r.get("objectives") != null and r.get("id") != null:
			quests.append(r)
	if quests.is_empty():
		var sel: Resource = load(selected_path)
		if sel != null:
			quests.append(sel)
	return quests


## Render a built graph into the GraphEdit: clear, drop one GraphNode per node positioned by the pure layout,
## then connect edges (best-effort -- GraphEdit needs ports, so every node gets one in + one out slot).
func _render(graph: Dictionary) -> void:
	_graph.clear_connections()
	for c in _graph.get_children():
		if c is GraphNode:
			_graph.remove_child(c)
			c.queue_free()

	var pos: Dictionary = GraphData.layout(graph)
	var nodes: Array = graph.get("nodes", [])
	var problems: Array = graph.get("problems", [])
	var problem_ids: Dictionary = {}
	for p in problems:
		problem_ids[String(p.get("node"))] = true

	# id -> the GraphNode name we gave it (GraphEdit connects by node NAME).
	var name_for: Dictionary = {}
	for n in nodes:
		var id: String = String(n.get("id"))
		var gn := GraphNode.new()
		gn.title = String(n.get("title"))
		gn.name = _safe_name(id)
		name_for[id] = gn.name
		# One in slot (left) + one out slot (right) so edges have ports. Enabled L/R, type 0.
		gn.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
		var body := Label.new()
		body.text = _trim(String(n.get("body")), 90)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(220, 0)
		gn.add_child(body)
		if problem_ids.has(id):
			gn.modulate = PROBLEM_COLOR
		var grid: Vector2 = pos.get(id, Vector2.ZERO)
		gn.position_offset = Vector2(grid.x * COL_W + 20.0, grid.y * ROW_H + 20.0)
		_graph.add_child(gn)

	for e in graph.get("edges", []):
		var from_id: String = String(e.get("from"))
		var to_id: String = String(e.get("to"))
		if name_for.has(from_id) and name_for.has(to_id):
			_graph.connect_node(String(name_for[from_id]), 0, String(name_for[to_id]), 0)

	var msg := "%d node(s), %d edge(s)" % [nodes.size(), graph.get("edges", []).size()]
	if not problems.is_empty():
		msg += " — %d problem(s): " % problems.size()
		var parts: Array[String] = []
		for p in problems:
			parts.append("%s: %s" % [String(p.get("node")), String(p.get("message"))])
		msg += "; ".join(parts)
		_status.add_theme_color_override("font_color", PROBLEM_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
	_status.text = msg


## GraphNode names must be unique + node-name-legal; map an arbitrary id to a safe stable name.
static func _safe_name(id: String) -> String:
	var s := id.replace("/", "_").replace(":", "_").replace(".", "_").replace(" ", "_")
	return s if s != "" else "node"


static func _trim(s: String, n: int) -> String:
	var one := s.replace("\n", " ").strip_edges()
	return one if one.length() <= n else one.substr(0, n) + "…"


func _reveal_selected() -> void:
	var path := _selected_path()
	if path == "":
		return
	if ResourceLoader.exists(path):
		EditorInterface.edit_resource(load(path))
	EditorInterface.select_file(path)
