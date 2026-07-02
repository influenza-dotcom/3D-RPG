extends GutTest

## P3 (level-flow lifecycle): the SCENE-LIFECYCLE contract behind the saved-level boot fix — the part the pure
## resolver / placement predicates in test_level_flow.gd can't reach. It drives a real GameRoot through its
## _ready() boot (which DEFERS load_level) IN-TREE, in the same topology as game.tscn: a wrapper "Game" node with
## sibling "GameRoot" and DUMMY "Player" children. The Player is a bare Node3D so the heavy real Player._ready()
## never runs, and the levels are small CODE-BUILT LevelData scenes (an "export" default + a "saved" level embedded
## in a user:// .tres). It locks down what only happens once nodes are actually in the tree:
##   - a FRESH game boots the EXPORTED level and PLACES + respawn-seeds the player at its PlayerSpawn;
##   - a LOADED game boots the SAVED level (resolved by PATH) over the export and does NOT re-place the player
##     (the real Player._ready restores the saved respawn — re-placing here would clobber it; place_at_spawn=false);
##   - a runtime load_level() swap FREES the old Level, instantiates the new one, and re-places + re-seeds respawn.
## This exercises the two-layer call_deferred ordering (_ready -> load_level -> _place_player_at_entry) and the
## group-based PlayerSpawn lookup (&"player_spawn"), neither of which the off-tree predicate tests can prove.
##
## GameState is the AUTOLOAD singleton here (GameRoot reads GameState.loaded / current_level_path and calls
## set_current_level / set_respawn on it), so before/after_each snapshot + restore the fields we touch — otherwise
## the rest of the suite would inherit a mutated respawn / loaded flag.

const GAMEROOT := preload("res://scripts/world/game_root.gd")
const SAVED_LEVEL_PATH := "user://test_lifecycle_saved_level.tres"
const DEV_START_FILE := "user://_dev_start_entry.txt"  ## GameRoot's one-shot Play-From-Spawn marker — must be absent

# Snapshot of the GameState autoload fields we mutate, restored after each test so the wider suite is untouched.
var _s_loaded: bool
var _s_level_path: String
var _s_has_respawn: bool
var _s_respawn_pos: Vector3
var _s_respawn_yaw: float
var _s_matches: bool


func before_each() -> void:
	_s_loaded = GameState.loaded
	_s_level_path = GameState.current_level_path
	_s_has_respawn = GameState.has_respawn
	_s_respawn_pos = GameState.respawn_position
	_s_respawn_yaw = GameState.respawn_yaw
	_s_matches = GameState.respawn_level_matches
	# A stray dev-start file would inject a one-shot spawn override and flip should_place_at_spawn -> the loaded-game
	# "don't re-place" assertion would test a leftover instead of the real contract. Clear it first.
	_remove(DEV_START_FILE)


