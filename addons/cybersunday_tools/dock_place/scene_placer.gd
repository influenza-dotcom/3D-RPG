@tool
extends VBoxContainer

## CYBER SUNDAY "Place" tab (Build group): drop a whole NPC / level prefab into the EDITED scene in one click — the
## third leg of the dock. The Palette drops COMPONENTS onto an existing node; the Place Item tab drops world pickups;
## this tab drops the big SCENE PIECES a level is built from (an NPC, a PlayerSpawn marker, a LevelDoor, a Door, a
## loot Container, and the CSG blockout shell — floors, walls, ramps, building shells) so a designer never has to
## hunt scenes/ in the FileSystem dock and drag-instance by hand.
##
## Each button instances (or builds) the piece, parents it under the node SELECTED in the Scene tree (or the scene
## root), owns the subtree so it saves, drops it ~3 m in front of the editor camera, and selects it — all through
## EditorUndoRedoManager so it is a single undoable action. The NPC button also assigns an optional NpcData archetype
## (picked from a dropdown that scans resources/characters/) to the instance's `profile` export. A missing prefab is
## reported on the status label, never a crash. All pure subtree bookkeeping lives in place_ops.gd and the CSG
## builders in csg_blockout.gd (both GUT-tested headless).
##
## Three placement rules a reader must know before touching _finish_place:
##   * SIBLING RULE — placing selects what it just placed, so a second press would nest the new piece INSIDE the
##     first (NPC inside NPC, wall inside floor). The tab therefore remembers (weakly) the node it placed last and
##     every CSG piece it placed; when the selection IS one of those, the new piece goes under that node's PARENT —
##     a sibling — and the status says so. Any other selection is a deliberate parent and is honoured as before.
##   * GROUND — the four CSG pieces raycast straight down from 5 m above the camera-focus point and land on
##     whatever they hit (the level floor, an earlier slab); no hit means height 0, the template's ground plane.
##     Prefabs keep the camera-focus height (an NPC or a door is dragged into place anyway). Editor-only: the probe
##     reads the edited scene's World3D from a button handler, never from _init (off-tree that call RAISES).
##   * SCENE GATE — on_scene_changed(root) from the host (cyber_panel.gd, forwarded from EditorPlugin.scene_changed
##     and once at enable) greys every button that needs an open scene with "Open a scene first" BEFORE a click;
##     the handler's own root check stays as the fallback for a click that lands between two scene switches.
##
## Handoff: select_path(path) is what the New / Blueprints tabs call after creating an archetype — it rescans and
## points the dropdown at that file. The editor's filesystem_changed signal only FLAGS the list stale; the rescan
## waits for the tab's next reveal (never mid-edit while visible) and keeps the picked archetype BY PATH, never by
## index. The Refresh button is the explicit fallback.
##
## Off-tree contract: GUT and the headless probe construct this tab bare (.new(), no parent, no tree), so _init makes
## no editor call outside the Engine.is_editor_hint() guard — every EditorInterface use lives in a button handler,
## in the first-reveal latch, or behind that guard.

const PlaceOps := preload("res://addons/cybersunday_tools/dock_place/place_ops.gd")
const CsgBlockout := preload("res://addons/cybersunday_tools/dock_place/csg_blockout.gd")
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")

const NPC_SCENE := "res://scenes/characters/NPC.tscn"
const PLAYER_SPAWN_SCENE := "res://scenes/world/PlayerSpawn.tscn"
const LEVEL_DOOR_SCENE := "res://scenes/components/level_door.tscn"
const DOOR_SCENE := "res://scenes/components/door.tscn"
const CONTAINER_SCENE := "res://scenes/components/container.tscn"

const CHARACTERS_DIR := "res://resources/characters"

