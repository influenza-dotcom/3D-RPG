@tool
extends VBoxContainer

## Component-palette dock: a searchable, category-grouped list of every drop-in component (from core/catalog.gd),
## with one-click "Add to selected node". Kills the discoverability problem for the ~67-component catalog and makes
## the canonical components the path of least resistance. Adds are undo-able (EditorUndoRedoManager).
##
## add_mode "instance" -> load+instantiate the prefab; "child" -> build the script's native base (via the script's
## get_instance_base_type) and attach the script. The new node parents under the selected node (or the scene root).

const Catalog := preload("res://addons/cybersunday_tools/core/catalog.gd")

var _search: LineEdit = null
var _tree: Tree = null
var _desc: Label = null


func _init() -> void:
	name = "Palette"
	add_theme_constant_override("separation", 4)

	_search = LineEdit.new()
	_search.placeholder_text = "Search components…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _rebuild_tree())
	add_child(_search)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 220)
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_add)  # double-click = add
	add_child(_tree)

	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(0, 48)
	_desc.modulate = Color(1, 1, 1, 0.75)
	add_child(_desc)

	var add := Button.new()
	add.text = "Add to selected node"
	add.pressed.connect(_on_add)
	add_child(add)

	_rebuild_tree()


func _rebuild_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root_item := _tree.create_item()
	var filter := _search.text.strip_edges().to_lower()
	var cats := {}
	for row in Catalog.COMPONENTS:
		var label := str(row["class_name"])
		var desc := str(row.get("description", ""))
		if filter != "" and not (label.to_lower().contains(filter) or desc.to_lower().contains(filter)):
			continue
		var cat := str(row.get("category", "Misc"))
		if not cats.has(cat):
			var ci := _tree.create_item(root_item)
			ci.set_text(0, cat)
			ci.set_selectable(0, false)
			ci.set_custom_color(0, Color(0.6, 0.8, 1.0))
			cats[cat] = ci
		var it := _tree.create_item(cats[cat])
		it.set_text(0, label)
		it.set_metadata(0, row)


func _selected_row() -> Dictionary:
	var it := _tree.get_selected()
	if it == null:
		return {}
	var md: Variant = it.get_metadata(0)
	return md if md is Dictionary else {}


func _on_item_selected() -> void:
	var row := _selected_row()
	if row.is_empty():
		_desc.text = ""
		return
	_desc.text = "%s — %s" % [str(row.get("category", "")), str(row.get("description", ""))]


func _on_add() -> void:
	var row := _selected_row()
	if row.is_empty():
		return
	var node := _make_node(row)
	if node == null:
		_desc.text = "Couldn't build %s (missing scene/script?)." % str(row.get("class_name", "?"))
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		node.free()
		_desc.text = "Open a scene first, then add."
		return
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var parent: Node = sel[0] if not sel.is_empty() else root
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Add %s" % node.name)
	ur.add_do_method(parent, "add_child", node)
	ur.add_do_property(node, "owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	_desc.text = "Added %s under %s." % [node.name, parent.name]


## Build a fresh node for a catalog row (no editor calls -- unit-testable). "instance" instantiates the prefab;
## "child" builds the script's native base type and attaches the script. Returns null on any missing piece.
func _make_node(row: Dictionary) -> Node:
	var mode := str(row.get("add_mode", ""))
	if mode == "instance":
		var sc := str(row.get("scene_path", ""))
		if sc == "":
			return null
		var ps := load(sc) as PackedScene
		return ps.instantiate() if ps != null else null
	# "child": bare node of the script's native base + the script
	var sp := str(row.get("script_path", ""))
	if sp == "":
		return null
	var s := load(sp) as GDScript
	if s == null:
		return null
	var base := s.get_instance_base_type()
	if base == &"" or not ClassDB.can_instantiate(base):
		return null
	var node := ClassDB.instantiate(base) as Node
	if node == null:
		return null
	node.set_script(s)
	node.name = str(row.get("class_name", base))
	return node
