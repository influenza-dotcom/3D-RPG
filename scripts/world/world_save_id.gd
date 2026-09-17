extends RefCounted

## @system Save Model
## @seam WorldSaveId is the ONE identity scheme for every persistable (Door, ItemContainer, Corpse, CanPickUp, MoneyPickUp, UpgradePickup, CanDestroy, NPC): an authored save_id is the whole key 'id:<x>'; a blank id falls back to level|path|position (world_objects, corpse discovery) or level|node_path (the world ledger), and a node that HAS an id reads those old keys only as a legacy path (read_object_state / corpse_discovered / snapshot_legacy_key_for), adopting the state onto its id key.
## @risk Changing a fallback shape (node_path source or _round_cm precision) silently re-keys every object still without a save_id, and breaks the legacy read that lets a newly stamped object find its old state — no error.
## @risk A save_id authored INSIDE a reusable prefab is shared by every copy of it, so they all load one saved state; ScanScene.save_id_findings reports the duplicate as an ERROR, and blank_id_warning_in stays quiet while a prefab (not a level) is being edited so nobody is told to put one there.
## @test res://tests/test_save_identity.gd
## @test res://tests/test_game_save.gd
## Preloaded as a const where needed (NO class_name — nothing for the global script class cache to miss, matching
## Factions / GoapLibrary / ItemIds). Consumers: `const WorldSaveId = preload("res://scripts/world/world_save_id.gd")`.
##
## WHY ONE SCHEME. Persistable state used to be keyed three ways — the position-derived world_objects key, the
## level|node_path snapshot key, and Corpse's marker — and a blank id is the normal case, so any layout edit (move a
## door, rename a crate, re-parent an NPC) silently orphaned that object's saved state. Now `save_id` is primary
## everywhere: the Place tab, the Palette and the Item placer stamp a unique one on placement (new_save_id), the
## Place tab stamps any that are missing in a level in one undoable step, and a blank one on a persistable
## authored in a level shows up as a config warning, an Audit row and a validate_all.gd WARN.
##
## THE LEGACY READ PATH. Saves written before an object had a save_id filed its state under the fallback key. When
## a node that now HAS an id finds nothing under "id:<x>", it looks under the key it would have had without one and,
## on a hit, MOVES that entry to the id key in memory (no disk write — the next ordinary save persists it). A node
## whose id is still blank keeps reading and writing the fallback, because nothing else identifies it.

## The level scene folders: a persistable in a scene saved under one of these is AUTHORED IN A LEVEL, so it wants its
## own save_id. (A LevelRoot root counts too — see is_level_scene.)
const LEVEL_SCENE_DIRS: Array[String] = ["res://scenes/levels/", "res://scenes/worlds/"]

## What a blank id costs, in one sentence — shared by the config warning and the Audit / validate_all rows.
const BLANK_ID_CAUSE := "No save_id: its saved state is keyed by its node path (plus its position, for doors, pickups, props and corpse markers), so moving, renaming or re-parenting it loses that state."
## The config-warning text a blank id raises: the cost, then what to do.
const BLANK_ID_WARNING := BLANK_ID_CAUSE + " Stamp one with CYBER SUNDAY → Place → Stamp Missing save_ids (or type a unique id)."


## The world_objects / corpse key: "id:<save_id>" when authored, else the level|path|position fallback.
static func key_for(node: Node3D, save_id: StringName) -> String:
	if save_id != &"":
		return "id:%s" % String(save_id)
	return legacy_key_for(node)


## The level|scene-path|rounded-position key every blank-id object uses — and the key a save written before this
## object had a save_id stored its state under (the legacy read path).
static func legacy_key_for(node: Node3D) -> String:
	var node_path: String = str(node.get_path()) if node.is_inside_tree() else String(node.name)
	# global_position off-tree raises an engine error; the fallback is only meaningful in-tree (restore runs in
	# _ready), so zero the position off-tree rather than error — the node_path still distinguishes such keys.
	var p := node.global_position if node.is_inside_tree() else Vector3.ZERO
	return "%s|%s|%.2f,%.2f,%.2f" % [
		GameState.current_level_path,
		node_path,
		_round_cm(p.x), _round_cm(p.y), _round_cm(p.z),
	]


## The world ledger key (NPC / ItemContainer snapshot_key): "id:<save_id>", else level|node_path. POSITION-FREE on
## purpose — an NPC moves, so a position in the key would never match the reloaded node at its authored spot.
static func snapshot_key_for(node: Node, save_id: StringName) -> String:
	if save_id != &"":
		return "id:%s" % String(save_id)
	return path_key(node)


