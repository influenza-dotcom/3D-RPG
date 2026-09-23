extends GutTest

## ChunkStreamer — streams chunk scenes around a target. Each test writes a tiny grid of WorldChunk scenes to a user://
## scratch folder (x in -1..2, z in -1..1, with a GAP at (1, 1)), points a streamer at it and drives step() by hand, so
## nothing depends on physics timing except the one threaded test, which polls frames with a bound.
##
## Scripts are loaded BY PATH (never ChunkStreamer.new() / WorldChunk.new()): both are new class_names, and a headless
## run before the editor has scanned them would otherwise drop this whole file.

const STREAMER := "res://scripts/world/chunk_streamer.gd"
const CHUNK := "res://scripts/world/world_chunk.gd"
const SIZE := 16.0

var _dir := ""
# The streamer captures / applies chunk buckets on the GameState AUTOLOAD: bank what it touches, and start every test
# with no active level (so a capture is a no-op) unless the test sets one.
var _s_level_path: String
var _s_ledger: RefCounted
var _s_dead: Dictionary


func before_each() -> void:
	_s_level_path = GameState.current_level_path
	_s_ledger = GameState.world_snapshot
	_s_dead = GameState._dead_authored
	GameState.current_level_path = ""
	GameState.world_snapshot = load("res://scripts/world/world_snapshot.gd").new()
	GameState._dead_authored = {}
	_dir = "user://_test_chunks_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	for x in range(-1, 3):
		for z in range(-1, 2):
			if Vector2i(x, z) == Vector2i(1, 1):
				continue  # the gap
			var root: Node3D = load(CHUNK).new()
			root.name = "Authored"
			var ps := PackedScene.new()
			assert_eq(ps.pack(root), OK, "chunk %d,%d packs" % [x, z])
			root.free()
			assert_eq(ResourceSaver.save(ps, "%s/chunk_%d_%d.tscn" % [_dir, x, z]), OK, "chunk %d,%d saves" % [x, z])


func after_each() -> void:
	GameState.current_level_path = _s_level_path
	GameState.world_snapshot = _s_ledger
	GameState._dead_authored = _s_dead
	var d := DirAccess.open(_dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_dir)


func _streamer(target: Node3D) -> Node3D:
	var s: Node3D = load(STREAMER).new()
	s.chunk_folder = _dir
	s.chunk_size = SIZE
	s.load_radius = 1
	s.unload_radius = 2
	s.threaded_loading = false
	add_child_autofree(s)
	s.target = s.get_path_to(target)
	return s


func _marker_at(cell: Vector2i) -> Node3D:
	var m := Node3D.new()
	add_child_autofree(m)
	m.global_position = Vector3((cell.x + 0.5) * SIZE, 0.0, (cell.y + 0.5) * SIZE)
	return m


func test_step_loads_the_ring_around_the_target_and_skips_gaps() -> void:
	var s := _streamer(_marker_at(Vector2i(0, 0)))
	s.step()
	assert_eq(s.live_coords().size(), 8, "the 3x3 around (0,0) minus the (1,1) gap")
	assert_false(s.live_coords().has(Vector2i(1, 1)), "a missing file is a gap, never an error")
	var c: Node = s.chunk_at(Vector2i(-1, 0))
	assert_not_null(c, "a loaded cell is reachable by coord")
	assert_eq(String(c.name), "Chunk_-1_0", "named by ChunkGrid.chunk_node_name — part of every save key inside it")
	assert_eq(c.get_parent(), s, "chunks are the streamer's children")


func test_walking_loads_ahead_and_unloads_past_the_band() -> void:
	var m := _marker_at(Vector2i(0, 0))
	var s := _streamer(m)
	s.step()
	var far_left: Node = s.chunk_at(Vector2i(-1, 0))
	m.global_position = Vector3(2.5 * SIZE, 0.0, 0.5 * SIZE)  # into cell (2,0): two rings — a walk, not an arrival
	s.step()
	assert_eq(s.current_coord(), Vector2i(2, 0), "the streamer tracks the target's cell")
	assert_not_null(s.chunk_at(Vector2i(2, 1)), "the new ring streams in")
	assert_null(s.chunk_at(Vector2i(-1, 0)), "three rings behind is unloaded")
	assert_true(not is_instance_valid(far_left) or far_left.is_queued_for_deletion(), "an unloaded chunk is freed")
	assert_true(not is_instance_valid(far_left) or far_left.get_parent() == null, "...and detached at once, so group scans stop seeing it this frame")
	assert_not_null(s.chunk_at(Vector2i(0, 0)), "two rings behind stays (hysteresis band)")