## Idle status: the one next step. "Select" = the Scene tree (Godot's own UI); "Pick" is reserved for this tab's lists.
const MSG_IDLE := "Select a parent node (or nothing for the scene root), then place -- pieces land in front of the camera."
## Disabled-button tooltip while no scene is open (the host's on_scene_changed gate); the click-time status fallback
## is the fuller MSG_NO_SCENE_STATUS.
const MSG_NO_SCENE := "Open a scene first"
const MSG_NO_SCENE_STATUS := "Open a scene first, then place."
## The amber the inspector warnings use (npcdata_inspector / weapondata_inspector), so a scan problem reads the same
## everywhere in the dock.
const WARN_COLOR := Color(1.0, 0.82, 0.3)

## Ground probe for the CSG pieces: the ray starts GROUND_PROBE_UP metres above the (snapped) camera-focus point so a
## focus point that sits just under a slab's top still finds it, and runs GROUND_PROBE_LENGTH metres down so a
## camera hovering high above the map still reaches the floor. A miss lands the piece at height 0.
const GROUND_PROBE_UP := 5.0
const GROUND_PROBE_LENGTH := 500.0

var _profile_pick: OptionButton = null
## Archetype file paths from the last scan (dropdown row i+1 carries _profile_paths[i] as its metadata; row 0 is
## "(none)"). Kept so select_path / the fs-refresh can re-point the dropdown BY PATH after a rebuild.
var _profile_paths: PackedStringArray = PackedStringArray()
## Files under resources/characters/ that failed to load on the last scan — reported in the warn colour so a broken
## archetype is visible from this tab instead of silently missing from the dropdown.
var _scan_failed := 0
var _status: Label = null

var _snap_pick: OptionButton = null
const SNAP_VALUES: Array[float] = [0.0, 0.5, 1.0, 2.0]  # index-aligned with the snap dropdown (0 = Off)
var _body: VBoxContainer = null  ## scrollable body — every placement control lives here so a growing button list scrolls inside the tab instead of forcing the shared bottom panel taller (the content_dock.gd pattern)

## Every button that needs an open scene (the place buttons + Snap Selected). on_scene_changed greys them all and
## swaps their tooltip for MSG_NO_SCENE; each keeps its real tooltip in the "tip" meta so it can be restored.
var _scene_buttons: Array[Button] = []
## Mirrors the host's on_scene_changed(root). The handlers re-read the live edited-scene root themselves (the editor
## is the source of truth); this flag only drives the button state.
var _scene_open := false

## SIBLING RULE state — weak on purpose: the editor owns these nodes (and undo may free them); the tab must never
## keep one alive. _last_placed is whatever this tab placed last; _placed_csg is every CSG piece it placed this
## session, because a designer tiling floors clicks Floor / Floor / Wall with the previous piece still selected.
var _last_placed: WeakRef = null
var _placed_csg: Array[WeakRef] = []

## Lazy first-reveal latch — the archetype scan (which LOADS every file under resources/characters/ to type-test it)
## runs on first reveal, not at panel construction. cyber_panel._init() builds every tab eagerly and the editor
## reconstructs the panel on every plugin reload, so an _init-time scan costs a full folder load on every editor
## start even when this tab is never opened. Mirrors content_browser / tuning_browser / item_placer_dock.
var _revealed := false
## Set by the editor's filesystem_changed (a file under resources/ was added, removed or reimported). The rescan runs
## on the NEXT in-tree reveal, never while the tab is visible mid-edit, and keeps the selection by path.
var _fs_dirty := false


