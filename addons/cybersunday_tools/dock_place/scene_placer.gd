@tool
extends VBoxContainer

## CYBER SUNDAY "Place" tab: drop a whole NPC / level prefab into the EDITED scene in one click — the missing
## third leg of the dock. The Palette drops COMPONENTS onto an existing node; the Items tab drops world pickups;
## this tab drops the big SCENE PIECES a level is built from (an NPC, a PlayerSpawn marker, a LevelDoor, a loot
## Container) so a designer never has to hunt scenes/ in the FileSystem dock and drag-instance by hand.
##
## Each button instances the prefab, parents it under the SELECTED node (or the scene root), owns the subtree so it
## saves, drops it ~3 m in front of the editor camera, and selects it — all through EditorUndoRedoManager so it's a
## single undoable action. The NPC button also assigns an optional NpcData archetype (picked from a dropdown that
## scans resources/characters/) to the instance's `profile` export. A missing prefab is reported on the status
## label, never a crash. All pure subtree bookkeeping lives in place_ops.gd (GUT-tested headless).

const PlaceOps := preload("res://addons/cybersunday_tools/dock_place/place_ops.gd")

const NPC_SCENE := "res://scenes/enemies/NPC.tscn"
const PLAYER_SPAWN_SCENE := "res://scenes/world/PlayerSpawn.tscn"
const LEVEL_DOOR_SCENE := "res://scenes/components/level_door.tscn"
const DOOR_SCENE := "res://scenes/components/door.tscn"
const CONTAINER_SCENE := "res://scenes/components/container.tscn"

const CHARACTERS_DIR := "res://resources/characters"

var _profile_pick: OptionButton = null
var _profiles: Array[String] = []  # resource paths, index-aligned with the dropdown (index 0 = "(none)")
var _status: Label = null


func _init() -> void:
	name = "Place"
	custom_minimum_size = Vector2(110, 0)  # small floor so the tab stays narrow on a short display
	add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = "Drop a scene piece into the edited level"
	add_child(head)

	# NPC row: a profile dropdown + the place button.
	var profile_label := Label.new()
	profile_label.text = "NPC archetype (optional):"
	profile_label.modulate = Color(1, 1, 1, 0.75)
	add_child(profile_label)

	_profile_pick = OptionButton.new()
	_profile_pick.custom_minimum_size = Vector2(0, 0)
	add_child(_profile_pick)

	_add_button("Place NPC", _place_npc)
	_add_button("Place PlayerSpawn", _place_player_spawn)
	_add_button("Place LevelDoor", _place_level_door)
	_add_button("Place Door", _place_door)
	_add_button("Place Container", _place_container)

	var refresh := Button.new()
	refresh.text = "Refresh archetypes"
	refresh.pressed.connect(_reload_profiles)
	add_child(refresh)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_status)

	_reload_profiles()


func _add_button(text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	add_child(b)


## Scan resources/characters/ for NpcData .tres/.res and fill the dropdown. Index 0 is always "(none)". A row that
## loads but isn't an NpcData (e.g. a CharacterStats or NpcLook in the same folder) is skipped so the picker only
## offers real archetypes.
func _reload_profiles() -> void:
	if _profile_pick == null:
		return
	_profile_pick.clear()
	_profiles.clear()
	_profile_pick.add_item("(none)")
	_profiles.append("")  # keep _profiles index-aligned with the dropdown
	var dir := DirAccess.open(CHARACTERS_DIR)
	if dir != null:
		for f in dir.get_files():
			var fname := f.trim_suffix(".remap")
			if not (fname.ends_with(".tres") or fname.ends_with(".res")):
				continue
			var path := CHARACTERS_DIR.path_join(fname)
			var res := load(path)
			if res is NpcData:
				_profile_pick.add_item(fname.get_basename())
				_profiles.append(path)
	if _status != null:
		_status.text = "%d archetype(s). Pick a node (or none) and place." % (_profiles.size() - 1)


## The NpcData the dropdown currently points at, or null for "(none)" / a stale index.
func _selected_profile() -> NpcData:
	if _profile_pick == null:
		return null
	var idx := _profile_pick.get_selected()
	if idx <= 0 or idx >= _profiles.size():
		return null
	var path := _profiles[idx]
	if path == "":
		return null
	return load(path) as NpcData


func _place_npc() -> void:
	var node := _instance(NPC_SCENE, "NPC")
	if node == null:
		return
	var profile := _selected_profile()
	if profile != null and node is NPC:
		(node as NPC).profile = profile
	_finish_place(node, "NPC" if profile == null else "NPC [%s]" % _profile_pick.get_item_text(_profile_pick.get_selected()))


func _place_player_spawn() -> void:
	var node := _instance(PLAYER_SPAWN_SCENE, "PlayerSpawn")
	if node == null:
		return
	_finish_place(node, "PlayerSpawn")


func _place_level_door() -> void:
	var node := _instance(LEVEL_DOOR_SCENE, "LevelDoor")
	if node == null:
		return
	_finish_place(node, "LevelDoor")


func _place_door() -> void:
	var node := _instance(DOOR_SCENE, "Door")
	if node == null:
		return
	_finish_place(node, "Door")


func _place_container() -> void:
	var node := _instance(CONTAINER_SCENE, "Container")
	if node == null:
		return
	_finish_place(node, "Container")


## Load + instance a prefab. Reports a missing/broken scene on the status label and returns null (no crash) so the
## button is inert rather than fatal when a path drifts.
func _instance(path: String, label: String) -> Node:
	if not ResourceLoader.exists(path):
		_status.text = "%s scene not found: %s" % [label, path]
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		_status.text = "%s is not a PackedScene: %s" % [label, path]
		return null
	var node := ps.instantiate()
	if node == null:
		_status.text = "Couldn't instantiate %s (%s)." % [label, path]
		return null
	return node


## Shared tail: parent under the selection (or root), own the subtree so it saves, drop it in front of the camera,
## select it — one undoable action. Frees the orphan and reports if no scene is open.
func _finish_place(node: Node, label: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		node.free()
		_status.text = "Open a scene first, then place %s." % label
		return
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var parent: Node = sel[0] if not sel.is_empty() else root
	var pos := _viewport_focus()
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Place %s" % label)
	ur.add_do_method(parent, "add_child", node)
	ur.add_do_reference(node)
	ur.add_do_method(PlaceOps, "own_recursive", node, root)  # own the whole subtree so every node saves
	if node is Node3D:
		ur.add_do_property(node, "global_position", pos)  # drop it in front of the editor camera, not the origin
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	var where := "under %s" % parent.name if parent != root else "under the scene root"
	_status.text = "Placed %s %s, in front of the view — selected; drag to fine-tune, then SAVE." % [label, where]


## ~3 m in front of the 3D editor camera so a placed piece lands in view (not at the world origin). Falls back to
## the origin if there's no open 3D viewport / camera.
func _viewport_focus() -> Vector3:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position - cam.global_basis.z * 3.0