func test_an_actor_standing_near_the_player_pins_its_home_chunk() -> void:
	var m := _marker_at(Vector2i(0, 0))
	var s := _streamer(m)
	s.step()
	var home: Node = s.chunk_at(Vector2i(-1, 0))
	var npc := Node3D.new()
	npc.add_to_group(Groups.NPC)
	home.add_child(npc)
	npc.global_position = Vector3(2.5 * SIZE, 0.0, 0.5 * SIZE)  # it followed the player two cells over
	m.global_position = Vector3(2.5 * SIZE, 0.0, 0.5 * SIZE)
	s.step()
	assert_not_null(s.chunk_at(Vector2i(-1, 0)), "the home chunk of an actor beside the player is not unloaded")
	assert_null(s.chunk_at(Vector2i(-1, -1)), "...while its empty neighbour at the same distance is")


func test_offset_mode_moves_each_chunk_into_its_cell() -> void:
	var m := _marker_at(Vector2i(0, 0))
	var s: Node3D = load(STREAMER).new()
	s.chunk_folder = _dir
	s.chunk_size = SIZE
	s.threaded_loading = false
	s.offset_chunks_to_grid = true
	add_child_autofree(s)
	s.target = s.get_path_to(m)
	s.step()
	var c: Node3D = s.chunk_at(Vector2i(-1, 1))
	assert_eq(c.position, Vector3(-SIZE, 0.0, SIZE), "an offset chunk sits at its cell's corner")
	s.offset_chunks_to_grid = false
	s.unload_all()
	s.step()
	assert_eq((s.chunk_at(Vector2i(-1, 1)) as Node3D).position, Vector3.ZERO, "a world-space chunk keeps its authored origin")


func test_chunks_get_the_level_passes() -> void:
	var s := _streamer(_marker_at(Vector2i(0, 0)))
	s.step()
	var c: Node = s.chunk_at(Vector2i(0, 0))
	assert_true(c is LevelRoot, "a WorldChunk is a LevelRoot (what Ps1Warp.cover gates on)")
	assert_true(c.has_meta(&"_ps1_warp_applied"), "the streamer covers each chunk with the PS1 warp as it lands")


func test_threaded_walk_fills_in_over_frames() -> void:
	var m := _marker_at(Vector2i(0, 0))
	var s := _streamer(m)
	s.threaded_loading = true
	s.sync_load_on_arrival = false
	s.step()
	assert_not_null(s.chunk_at(Vector2i(0, 0)), "the cell under the target always loads synchronously")
	var loaded: int = s.live_coords().size()
	for i in 120:
		if s.live_coords().size() >= 8:
			break
		await wait_physics_frames(1)
	assert_eq(s.live_coords().size(), 8, "background loads land within a couple of seconds (started with %d)" % loaded)


func test_signals_fire_per_chunk() -> void:
	var m := _marker_at(Vector2i(0, 0))
	var s := _streamer(m)
	var counts := {"in": 0, "out": 0}
	s.chunk_loaded.connect(func(_c: Vector2i, _n: Node) -> void: counts["in"] += 1)
	s.chunk_unloaded.connect(func(_c: Vector2i) -> void: counts["out"] += 1)
	s.step()
	assert_eq(counts["in"], 8, "one chunk_loaded per chunk")
	s.unload_all()
	assert_eq(counts["out"], 8, "one chunk_unloaded per chunk")


func test_editor_listing_parses_negative_coords() -> void:
	var s := _streamer(_marker_at(Vector2i(0, 0)))
	var found: Array = s.editor_list_chunks()
	assert_eq(found.size(), 11, "4x3 minus the gap")
	assert_true(found.has(Vector2i(-1, -1)), "negative coords parse")
	assert_false(found.has(Vector2i(1, 1)), "the gap has no file")


