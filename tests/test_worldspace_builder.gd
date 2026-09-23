extends GutTest

## WorldspaceBuilder — the scaffold behind scripts/tools/new_worldspace.gd. Pins the shapes a designer relies on: a
## chunk is a WorldChunk with a cell-fitted navmesh that actually bakes from its OWN ground, two neighbouring chunks'
## baked edges meet on the shared cell line (the seam the navigation map knits), and the persistent layer keeps the
## sky + spawn but hands the ground and navmesh to the chunks.

const Builder = preload("res://scripts/world/worldspace_builder.gd")
const SIZE := 16.0


func _region(root: Node) -> NavigationRegion3D:
	for n in root.find_children("*", "NavigationRegion3D", true, false):
		return n
	return null


func test_chunk_shape_survives_a_pack() -> void:
	var chunk := Builder.build_chunk(Vector2i(1, -1), SIZE)
	var ps := PackedScene.new()
	assert_eq(ps.pack(chunk), OK, "a built chunk packs")
	chunk.free()
	var inst := ps.instantiate()
	assert_true(inst is LevelRoot, "the root is a WorldChunk (a LevelRoot)")
	assert_eq(inst.get(&"cell"), Vector2i(1, -1), "cell is stamped")
	assert_not_null(_region(inst), "the NavigationRegion3D is owned, so it survives the pack")
	assert_not_null(inst.get_node_or_null(^"Geometry/Ground/StaticBody3D/CollisionShape3D"), "...and the ground collider")
	assert_true(inst.get_node(^"Geometry").is_in_group(Groups.NAVMESH), "Geometry keeps its persistent navmesh group")
	assert_not_null(inst.get_node_or_null(^"SeeThroughBrushes"), "each chunk carries its own SeeThroughBrushes")
	inst.free()


func test_bake_fits_the_cell_and_neighbours_meet_on_the_seam() -> void:
	var a := Builder.build_chunk(Vector2i(0, 0), SIZE)
	var b := Builder.build_chunk(Vector2i(1, 0), SIZE)
	add_child_autofree(a)
	add_child_autofree(b)
	assert_gt(Builder.bake_chunk(a), 0, "chunk (0,0) bakes a walkable navmesh from its own ground")
	assert_gt(Builder.bake_chunk(b), 0, "chunk (1,0) too")
	var max_a := -INF
	for v in _region(a).navigation_mesh.get_vertices():
		max_a = maxf(max_a, v.x)
		assert_true(v.x >= -0.3 and v.x <= SIZE + 0.3, "chunk (0,0)'s navmesh stays inside its cell (x=%.2f)" % v.x)
		# A bake box taller than Recast's 13-bit span height wraps every height (a floor at 0 once baked at -942).
		assert_true(absf(v.y) < 0.5, "the ground bakes at its real height (y=%.2f), not wrapped by an over-tall bake box" % v.y)
	var min_b := INF
	for v in _region(b).navigation_mesh.get_vertices():
		min_b = minf(min_b, v.x)
	assert_almost_eq(max_a, SIZE, 0.3, "chunk (0,0)'s mesh reaches the shared edge instead of eroding agent_radius short of it")
	assert_almost_eq(min_b, SIZE, 0.3, "chunk (1,0)'s mesh starts on the same line — the seam the nav map joins")


## The cell fit also writes the agent values Recast would ceil/truncate to anyway, so a chunk bake never warns about
## precision (the engine's own rounding: agent_height/radius CEILED to whole voxels, region_min_size² truncated).
func test_cell_fit_writes_the_voxel_values_the_bake_actually_uses() -> void:
	var chunk := Builder.build_chunk(Vector2i(0, 0), SIZE)
	var nav := _region(chunk).navigation_mesh
	var cs := nav.cell_size
	var ch := nav.cell_height
	assert_almost_eq(nav.agent_radius, ceilf(0.6 / cs - 0.001) * cs, 0.0001, "0.6 m ceils to the next whole cell (0.75 on a 0.25 grid)")
	assert_almost_eq(nav.agent_height, 2.2, 0.0001, "2.2 m is already 220 voxels of 0.01 — kept, just nudged under the float32 edge")
	assert_true(nav.agent_height <= roundf(nav.agent_height / ch) * ch, "...and never above the voxel it names, or Recast would ceil one more")
	assert_eq(nav.region_min_size, 0.0, "0.1² truncates to 0 cells, which is what the bake always used")
	var before := [nav.agent_height, nav.agent_radius, nav.region_min_size]
	chunk.apply_cell_fit(nav)
	assert_eq([nav.agent_height, nav.agent_radius, nav.region_min_size], before, "snapping is idempotent — a re-fit never drifts a value")
	var custom := NavigationMesh.new()
	custom.agent_radius = 0.5
	custom.region_min_size = 2.0
	chunk.snap_agent_to_voxels(custom)
	assert_almost_eq(custom.agent_radius, 0.5, 0.0001, "a value already on the grid stays where it is")
	assert_eq(custom.region_min_size, 2.0, "a region size whose square is whole stays")
	chunk.free()


