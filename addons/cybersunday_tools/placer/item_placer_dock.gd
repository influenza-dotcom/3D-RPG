@tool
extends VBoxContainer

## World item-placer dock: pick any authored Item and drop a ready CanPickUp for it into the scene -- the "find a
## stimpak in the world like Fallout" workflow, no manual node wiring. CanPickUp.build_model_from_item auto-fits the
## visual + collider, so the dropped pickup is immediately visible and lootable.
##
## It scans resources/items/ itself (the ItemDb autoload is non-@tool, so it's empty in the editor). The placed
## pickup parents under the selected node (or the scene root) and the add is undo-able; drag it into position after.

const ITEMS_DIR := "res://resources/items"
const PICKUP_SCENE := "res://scenes/components/can_pick_up.tscn"

var _list: ItemList = null
var _items: Array[Item] = []
var _status: Label = null


func _init() -> void:
	name = "Items"
	add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = "Drop a pickup for any item"
	add_child(head)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 200)
	_list.item_activated.connect(func(_i): _place())  # double-click = place
	add_child(_list)

	var place := Button.new()
	place.text = "Place selected in scene"
	place.pressed.connect(_place)
	add_child(place)

	var refresh := Button.new()
	refresh.text = "Refresh list"
	refresh.pressed.connect(_reload)
	add_child(refresh)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)

	_reload()


func _reload() -> void:
	_items = _scan_items()
	if _list == null:
		return
	_list.clear()
	for it in _items:
		_list.add_item(_item_label(it))
	if _status != null:
		_status.text = "%d item(s) — double-click or Place." % _items.size()


## Scan resources/items/ for Item .tres/.res (mirrors ItemDb's boot scan; the autoload itself is empty in-editor).
static func _scan_items() -> Array[Item]:
	var out: Array[Item] = []
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var fname := f.trim_suffix(".remap")
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		var it := load(ITEMS_DIR.path_join(fname)) as Item
		if it != null:
			out.append(it)
	return out


func _place() -> void:
	if _list == null:
		return
	var sel_idx := _list.get_selected_items()
	if sel_idx.is_empty():
		_status.text = "Pick an item from the list first."
		return
	var it := _items[sel_idx[0]]
	var node := _make_pickup(it)
	if node == null:
		_status.text = "Couldn't build the pickup (missing can_pick_up.tscn?)."
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		node.free()
		_status.text = "Open a scene first, then place."
		return
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var parent: Node = sel[0] if not sel.is_empty() else root
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Place item: %s" % _item_label(it))
	ur.add_do_method(parent, "add_child", node)
	ur.add_do_property(node, "owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	_status.text = "Placed %s under %s — drag it into position." % [_item_label(it), parent.name]


## Build a ready CanPickUp for `it` (no editor calls -- unit-testable). build_model_from_item makes it visible.
func _make_pickup(it: Item) -> Node:
	if it == null:
		return null
	var ps := load(PICKUP_SCENE) as PackedScene
	if ps == null:
		return null
	var node := ps.instantiate()
	node.set(&"item", it)
	node.set(&"build_model_from_item", true)
	node.name = "Pickup_%s" % _item_label(it)
	return node


static func _item_label(it: Item) -> String:
	if it == null:
		return "(null)"
	if it.id != &"":
		return String(it.id)
	if it.resource_path != "":
		return it.resource_path.get_file().get_basename()
	return str(it)