func _init() -> void:
	name = "Place"
	custom_minimum_size = Vector2(110, 0)  # small floor so the tab stays narrow on a short display
	add_theme_constant_override("separation", 4)

	# Action bar (outside the scroll): the archetype dropdown + Refresh on one row. No heading — the tab title
	# already says "Place".
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	add_child(top)
	var profile_label := Label.new()
	profile_label.text = "NPC archetype:"
	profile_label.modulate = Color(1, 1, 1, 0.75)
	profile_label.tooltip_text = "Optional. The archetype stamped onto the next NPC you place -- files come from resources/characters/."
	top.add_child(profile_label)
	_profile_pick = OptionButton.new()
	_profile_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Width guards (rule of every dropdown in the dock): the ScrollContainer below disables horizontal scroll, so an
	# unclamped dropdown would widen the whole editor to its longest row. PickerRows.apply re-asserts both on fill.
	_profile_pick.fit_to_longest_item = false
	_profile_pick.clip_text = true
	_profile_pick.tooltip_text = "Optional. The archetype stamped onto the next NPC you place -- files come from resources/characters/. (none) places a plain NPC."
	top.add_child(_profile_pick)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = "Re-reads the archetype list from resources/characters/; what you picked stays picked. Read-only."
	refresh.pressed.connect(_on_refresh_pressed)
	top.add_child(refresh)

	# The control list lives in a ScrollContainer with a small height floor (the content_dock.gd pattern) so it can
	# NEVER force the shared bottom panel taller than the screen: a TabContainer's minimum is the CURRENT tab's
	# minimum, and the editor's bottom splitter keeps the height it grew to. Action bar + status stay outside the
	# scroll (always visible); everything placeable scrolls in `_body`.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 100)
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)

	_add_button("Place NPC", _place_npc,
		"Place an NPC using the archetype above, in front of the camera. Writes: the open scene.")
	_add_button("Place PlayerSpawn", _place_player_spawn,
		"Where the player appears; set entry_id so doors can target it. Writes: the open scene.")
	_add_button("Place LevelDoor", _place_level_door,
		"A door that travels to a different level -- set its level after placing. Writes: the open scene.")
	_add_button("Place Door", _place_door,
		"A door that swings open inside this level. Writes: the open scene.")
	_add_button("Place Container", _place_container,
		"A lootable box -- assign a loot table in the Inspector. Writes: the open scene.")

	# --- Blockout (CSG) -------------------------------------------------------------------------------------
	# Carve the walkable SHELL of a level — floors, walls, ramps, enterable building shells — as native CSG. CSG
	# feeds the level's `navmesh`-group bake in 4.6 (verified), so these drop straight into the existing bake +
	# audit with no new pipeline. The room shell is walls-only with a >=2.4 m doorway (so the interior stays ONE
	# navmesh island on the open ground). Pure construction lives in csg_blockout.gd (GUT-tested headless).
	# Guidance lives in tooltips (not a tall always-on hint label) to keep the tab short.
	_body.add_child(HSeparator.new())
	var blk_head := Label.new()
	blk_head.text = "Blockout"
	blk_head.modulate = Color(1, 1, 1, 0.75)
	blk_head.tooltip_text = "Rough walkable geometry: a floor, a wall, a ramp or a whole building shell. Every piece lands on the ground under the camera and joins the navmesh group -- re-bake afterwards (Level -> Bake + Check Navmesh). Doorways need at least 2.4 m clear or NPCs can't path inside."
	_body.add_child(blk_head)

	# Grid snap: label + dropdown on one row to save height.
	var snap_row := HBoxContainer.new()
	_body.add_child(snap_row)
	var snap_label := Label.new()
	snap_label.text = "Grid snap (X/Z):"
	snap_label.modulate = Color(1, 1, 1, 0.75)
	snap_label.tooltip_text = "Grid step for new pieces and for Snap Selected to Grid. Off places exactly where the camera looks."
	snap_row.add_child(snap_label)
	_snap_pick = OptionButton.new()
	_snap_pick.add_item("Off")     # index 0 -> SNAP_VALUES[0] == 0.0
	_snap_pick.add_item("0.5 m")
	_snap_pick.add_item("1 m")
	_snap_pick.add_item("2 m")
	_snap_pick.fit_to_longest_item = false  # same width guard as the archetype dropdown (horizontal scroll is off)
	_snap_pick.clip_text = true
	_snap_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snap_pick.tooltip_text = "Grid step for new pieces and for Snap Selected to Grid -- floors and walls only tile flush when they share a step. Off places exactly where the camera looks."
	snap_row.add_child(_snap_pick)

	_add_button("Place Building Shell", _place_room_shell,
		"Four walls with a doorway and no floor -- lands on the ground under the camera; re-bake the navmesh afterwards. Writes: the open scene.")
	# Floor / Wall / Ramp share one row to keep the tab short; tooltips carry the detail.
	var prim_row := HBoxContainer.new()
	_body.add_child(prim_row)
	_add_row_button(prim_row, "Floor", _place_floor,
		"A flat floor slab -- lands on the ground under the camera; re-bake the navmesh afterwards. Writes: the open scene.")
	_add_row_button(prim_row, "Wall", _place_wall,
		"A single wall -- lands on the ground under the camera; re-bake the navmesh afterwards. Writes: the open scene.")
	_add_row_button(prim_row, "Ramp", _place_ramp,
		"A walkable ramp, never steeper than NPCs can climb -- lands on the ground under the camera; re-bake the navmesh afterwards. Writes: the open scene.")
	_add_button("Snap Selected to Grid", _snap_selected,
		"Rounds the selected 3D nodes onto the grid step above so floors and walls tile flush. Writes: the open scene.")

	# The ONE status row, outside the scroll so it is always visible. Two lines max; the tooltip mirrors the full
	# text on every write (_set_status) so a long placement report is never lost.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_IDLE)

	# Editor-only wiring, guarded so the bare off-tree construction (GUT / the headless probe) never touches
	# EditorInterface: the filesystem signal only FLAGS the archetype list stale (see _fs_dirty).
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan resources/characters on first reveal, not at panel construction