## The key an older world ledger filed this node under when it had no save_id, or "" when it still has none (its
## snapshot key IS the path key, so there is nothing else to look up).
static func snapshot_legacy_key_for(node: Node, save_id: StringName) -> String:
	return path_key(node) if save_id != &"" else ""


## level|node_path — the position-free fallback. Off-tree the path degrades to the node name.
static func path_key(node: Node) -> String:
	var np: String = str(node.get_path()) if node.is_inside_tree() else String(node.name)
	return "%s|%s" % [GameState.current_level_path, np]


## Read `node`'s saved world_objects state in the current level, through the legacy path: the id key first; when that
## is missing and the node has an id, the fallback key, which is then moved onto the id key (in memory, no autosave).
## Always a Dictionary ({} for none). Every persistable's restore in _ready goes through here.
static func read_object_state(node: Node3D, save_id: StringName) -> Dictionary:
	var level: String = GameState.current_level_path
	var key := key_for(node, save_id)
	if save_id == &"" or GameState.has_object_state(level, key):
		return GameState.object_state(level, key)
	return GameState.adopt_legacy_object_state(level, legacy_key_for(node), key)


## Whether the Corpse marker `node` was already investigated, through the same legacy path as read_object_state.
static func corpse_discovered(node: Node3D, save_id: StringName) -> bool:
	var key := key_for(node, save_id)
	if GameState.is_corpse_discovered(key):
		return true
	return save_id != &"" and GameState.adopt_legacy_corpse_key(legacy_key_for(node), key)


## True when `node` is a persistable that needs its own save_id: it exports one, and it has not opted out of
## persistence (a loot-dropped CanPickUp builds its model from its item; a code-spawned MoneyPickUp/UpgradePickup sets
## persist_collected = false). Duck-typed, so it works off-tree, headless and on any future persistable.
static func wants_save_id(node: Node) -> bool:
	if node == null or not (&"save_id" in node):
		return false
	if &"build_model_from_item" in node and bool(node.get(&"build_model_from_item")):
		return false
	if &"persist_collected" in node and not bool(node.get(&"persist_collected")):
		return false
	return true


## True when `root` is a level scene: a LevelRoot, or a scene saved under one of LEVEL_SCENE_DIRS (older levels root a
## plain Node3D). A persistable anywhere else is being edited inside a PREFAB, where an id would be copied into every
## instance, so it must stay blank there.
static func is_level_scene(root: Node) -> bool:
	if root == null:
		return false
	if root is LevelRoot:
		return true
	for dir in LEVEL_SCENE_DIRS:
		if root.scene_file_path.begins_with(dir):
			return true
	return false


## The editor config warning for `node`'s blank save_id, or "". Each persistable's _get_configuration_warnings calls
## this; it reads the edited scene, so it is quiet at runtime and in a headless run.
static func blank_id_warning(node: Node) -> String:
	if not Engine.is_editor_hint() or node == null or not node.is_inside_tree():
		return ""
	return blank_id_warning_in(node, node.get_tree().edited_scene_root)


## The pure core of blank_id_warning with the edited scene root passed in: warns when `node` wants a save_id, has a
## blank one, and sits below the root of a LEVEL scene (never the root itself, never inside a prefab being edited).
static func blank_id_warning_in(node: Node, scene_root: Node) -> String:
	if node == null or scene_root == null or node == scene_root or not is_level_scene(scene_root):
		return ""
	if not wants_save_id(node) or StringName(node.get(&"save_id")) != &"":
		return ""
	return BLANK_ID_WARNING


## A fresh save_id for `node` that is not a key of `taken` (a set of StringName ids already used in the scene): the
## component kind in snake_case plus a random 6-hex suffix, e.g. "door_3f9a1c". Readable in a save file, unique
## across levels in practice (corpse discovery keys are not level-scoped), and the caller adds it to `taken`.
static func new_save_id(node: Node, taken: Dictionary) -> StringName:
	var kind := "object"
	var script: Script = node.get_script() if node != null else null
	while script != null:
		var gname := String(script.get_global_name())
		if gname != "":
			kind = gname.to_snake_case()
			break
		script = script.get_base_script()
	while true:
		var id := StringName("%s_%06x" % [kind, randi() & 0xFFFFFF])
		if not taken.has(id):
			return id
	return &""  # unreachable; keeps the typed return total


static func _round_cm(v: float) -> float:
	return roundf(v * 100.0) / 100.0