func test_level_root_skips_nav_checks_for_a_streamed_worldspace() -> void:
	var world := LevelRoot.new()
	add_child_autofree(world)
	var s: Node3D = load(STREAMER).new()
	world.add_child(s)
	var w := world._get_configuration_warnings()
	for line in w:
		assert_false("NavigationRegion3D" in line, "a worldspace's navmesh lives in its chunks: " + line)


func test_world_chunk_validator_wants_no_sky_and_no_spawn() -> void:
	var chunk: Node3D = load(CHUNK).new()
	add_child_autofree(chunk)
	var w: PackedStringArray = chunk._get_configuration_warnings()
	for line in w:
		assert_false(line.begins_with("No WorldEnvironment"), "a chunk doesn't need a sky: " + line)
		assert_false(line.begins_with("No PlayerSpawn"), "...or a spawn: " + line)
	chunk.add_child(WorldEnvironment.new())
	var hit := false
	for line in chunk._get_configuration_warnings():
		hit = hit or line.contains("fight the worldspace's sky")
	assert_true(hit, "a chunk that brings its own WorldEnvironment is flagged")


## THE CHUNK LEDGER: a crate looted in a chunk stays looted after that chunk streams out and back in — the chunk's own
## bucket is captured on the way out and handed back on the way in — and a level-wide capture never files chunk content
## under the level (which would go stale the moment the chunk unloads).
func test_a_crate_looted_in_a_chunk_stays_looted_after_it_streams_out_and_back() -> void:
	const WORLD := "res://_test_world.tres"
	const HEALTHPACK := "res://resources/items/healthpack.tres"
	GameState.current_level_path = WORLD
	var root: Node3D = load(CHUNK).new()
	root.name = "Authored"
	var crate := ItemContainer.new()
	crate.name = "Crate"
	crate.save_id = &"chunk_crate"
	var stack := ItemStack.new()
	stack.item = load(HEALTHPACK)
	stack.count = 3
	crate.item_stacks.append(stack)
	root.add_child(crate)
	crate.owner = root
	var ps := PackedScene.new()
	assert_eq(ps.pack(root), OK, "the crate chunk packs")
	root.free()
	assert_eq(ResourceSaver.save(ps, "%s/chunk_0_0.tscn" % _dir), OK, "the crate chunk replaces cell (0,0)")

	var m := _marker_at(Vector2i(0, 0))
	var s := _streamer(m)
	s.step()
	var live := s.chunk_at(Vector2i(0, 0)).get_node(^"Crate") as ItemContainer
	var item: Item = load(HEALTHPACK)
	assert_eq(live.inventory.count_of_id(item.id), 3, "precondition: the crate seeded its authored healthpacks")
	live.inventory.clear()

	GameState.capture_level_state(get_tree(), WORLD)
	var ledger: Dictionary = GameState.world_snapshot.to_dict()
	var chunk_key: String = load("res://scripts/world/world_snapshot.gd").scoped_key(WORLD, "Chunk_0_0")
	assert_true(ledger.has(chunk_key), "a save captures the loaded chunk into its own bucket")
	assert_false((ledger.get(WORLD, {}).get("containers", {}) as Dictionary).has("id:chunk_crate"), "...and the LEVEL bucket never holds chunk content")

	m.global_position = Vector3(3.5 * SIZE, 0.0, 0.5 * SIZE)  # three rings away: (0,0) streams out
	s.step()
	assert_null(s.chunk_at(Vector2i(0, 0)), "precondition: the crate's chunk unloaded")
	m.global_position = Vector3(0.5 * SIZE, 0.0, 0.5 * SIZE)
	s.step()
	await wait_frames(2)  # the bucket apply is deferred behind the chunk's _ready
	var back := s.chunk_at(Vector2i(0, 0)).get_node(^"Crate") as ItemContainer
	assert_ne(back, live, "precondition: a fresh instance streamed in")
	assert_eq(back.inventory.count_of_id(item.id), 0, "the crate is STILL LOOTED — restored from the chunk's bucket, not re-seeded")