## Lazy first-reveal: run the archetype folder scan ONCE, the first time the tab is actually shown, and sync the
## scene gate from the editor (a tab built after plugin.gd's enable-time on_scene_changed call would otherwise show
## live buttons with no scene open). Later reveals rescan only when the filesystem flagged the list stale, keeping
## the picked archetype by path.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_reload_profiles()
		_report_scan(MSG_IDLE)
		if Engine.is_editor_hint():
			on_scene_changed(EditorInterface.get_edited_scene_root())
	elif is_visible_in_tree() and _fs_dirty:
		_reload_profiles()
		_report_scan(MSG_IDLE)


## EditorFileSystem.filesystem_changed: something under res:// changed. Only flag it — the rescan waits for the next
## reveal so a designer mid-edit never has the dropdown rebuilt under the mouse.
func _on_filesystem_changed() -> void:
	_fs_dirty = true


## Host seam (cyber_panel.on_scene_changed, forwarded from EditorPlugin.scene_changed and once at enable): grey every
## button that needs an open scene while none is open. `root` may be null (every scene closed). is_instance_valid
## guards a stale root handed over mid-close — a freed Object compares unequal to null in GDScript.
func on_scene_changed(root: Node) -> void:
	_scene_open = is_instance_valid(root)
	for b in _scene_buttons:
		b.disabled = not _scene_open
		b.tooltip_text = String(b.get_meta(&"tip", "")) if _scene_open else MSG_NO_SCENE


## Handoff seam (Host.open_in_editor -> cyber_panel.open_in_editor -> here): rescan the archetypes and point the
## dropdown at the NpcData at `path`. true when the file is in the list; false (and a status line) when it isn't —
## the host then opens it in the Inspector instead.
func select_path(path: String) -> bool:
	_reload_profiles(path)
	var found := _profile_paths.has(path)
	if found:
		_report_scan("Picked %s -- Place NPC drops one in front of the camera." % path.get_file().get_basename())
	else:
		_report_scan("Couldn't pick %s: it isn't an archetype in resources/characters/." % path.get_file())
	return found


