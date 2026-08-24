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
const CsgBlockout := preload("res://addons/cybersunday_tools/dock_place/csg_blockout.gd")

const NPC_SCENE := "res://scenes/characters/NPC.tscn"
const PLAYER_SPAWN_SCENE := "res://scenes/world/PlayerSpawn.tscn"
const LEVEL_DOOR_SCENE := "res://scenes/components/level_door.tscn"
const DOOR_SCENE := "res://scenes/components/door.tscn"
const CONTAINER_SCENE := "res://scenes/components/container.tscn"

const CHARACTERS_DIR := "res://resources/characters"

var _profile_pick: OptionButton = null
var _profiles: Array[String] = []  # resource paths, index-aligned with the dropdown (index 0 = "(none)")
var _status: Label = null

var _snap_pick: OptionButton = null
const SNAP_VALUES: Array[float] = [0.0, 0.5, 1.0, 2.0]  # index-aligned with the snap dropdown (0 = Off)
var _body: VBoxContainer = null  ## scrollable body — all placement controls live here so a growing button list scrolls inside the tab instead of forcing the whole bottom panel taller (the content_dock.gd pattern)

## Lazy first-reveal latch — the archetype scan (which LOADS every file under resources/characters/ to type-test it)
## runs on first reveal, not at panel construction. cyber_panel._init() builds all 22 tabs eagerly and the editor
## reconstructs the panel on every plugin reload, so an _init-time scan costs a full folder load on every editor
## start even when this tab is never opened. Mirrors content_browser / tuning_browser / item_placer_dock.
var _revealed := false


func _init() -> void:
	name = "Place"
	custom_minimum_size = Vector2(110, 0)  # small floor so the tab stays narrow on a short display
	add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = "Drop a scene piece into the edited level"
	add_child(head)

	# The control list lives in a ScrollContainer with a small height floor (the content_dock.gd pattern) so it can
	# NEVER force the shared bottom panel taller than the screen — the panel sizes to its tallest tab. head + status
	# stay outside the scroll (always visible); everything placeable scrolls in `_body`.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 120)
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)

	# NPC row: a profile dropdown + the place button.
	var profile_label := Label.new()
	profile_label.text = "NPC archetype (optional):"
	profile_label.modulate = Color(1, 1, 1, 0.75)
	_body.add_child(profile_label)

	_profile_pick = OptionButton.new()
	_profile_pick.custom_minimum_size = Vector2(0, 0)
	_body.add_child(_profile_pick)

	_add_button("Place NPC", _place_npc)
	_add_button("Place PlayerSpawn", _place_player_spawn)
	_add_button("Place LevelDoor", _place_level_door)
	_add_button("Place Door", _place_door)
	_add_button("Place Container", _place_container)

	var refresh := Button.new()
	refresh.text = "Refresh archetypes"
	refresh.pressed.connect(_reload_profiles)
	_body.add_child(refresh)

	# --- Blockout (CSG) -------------------------------------------------------------------------------------
	# Carve the walkable SHELL of a level — floors, walls, ramps, enterable building shells — as native CSG. CSG
	# feeds the level's `navmesh`-group bake in 4.6 (verified), so these drop straight into the existing bake +
	# audit with no new pipeline. The room shell is walls-only with a >=2.4 m doorway (so the interior stays ONE
	# navmesh island on the open ground). Pure construction lives in csg_blockout.gd (GUT-tested headless).
	# Guidance lives in tooltips (not a tall always-on hint label) to keep the tab short.
	_body.add_child(HSeparator.new())
	var blk_head := Label.new()
	blk_head.text = "Blockout (CSG)"
	blk_head.tooltip_text = "Carve walkable shell geometry. Pieces join the `navmesh` group — re-Bake the NavigationRegion3D after placing, and tidy them under `Geometry`. Doorways need >=2.4 m clear or the interior bakes as its own island."
	_body.add_child(blk_head)

	# Grid snap: label + dropdown on one row to save height.
	var snap_row := HBoxContainer.new()
	_body.add_child(snap_row)
	var snap_label := Label.new()
	snap_label.text = "Grid snap (X/Z):"
	snap_label.modulate = Color(1, 1, 1, 0.75)
	snap_row.add_child(snap_label)
	_snap_pick = OptionButton.new()
	_snap_pick.add_item("Off")     # index 0 -> SNAP_VALUES[0] == 0.0
	_snap_pick.add_item("0.5 m")
	_snap_pick.add_item("1 m")
	_snap_pick.add_item("2 m")
	_snap_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snap_row.add_child(_snap_pick)

	_add_button("Place Building Shell + door", _place_room_shell)
	# Floor / Wall / Ramp share one row to keep the tab short; tooltips carry the detail.
	var prim_row := HBoxContainer.new()
	_body.add_child(prim_row)
	_add_row_button(prim_row, "Floor", _place_floor, "Place a CSG floor slab (navmesh group + collision).")
	_add_row_button(prim_row, "Wall", _place_wall, "Place a CSG wall (navmesh group + collision).")
	_add_row_button(prim_row, "Ramp", _place_ramp, "Place a walkable CSG ramp (slope auto-clamped under agent_max_slope).")
	_add_button("Snap Selected to Grid", _snap_selected)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)  # outside the scroll so the current status is always visible

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan resources/characters on first reveal, not at panel construction