func after_each() -> void:
	GameState.loaded = _s_loaded
	GameState.current_level_path = _s_level_path
	GameState.has_respawn = _s_has_respawn
	GameState.respawn_position = _s_respawn_pos
	GameState.respawn_yaw = _s_respawn_yaw
	GameState.respawn_level_matches = _s_matches
	_remove(SAVED_LEVEL_PATH)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Build a tiny level PackedScene: a Node3D body carrying a uniquely-named marker (so a test can tell WHICH scene
## instantiated) + one PlayerSpawn at a known LOCAL transform (so placement + respawn-seeding are checkable; the
## body roots at origin under the Game host, so the spawn's global == its local).
func _make_level_scene(marker_name: String, spawn_pos: Vector3, spawn_yaw: float) -> PackedScene:
	var body := Node3D.new()
	body.name = "LevelBody"
	var marker := Node.new()
	marker.name = marker_name
	body.add_child(marker)
	marker.owner = body  # owner must be set (to the pack root) or pack() drops the child
	var spawn := PlayerSpawn.new()
	spawn.name = "Spawn"
	spawn.position = spawn_pos
	spawn.rotation = Vector3(0.0, spawn_yaw, 0.0)
	body.add_child(spawn)
	spawn.owner = body
	var packed := PackedScene.new()
	var ok := packed.pack(body)
	body.free()  # pack() copied the data; the source tree is no longer needed
	assert_eq(ok, OK, "the test level scene should pack")
	return packed


## A level PackedScene with a marker but NO PlayerSpawn — mirrors the shipping trenchboom export (which has none), so
## the M3 mismatch-boot re-seed can't rely on _find_spawn succeeding.
func _make_spawnless_level_scene(marker_name: String) -> PackedScene:
	var body := Node3D.new()
	body.name = "LevelBody"
	var marker := Node.new()
	marker.name = marker_name
	body.add_child(marker)
	marker.owner = body  # owner must be the pack root or pack() drops the child
	var packed := PackedScene.new()
	var ok := packed.pack(body)
	body.free()
	assert_eq(ok, OK, "the spawn-less test level scene should pack")
	return packed


## A game.tscn-shaped host, NOT yet in the tree: a wrapper Game node with sibling GameRoot + dummy Player children.
## The caller sets GameState + gr.level, then add_child_autofree()s `host` to fire the real GameRoot._ready() boot.
## This exercises GameRoot._host()'s production sibling path (GameRoot has no Player child; its parent does).
func _make_game_host(player_at: Vector3) -> Dictionary:
	var host := Node3D.new()
	host.name = "Game"
	var gr := GAMEROOT.new()
	gr.name = "GameRoot"
	var player := Node3D.new()
	player.name = "Player"
	player.position = player_at
	host.add_child(gr)
	host.add_child(player)
	return {"host": host, "root": gr, "player": player}


func _level_child(host: Node3D) -> Node:
	return host.get_node_or_null(^"Level")


# --- a FRESH game boots + places at the exported level's spawn -------------------------------------------------

func test_fresh_boot_loads_export_and_places_player() -> void:
	var spawn_pos := Vector3(3.0, 0.0, 4.0)
	var spawn_yaw := 0.8
	var export_data := LevelData.new()
	export_data.scene = _make_level_scene("FromExport", spawn_pos, spawn_yaw)

	GameState.loaded = false
	GameState.current_level_path = ""

	var ctx := _make_game_host(Vector3(99.0, 99.0, 99.0))  # a sentinel start; a fresh boot should overwrite it
	var host := ctx["host"] as Node3D
	var gr := ctx["root"] as Node3D
	gr.level = export_data
	add_child_autofree(host)
	# Two deferred hops: _ready -> load_level (frame 1) -> _place_player_at_entry (frame 2). Await a few for safety.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var level := _level_child(host)
	assert_not_null(level, "a fresh boot instantiates the exported level as the 'Level' child")
	if level != null:
		assert_not_null(level.get_node_or_null(^"FromExport"), "the EXPORTED level scene loaded (its marker is present)")
	var player := ctx["player"] as Node3D
	assert_eq(player.global_position, spawn_pos, "a fresh boot PLACES the player at the level's PlayerSpawn position")
	assert_almost_eq(player.rotation.y, spawn_yaw, 0.001, "placement also faces the player along the spawn yaw")
	assert_true(GameState.has_respawn, "a fresh boot seeds the respawn point")
	assert_eq(GameState.respawn_position, spawn_pos, "the seeded respawn is the spawn position (a later death returns here)")
	export_data = null


# --- a LOADED game boots the SAVED level and KEEPS its restored respawn ----------------------------------------

func test_loaded_boot_prefers_saved_level_and_keeps_respawn() -> void:
	var export_data := LevelData.new()
	export_data.scene = _make_level_scene("FromExport", Vector3(3.0, 0.0, 4.0), 0.0)

	var saved_data := LevelData.new()
	saved_data.scene = _make_level_scene("FromSaved", Vector3(7.0, 0.0, 7.0), 0.5)
	saved_data.display_name = "Saved"
	# Persist it so resolve_boot_level can resolve it by PATH (the real boot loads from GameState.current_level_path,
	# never an in-memory ref) — the embedded scene rides along as a sub-resource.
	assert_eq(ResourceSaver.save(saved_data, SAVED_LEVEL_PATH), OK, "the saved LevelData should write to disk")

	GameState.loaded = true
	GameState.current_level_path = SAVED_LEVEL_PATH

	var restored_respawn := Vector3(42.0, 1.0, 42.0)  # stands in for the respawn the real Player._ready restores
	var ctx := _make_game_host(restored_respawn)
	var host := ctx["host"] as Node3D
	var gr := ctx["root"] as Node3D
	gr.level = export_data
	add_child_autofree(host)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var level := _level_child(host)
	assert_not_null(level, "a loaded boot still instantiates a 'Level' child")
	if level != null:
		assert_not_null(level.get_node_or_null(^"FromSaved"), "the SAVED level (resolved by path) loaded over the export")
		assert_null(level.get_node_or_null(^"FromExport"), "the exported default did NOT load on a loaded game")
	var player := ctx["player"] as Node3D
	assert_eq(player.global_position, restored_respawn,
		"a loaded boot does NOT re-place the player — its restored saved respawn is preserved (place_at_spawn=false)")
	assert_eq(GameState.current_level_path, SAVED_LEVEL_PATH,
		"load_level re-records the active level path (so the next save still points at the saved level)")
	export_data = null
	saved_data = null


# --- M3: a loaded game whose SAVED level is gone falls back to the export + places there ----------------------

func test_loaded_boot_with_unresolvable_saved_level_places_at_export() -> void:
	# The bug M3 fixes: a live save points at a LevelData whose .tres was since deleted/renamed (authoring drift).
	# The saved respawn belongs to that now-missing level, so restoring it would strand the player out-of-bounds /
	# mid-air. GameRoot must fall back to the EXPORT level, flag respawn_level_matches false (so Player._ready skips
	# the stale respawn), and PLACE the player at the export's spawn + re-seed a valid respawn there.
	var export_spawn := Vector3(3.0, 0.0, 4.0)
	var export_data := LevelData.new()
	export_data.scene = _make_level_scene("FromExport", export_spawn, 0.6)

	GameState.loaded = true
	GameState.current_level_path = "res://resources/levels/deleted_missing_level.tres"  # recorded, but unresolvable

	var stale_respawn := Vector3(500.0, -80.0, 500.0)  # the wrong-level respawn we must NOT teleport to
	var ctx := _make_game_host(stale_respawn)
	var host := ctx["host"] as Node3D
	var gr := ctx["root"] as Node3D
	gr.level = export_data
	add_child_autofree(host)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(GameState.respawn_level_matches, "an unresolvable saved level flags the respawn as a mismatch")
	var level := _level_child(host)
	assert_not_null(level, "the boot falls back to instantiating a 'Level' child")
	if level != null:
		assert_not_null(level.get_node_or_null(^"FromExport"), "the EXPORT level loaded (the recorded saved level was unresolvable)")
	var player := ctx["player"] as Node3D
	assert_eq(player.global_position, export_spawn, "the player is PLACED at the export's spawn, NOT left at the stale saved respawn")
	assert_eq(GameState.respawn_position, export_spawn, "the respawn is RE-SEEDED in the export level (a later death returns HERE, not the wrong level)")
	export_data = null


# --- M3 no-regression: a legacy save (BLANK saved path) is NOT a mismatch — it keeps its restored respawn ---------

func test_loaded_boot_with_blank_saved_path_keeps_respawn() -> void:
	# A legacy / pre-[level] save has a loaded profile but a BLANK current_level_path. That is NOT a mismatch — we do
	# not second-guess a save with no recorded level identity: respawn_level_matches stays true, GameRoot boots the
	# export WITHOUT re-placing (the real Player._ready restores the saved respawn), exactly as before M3.
	var export_data := LevelData.new()
	export_data.scene = _make_level_scene("FromExport", Vector3(3.0, 0.0, 4.0), 0.0)

	GameState.loaded = true
	GameState.current_level_path = ""  # legacy save: no recorded level identity

	var restored_respawn := Vector3(42.0, 1.0, 42.0)  # stands in for the respawn the real Player._ready restores
	var ctx := _make_game_host(restored_respawn)
	var host := ctx["host"] as Node3D
	var gr := ctx["root"] as Node3D
	gr.level = export_data
	add_child_autofree(host)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(GameState.respawn_level_matches, "a blank saved path is NOT a mismatch (legacy save — the respawn is kept)")
	var player := ctx["player"] as Node3D
	assert_eq(player.global_position, restored_respawn, "a blank-path loaded boot does NOT re-place the player (its restored respawn is preserved)")
	export_data = null


# --- M3 sharp edge: a mismatch boot into a SPAWN-LESS export must still invalidate the stale respawn --------------

func test_mismatch_boot_with_spawnless_export_invalidates_stale_respawn() -> void:
	# The bug the diff review caught: the fallback export level may have NO PlayerSpawn (the shipping trenchboom export
	# has none). A mismatched boot then can't PLACE at a spawn — but it MUST still re-seed the respawn at the player's
	# current spot, or has_respawn keeps the DELETED level's coords and the first death teleports there.
	var export_data := LevelData.new()
	export_data.scene = _make_spawnless_level_scene("FromExportNoSpawn")

	GameState.loaded = true
	GameState.current_level_path = "res://resources/levels/deleted_missing_level.tres"  # recorded, but unresolvable

	var stale_respawn := Vector3(500.0, -80.0, 500.0)  # the wrong-level coords that must NOT survive the boot
	var player_at := Vector3(1.0, 0.0, 2.0)
	var ctx := _make_game_host(player_at)
	var host := ctx["host"] as Node3D
	var gr := ctx["root"] as Node3D
	gr.level = export_data
	# Seed the stale respawn the way the real Player would have loaded it from disk (has_respawn true, wrong-level pos).
	GameState.has_respawn = true
	GameState.respawn_position = stale_respawn
	add_child_autofree(host)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(GameState.respawn_level_matches, "an unresolvable saved level is flagged a mismatch")
	assert_ne(GameState.respawn_position, stale_respawn, "the stale wrong-level respawn is INVALIDATED (a later death won't teleport there)")
	assert_eq(GameState.respawn_position, player_at, "the respawn is re-seeded at the player's current in-level spot (no spawn to use)")
	export_data = null


# --- a runtime swap frees the old level + re-places the player ------------------------------------------------

func test_runtime_swap_frees_old_level_and_replaces_player() -> void:
	var export_data := LevelData.new()
	export_data.scene = _make_level_scene("FromExport", Vector3(3.0, 0.0, 4.0), 0.0)

	GameState.loaded = false
	GameState.current_level_path = ""

	var ctx := _make_game_host(Vector3(99.0, 99.0, 99.0))
	var host := ctx["host"] as Node3D
	var gr := ctx["root"] as Node3D
	gr.level = export_data
	add_child_autofree(host)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var booted := _level_child(host)
	assert_not_null(booted, "precondition: the export level booted")
	if booted != null:
		assert_not_null(booted.get_node_or_null(^"FromExport"), "precondition: the export scene is live before the swap")

	# A runtime door-swap to a second level (the LevelDoor / cutscene path — synchronous, not via _ready). load_level
	# free()s the old "Level" immediately, instantiates the new one, then DEFERS placement one frame.
	var next_spawn := Vector3(10.0, 0.0, -5.0)
	var next_data := LevelData.new()
	next_data.scene = _make_level_scene("FromNext", next_spawn, 0.0)
	gr.load_level(next_data, &"", true)
	await get_tree().process_frame
	await get_tree().process_frame

	var level := _level_child(host)
	assert_not_null(level, "after the swap there is still a 'Level' child")
	if level != null:
		assert_not_null(level.get_node_or_null(^"FromNext"), "the swap instantiated the NEW level")
		assert_null(level.get_node_or_null(^"FromExport"), "the swap FREED the old level (no stale geometry left behind)")
	var player := ctx["player"] as Node3D
	assert_eq(player.global_position, next_spawn, "a runtime swap re-places the player at the new level's spawn")
	assert_eq(GameState.respawn_position, next_spawn,
		"a runtime swap re-seeds the respawn at the new level (a later death returns to the NEW level, not the old)")
	export_data = null
	next_data = null