func test_bake_ignores_navmesh_group_geometry_outside_the_chunk() -> void:
	var stray := Builder.build_chunk(Vector2i(0, 0), SIZE)  # another floor in the same group, same cell, raised
	(stray.get_node(^"Geometry/Ground") as Node3D).position.y += 5.0
	add_child_autofree(stray)
	var chunk := Builder.build_chunk(Vector2i(0, 0), SIZE)
	add_child_autofree(chunk)
	Builder.bake_chunk(chunk)
	for v in _region(chunk).navigation_mesh.get_vertices():
		assert_true(v.y > -1.0 and v.y < 2.0, "only the chunk's own ground is parsed (found a vertex at y=%.2f)" % v.y)


## The whole point of the cell fit: two chunks baked separately join into ONE route on the navigation map.
func test_a_path_crosses_the_seam_on_the_live_nav_map() -> void:
	var a := Builder.build_chunk(Vector2i(0, 0), SIZE)
	var b := Builder.build_chunk(Vector2i(1, 0), SIZE)
	add_child_autofree(a)
	add_child_autofree(b)
	Builder.bake_chunk(a)
	Builder.bake_chunk(b)
	# A region re-registers its mesh on a later map sync. Maps build their iterations ASYNC, so a fixed frame count
	# is a race (measured: 3 frames alone, more than 4 inside the full suite). Wait for two NEW map iterations
	# instead — the first may already have been in flight before the regions changed — bounded so it cannot hang.
	_region(a).navigation_mesh = _region(a).navigation_mesh
	_region(b).navigation_mesh = _region(b).navigation_mesh
	var map := a.get_world_3d().navigation_map
	var start_iteration := NavigationServer3D.map_get_iteration_id(map)
	for _i in 60:
		if NavigationServer3D.map_get_iteration_id(map) >= start_iteration + 2:
			break
		await wait_physics_frames(1)
	assert_true(NavigationServer3D.map_get_iteration_id(map) >= start_iteration + 2, "the navigation map rebuilt after the chunks registered")
	var to := Vector3(SIZE * 1.5, 0.0, SIZE * 0.5)
	var path := NavigationServer3D.map_get_path(map, Vector3(SIZE * 0.25, 0.0, SIZE * 0.5), to, true)
	assert_gt(path.size(), 0, "a route exists from one chunk into the next")
	if path.size() > 0:
		assert_almost_eq(path[path.size() - 1].x, to.x, 0.5, "...and it reaches the far chunk instead of stopping at the seam")


## Every navmesh bakes at ONE cell height, and the navigation map must use it too: a mismatch makes the map warn on
## every region it registers and rasterizes cross-region edges on the coarser grid (the seam above is one).
func test_the_nav_map_cell_height_matches_every_navmesh() -> void:
	var map_ch := float(ProjectSettings.get_setting("navigation/3d/default_cell_height"))
	var chunk := Builder.build_chunk(Vector2i(0, 0), SIZE)
	assert_almost_eq(_region(chunk).navigation_mesh.cell_height, map_ch, 0.0001, "a built chunk bakes on the map's cell height")
	chunk.free()
	assert_almost_eq(NavigationServer3D.map_get_cell_height(get_tree().root.get_world_3d().navigation_map), map_ch, 0.0001,
		"the live default map picked the project setting up")
	var files: Array[String] = []
	_collect_scenes("res://scenes", files)
	var rx := RegEx.create_from_string("(?m)^cell_height = ([0-9.e-]+)$")
	var checked := 0
	for path in files:
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			checked += 1
			assert_almost_eq(float(m.get_string(1)), map_ch, 0.0001, "%s authors a navmesh cell_height the map does not use" % path)
	assert_gt(checked, 10, "the scan found the authored navmeshes (got %d)" % checked)


func _collect_scenes(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d in dir.get_directories():
		_collect_scenes(dir_path.path_join(d), out)
	for f in dir.get_files():
		if f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir_path.path_join(f))


func test_persistent_layer_keeps_the_sky_and_drops_the_ground() -> void:
	var world := Builder.build_persistent("res://nowhere", SIZE, Vector2i(2, 3))
	assert_not_null(world, "the template loads")
	assert_null(world.get_node_or_null(^"NavigationRegion3D"), "the navmesh lives in the chunks")
	assert_null(world.get_node_or_null(^"Geometry"), "...and so does the ground")
	assert_not_null(world.get_node_or_null(^"WorldEnvironment"), "the sky stays in the persistent layer")
	var streamer := world.get_node_or_null(^"ChunkStreamer")
	assert_not_null(streamer, "a ChunkStreamer is added")
	assert_eq(streamer.owner, world, "...and owned, so it saves")
	assert_eq(streamer.get(&"chunk_folder"), "res://nowhere", "pointed at the chunk folder")
	var spawn := world.get_node_or_null(^"PlayerSpawn") as Node3D
	assert_almost_eq(spawn.position.x, 2.5 * SIZE, 0.01, "the spawn sits mid-cell (x)")
	assert_almost_eq(spawn.position.z, 3.5 * SIZE, 0.01, "the spawn sits mid-cell (z)")
	world.free()