func _on_refresh_pressed() -> void:
	_reload_profiles()
	_report_scan("Refreshed archetypes -- %d found." % _profile_paths.size())


## A full-width place button. `tip` is its real tooltip; it is parked in the "tip" meta so on_scene_changed can swap
## in MSG_NO_SCENE while no scene is open and restore it afterwards.
func _add_button(text: String, handler: Callable, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.set_meta(&"tip", tip)
	b.pressed.connect(handler)
	_body.add_child(b)
	_scene_buttons.append(b)


## A compact button that shares a horizontal row (Floor/Wall/Ramp), expanding to split the row evenly. Same
## scene-gate registration as _add_button.
func _add_row_button(row: HBoxContainer, text: String, handler: Callable, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.set_meta(&"tip", tip)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	row.add_child(b)
	_scene_buttons.append(b)


## Write the status row: text + a mirrored tooltip (the label clamps to two lines), amber when `warn`.
func _set_status(msg: String, warn: bool = false) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")


## Status after a scan: `base` plus, when files failed to load, the failure count in the warn colour.
func _report_scan(base: String) -> void:
	if _scan_failed > 0:
		_set_status("%s -- %d file(s) failed to load (broken reference? press Refresh)" % [base, _scan_failed], true)
	else:
		_set_status(base)


## Scan resources/characters/ for NpcData .tres/.res and fill the dropdown through PickerRows (row 0 is always
## "(none)"; each row's metadata is its file path). A file that loads but isn't an NpcData (a CharacterStats or
## NpcLook in the same folder) is skipped silently; a file that fails to load is COUNTED (_scan_failed) so the
## status can name the problem. The dropdown is re-pointed BY PATH — `want`, else whatever was picked before the
## rebuild — never by index, so a file added or removed above the pick can't shift it onto a different archetype.
## Clears _fs_dirty: this IS the rescan the filesystem flag asks for.
func _reload_profiles(want: String = "") -> void:
	if _profile_pick == null:
		return
	if want == "":
		want = _selected_profile_path()
	_fs_dirty = false
	_scan_failed = 0
	_profile_paths = PackedStringArray()
	var labels := PackedStringArray()
	var dir := DirAccess.open(CHARACTERS_DIR)
	if dir != null:
		for f in dir.get_files():
			var fname := f.trim_suffix(".remap")
			if not (fname.ends_with(".tres") or fname.ends_with(".res")):
				continue
			var path := CHARACTERS_DIR.path_join(fname)
			var res := load(path)
			if res == null:
				_scan_failed += 1
				continue
			if res is NpcData:
				_profile_paths.append(path)
				labels.append(fname.get_basename())
	# `current` = "" when the wanted path is gone: path_rows would otherwise mint a disabled row for it, and a
	# placement can't use a row it can't load — falling back to "(none)" is the honest answer.
	var rows := PickerRows.path_rows(_profile_paths, labels, want if _profile_paths.has(want) else "", false)
	PickerRows.apply(_profile_pick, rows, want)


## The file path behind the dropdown's current row ("" for "(none)", an empty picker, or a stale index).
func _selected_profile_path() -> String:
	if _profile_pick == null:
		return ""
	var idx := _profile_pick.get_selected()
	if idx < 0 or idx >= _profile_pick.item_count:
		return ""
	var md: Variant = _profile_pick.get_item_metadata(idx)
	return String(md) if md is String else ""


## The NpcData the dropdown currently points at, or null for "(none)" / a file that no longer loads.
func _selected_profile() -> NpcData:
	var path := _selected_profile_path()
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
	var arche := _selected_profile_path().get_file().get_basename() if profile != null else ""
	_finish_place(node, "NPC" if arche == "" else "NPC (%s)" % arche)


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


## Load + instance a prefab. Reports a missing/broken scene on the status label (by file name — the full path is a
## code detail) and returns null, so the button is inert rather than fatal when a path drifts.
func _instance(path: String, label: String) -> Node:
	if not ResourceLoader.exists(path):
		_set_status("Couldn't place %s: its scene file is missing (%s)." % [label, path.get_file()], true)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		_set_status("Couldn't place %s: %s isn't a scene file." % [label, path.get_file()], true)
		return null
	var node := ps.instantiate()
	if node == null:
		_set_status("Couldn't place %s: %s failed to open." % [label, path.get_file()], true)
		return null
	return node


## Shared tail: parent under the selection (or root — see the SIBLING RULE in the header), own the subtree so it
## saves, drop it in front of the camera (on the ground for a CSG piece when `on_ground`), select it — one undoable
## action. Frees the orphan and reports if no scene is open. `label` names the piece in the undo history; the
## status prints the node's final Scene-tree name (possibly de-duplicated by add_child) plus the NPC's archetype.
func _finish_place(node: Node, label: String, on_ground: bool = false) -> void:
	var root := EditorInterface.get_edited_scene_root()
	on_scene_changed(root)  # keep the button state honest with what this click just observed
	if root == null:
		node.free()
		_set_status(MSG_NO_SCENE_STATUS)
		return
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var picked: Node = sel[0] if not sel.is_empty() else null
	var parent := _parent_for(picked, root)
	var pos := _snapped(_viewport_focus())
	var grounded := false
	if on_ground:
		var probe := _ground_under(pos, root)
		var gp: Vector3 = probe["pos"]
		pos = gp
		grounded = bool(probe["hit"])
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
	_remember_placement(node)
	# "NPC (raider)" keeps its archetype suffix behind the real node name: "NPC2 (raider)".
	var paren := label.find("(")
	var shown := String(node.name) if paren < 0 else "%s %s" % [node.name, label.substr(paren)]
	var where := _where_text(parent, picked, root)
	if not on_ground:
		_set_status("Placed %s %s, in front of the camera -- selected; drag to fine-tune, then save the scene (Ctrl+S)." % [shown, where])
	elif grounded:
		_set_status("Placed %s on the ground %s -- selected; drag to fine-tune, then save the scene (Ctrl+S). To drop existing pieces onto the floor select them and press Page Down. Re-bake: Level -> Bake + Check Navmesh." % [shown, where])
	else:
		_set_status("Placed %s %s -- no ground under the camera, placed at height 0. Selected; drag to fine-tune, then save the scene (Ctrl+S). To drop existing pieces onto the floor select them and press Page Down. Re-bake: Level -> Bake + Check Navmesh." % [shown, where])


## SIBLING RULE: the parent for a new piece. No selection -> the scene root. A selection that is something THIS TAB
## placed (the last piece, or any CSG piece) -> that node's parent, so repeated presses line pieces up as siblings
## instead of nesting each inside the previous one. Anything else -> the selection, a deliberate parent.
func _parent_for(picked: Node, root: Node) -> Node:
	if picked == null or not is_instance_valid(picked):
		return root
	if _placed_by_this_tab(picked):
		var p := picked.get_parent()
		return p if p != null else root
	return picked


## Where the piece went, for the status: "under the scene root" / "under Geometry" / "beside BlockoutFloor, under
## Geometry" when the sibling rule redirected it.
func _where_text(parent: Node, picked: Node, root: Node) -> String:
	var under := "under the scene root" if parent == root else "under %s" % parent.name
	if picked != null and is_instance_valid(picked) and parent != picked:
		return "beside %s, %s" % [picked.name, under]
	return under


## Remember what was just placed (weakly) for the sibling rule. CSGCombiner3D extends CSGShape3D, so one type test
## covers every blockout piece. Dead refs (undone + freed pieces) are pruned here so the list can't grow forever.
func _remember_placement(node: Node) -> void:
	_last_placed = weakref(node)
	var alive: Array[WeakRef] = []
	for w in _placed_csg:
		if w.get_ref() != null:
			alive.append(w)
	_placed_csg = alive
	if node is CSGShape3D:
		_placed_csg.append(weakref(node))


func _placed_by_this_tab(n: Node) -> bool:
	if _last_placed != null and _last_placed.get_ref() == n:
		return true
	for w in _placed_csg:
		if w.get_ref() == n:
			return true
	return false


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


## GROUND probe (CSG pieces only, handler-only — needs the edited scene in the editor's World3D): raycast straight
## down from GROUND_PROBE_UP above `pos` and return {"pos": Vector3, "hit": bool}. A hit keeps the X/Z and takes the
## hit height; a miss (or a non-3D scene root, or no space state) returns height 0 — the template's ground plane.
## The editor's own Snap-to-Floor (Page Down) uses the same query, so anything it can land on, this lands on.
func _ground_under(pos: Vector3, root: Node) -> Dictionary:
	var from := pos + Vector3.UP * GROUND_PROBE_UP
	var to := from + Vector3.DOWN * GROUND_PROBE_LENGTH
	if root is Node3D:
		var world := (root as Node3D).get_world_3d()
		if world != null:
			var space := world.direct_space_state
			if space != null:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
				if not hit.is_empty():
					var hp: Vector3 = hit["position"]
					return {"pos": Vector3(pos.x, hp.y, pos.z), "hit": true}
	return {"pos": Vector3(pos.x, 0.0, pos.z), "hit": false}


# --- Blockout (CSG) placement -----------------------------------------------------------------------------------
# Each builds a self-contained CSG piece OFF-tree (already in the `navmesh` group, use_collision on, doorway sized so
# the interior stays one navmesh island) and hands it to the shared _finish_place glue with on_ground = true:
# parented under the selection (select `Geometry`/`Blockout` first; a selected piece this tab placed yields a
# SIBLING) or the root, owned so it saves, dropped in front of the camera (grid-snapped) ON THE GROUND, selected,
# one undo. Re-bake the NavigationRegion3D after placing — these change the bake, not the runtime.

func _place_room_shell() -> void:
	_finish_place(CsgBlockout.build_room_shell(), "Building Shell", true)

func _place_floor() -> void:
	_finish_place(CsgBlockout.build_floor(), "Floor", true)

func _place_wall() -> void:
	_finish_place(CsgBlockout.build_wall(), "Wall", true)

func _place_ramp() -> void:
	_finish_place(CsgBlockout.build_ramp(), "Ramp", true)


## The active grid increment in metres (0 = Off), from the snap dropdown.
func _snap_value() -> float:
	if _snap_pick == null:
		return 0.0
	var i := _snap_pick.get_selected()
	return SNAP_VALUES[i] if i >= 0 and i < SNAP_VALUES.size() else 0.0

## Snap a placement position to the X/Z grid (height is left alone — blockout pieces define their own base height,
## and the ground probe sets it afterwards).
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
		_set_status("Pick a grid step first (not Off), then Snap Selected to Grid.")
		return
	var root := EditorInterface.get_edited_scene_root()
	on_scene_changed(root)
	if root == null:
		_set_status("Open a scene first, then snap.")
		return
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var movers: Array[Node3D] = []
	for n in sel:
		if is_instance_valid(n) and n is Node3D:
			movers.append(n as Node3D)
	if movers.is_empty():
		_set_status("Select a 3D node in the Scene tree first.")
		return
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Snap to grid")
	for n in movers:
		var p := n.global_position
		var target := Vector3(roundf(p.x / s) * s, p.y, roundf(p.z / s) * s)
		ur.add_do_property(n, "global_position", target)
		ur.add_undo_property(n, "global_position", p)
	ur.commit_action()
	var step := _snap_pick.get_item_text(_snap_pick.get_selected())
	_set_status("Snapped %d node(s) to the %s grid -- save the scene (Ctrl+S) to keep it." % [movers.size(), step])
