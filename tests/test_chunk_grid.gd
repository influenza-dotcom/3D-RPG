extends GutTest

## ChunkGrid — the pure grid math behind ChunkStreamer: position -> cell, the nearest-first load ring, and the
## load/unload plan with its hysteresis band. Everything here is static and tree-free.

const ChunkGrid = preload("res://scripts/world/chunk_grid.gd")


func test_coord_for_floors_toward_negative_infinity() -> void:
	assert_eq(ChunkGrid.coord_for(Vector3(0.5, 0, 0.5), 64.0), Vector2i(0, 0), "just inside the origin cell")
	assert_eq(ChunkGrid.coord_for(Vector3(-0.5, 0, 0.5), 64.0), Vector2i(-1, 0), "just left of the origin is cell -1, not a double-wide cell 0")
	assert_eq(ChunkGrid.coord_for(Vector3(64.0, 0, -64.0), 64.0), Vector2i(1, -1), "an exact cell edge belongs to the cell it starts")
	assert_eq(ChunkGrid.coord_for(Vector3(10, 999, 10), 64.0), Vector2i(0, 0), "height is ignored — a chunk is a vertical column")


func test_coord_for_honours_the_origin_and_survives_a_bad_size() -> void:
	assert_eq(ChunkGrid.coord_for(Vector3(100, 0, 100), 64.0, Vector3(50, 0, 50)), Vector2i(0, 0), "the origin shifts the grid")
	assert_eq(ChunkGrid.coord_for(Vector3(1, 0, 1), 0.0), ChunkGrid.coord_for(Vector3(1, 0, 1), 0.0), "a zero size doesn't divide by zero")


func test_chunk_origin_is_the_inverse_of_coord_for() -> void:
	for c in [Vector2i(0, 0), Vector2i(-3, 2), Vector2i(5, -7)]:
		var corner := ChunkGrid.chunk_origin(c, 32.0)
		assert_eq(ChunkGrid.coord_for(corner + Vector3(0.1, 0, 0.1), 32.0), c, "a point just inside the corner of %s maps back to it" % c)


func test_distance_is_chebyshev() -> void:
	assert_eq(ChunkGrid.distance(Vector2i(0, 0), Vector2i(2, 1)), 2, "the larger axis wins")
	assert_eq(ChunkGrid.distance(Vector2i(-1, -1), Vector2i(1, 1)), 2, "diagonals count as one ring per step")


func test_ring_is_nearest_first_and_sized_as_a_square() -> void:
	assert_eq(ChunkGrid.ring(Vector2i(4, 4), 0).size(), 1, "radius 0 is just the centre")
	var r1 := ChunkGrid.ring(Vector2i(4, 4), 1)
	assert_eq(r1.size(), 9, "radius 1 is the 3x3 block")
	assert_eq(r1[0], Vector2i(4, 4), "the centre comes first")
	var r2 := ChunkGrid.ring(Vector2i(0, 0), 2)
	assert_eq(r2.size(), 25, "radius 2 is 5x5 (Fallout 3's uGridsToLoad 5)")
	var last := 0
	for c in r2:
		var d := ChunkGrid.distance(Vector2i(0, 0), c)
		assert_true(d >= last, "ring order never steps back inward (%s at ring %d after ring %d)" % [c, d, last])
		last = d
	assert_eq(ChunkGrid.ring(Vector2i(0, 0), -1).size(), 0, "a negative radius is empty")


func test_plan_loads_what_is_missing_nearest_first() -> void:
	var live := {Vector2i(0, 0): true, Vector2i(1, 0): true}
	var p := ChunkGrid.plan(Vector2i(0, 0), live, 1, 2)
	assert_eq(p.load.size(), 7, "3x3 minus the two already live")
	assert_false(p.load.has(Vector2i(0, 0)), "a live cell is never re-requested")
	assert_eq(p.unload.size(), 0, "nothing live is out of range")


func test_plan_keeps_the_hysteresis_band_and_unloads_past_it() -> void:
	var live := {Vector2i(2, 0): true, Vector2i(3, 0): true}
	var p := ChunkGrid.plan(Vector2i(0, 0), live, 1, 2)
	assert_false(p.unload.has(Vector2i(2, 0)), "two rings out with unload_radius 2 stays (the band between load and unload)")
	assert_true(p.unload.has(Vector2i(3, 0)), "three rings out goes")


func test_plan_clamps_an_unload_radius_below_the_load_radius() -> void:
	var p := ChunkGrid.plan(Vector2i(0, 0), [Vector2i(2, 2)], 2, 0)
	assert_false(p.unload.has(Vector2i(2, 2)), "unload_radius < load_radius would free what this step loads; it clamps up")


func test_plan_skips_cells_the_exists_filter_rejects() -> void:
	var only_origin := func(c: Vector2i) -> bool: return c == Vector2i(0, 0)
	var p := ChunkGrid.plan(Vector2i(0, 0), {}, 1, 2, only_origin)
	assert_eq(p.load.size(), 1, "gaps in the grid are never requested")


func test_node_name_and_path_are_deterministic() -> void:
	assert_eq(ChunkGrid.chunk_node_name(Vector2i(-1, 2)), "Chunk_-1_2", "the node name is part of every fallback save key inside the chunk")
	assert_eq(ChunkGrid.chunk_path("res://w", "chunk_{x}_{z}.tscn", Vector2i(-1, 2)), "res://w/chunk_-1_2.tscn", "{x}/{z} substitute by replace")
	assert_eq(ChunkGrid.chunk_path("res://w", "100%_{z}_{x}.tscn", Vector2i(3, 4)), "res://w/100%_4_3.tscn", "a literal % in the pattern is harmless and order follows the pattern")