## Lazy first-reveal: run the archetype folder scan ONCE, the first time the tab is actually shown.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_reload_profiles()


func _add_button(text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	_body.add_child(b)


## A compact button that shares a horizontal row (Floor/Wall/Ramp), expanding to split the row evenly.
func _add_row_button(row: HBoxContainer, text: String, handler: Callable, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	row.add_child(b)


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
	var pos := _snapped(_viewport_focus())
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


# --- Blockout (CSG) placement -----------------------------------------------------------------------------------
# Each builds a self-contained CSG piece OFF-tree (already in the `navmesh` group, use_collision on, doorway sized so
# the interior stays one navmesh island) and hands it to the shared _finish_place glue: parented under the selection
# (select `Geometry`/`Blockout` first) or the root, owned so it saves, dropped in front of the camera (grid-snapped),
# selected, one undo. Re-bake the NavigationRegion3D after placing — these change the bake, not the runtime.

func _place_room_shell() -> void:
	_finish_place(CsgBlockout.build_room_shell(), "Building shell (CSG)")

func _place_floor() -> void:
	_finish_place(CsgBlockout.build_floor(), "Floor slab (CSG)")

func _place_wall() -> void:
	_finish_place(CsgBlockout.build_wall(), "Wall (CSG)")

func _place_ramp() -> void:
	_finish_place(CsgBlockout.build_ramp(), "Ramp (CSG)")


## The active grid increment in metres (0 = Off), from the snap dropdown.
func _snap_value() -> float:
	if _snap_pick == null:
		return 0.0
	var i := _snap_pick.get_selected()
	return SNAP_VALUES[i] if i >= 0 and i < SNAP_VALUES.size() else 0.0

## Snap a placement position to the X/Z grid (height is left alone — blockout pieces define their own base height).
func _snapped(pos: Vector3) -> Vector3:
	var s := _snap_value()
	if s <= 0.0:
		return pos
	return Vector3(roundf(pos.x / s) * s, pos.y, roundf(pos.z / s) * s)

## Round the selected 3D nodes' X/Z onto the current grid (one undoable action) so hand-placed floors/walls tile
## flush — gaps between floor pieces are the root cause of navmesh island fragmentation.
func _snap_selected() -> void:
	var s := _snap_value()
	if s <= 0.0:
		_status.text = "Pick a grid increment first (not Off), then Snap Selected."
		return
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var movers: Array[Node3D] = []
	for n in sel:
		if n is Node3D:
			movers.append(n as Node3D)
	if movers.is_empty():
		_status.text = "Select one or more 3D nodes to snap to the grid."
		return
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Snap to grid")
	for n in movers:
		var p := n.global_position
		var target := Vector3(roundf(p.x / s) * s, p.y, roundf(p.z / s) * s)
		ur.add_do_property(n, "global_position", target)
		ur.add_undo_property(n, "global_position", p)
	ur.commit_action()
	_status.text = "Snapped %d node(s) to the %.2f m grid." % [movers.size(), s]
