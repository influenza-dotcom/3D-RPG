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
	var vis := node.get_node_or_null(^"Visual")
	var pos := _viewport_focus()
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Place item: %s" % _item_label(it))
	ur.add_do_method(parent, "add_child", node)
	ur.add_do_reference(node)
	ur.add_do_property(node, "owner", root)  # owned -> saved into the scene
	if vis != null:
		ur.add_do_property(vis, "owner", root)  # the added Visual must be owned too, or it won't persist on save
	ur.add_do_property(node, "global_position", pos)  # drop it in front of the editor camera, not at the origin
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	_status.text = "Placed %s in front of the view — it's selected; drag to fine-tune, then SAVE the scene." % _item_label(it)


## Where to drop a placed item: ~3 m in front of the 3D editor camera so it lands in view (not at the world origin).
## Falls back to the origin if there's no open 3D viewport / camera.
func _viewport_focus() -> Vector3:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position - cam.global_basis.z * 3.0


## Build a ready CanPickUp for `it` with an AUTHORED, editor-visible "Visual" mesh child. CanPickUp's own
## build_model_from_item only builds the mesh at RUNTIME (its _ready bails in the editor), so a placed pickup would
## be invisible at edit time. We author the mesh here instead -- the item's world_model, else a glowing placeholder
## box -- so it shows in the editor AND saves, with build_model_from_item OFF so there's no runtime double-build.
func _make_pickup(it: Item) -> Node:
	if it == null:
		return null
	var ps := load(PICKUP_SCENE) as PackedScene
	if ps == null:
		return null
	var node := ps.instantiate()
	node.set(&"item", it)
	node.set(&"build_model_from_item", false)
	node.name = "Pickup_%s" % _item_label(it)
	var vis := _visual_for(it)
	vis.name = "Visual"
	node.add_child(vis)
	return node


## The world visual for an item: its world_model if set, else a glowing placeholder box (mirrors
## CanPickUp._default_item_visual) so a model-less item still shows something to see + position.
func _visual_for(it: Item) -> Node3D:
	var wm: Variant = it.get(&"world_model")
	if wm is PackedScene:
		var inst: Node = (wm as PackedScene).instantiate()
		if inst is Node3D:
			return inst as Node3D
		inst.free()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.25)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.8, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.7, 0.3)
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	return mi


static func _item_label(it: Item) -> String:
	if it == null:
		return "(null)"
	if it.id != &"":
		return String(it.id)
	if it.resource_path != "":
		return it.resource_path.get_file().get_basename()
	return str(it)
