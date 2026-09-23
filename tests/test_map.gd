extends GutTest

## Slice 10 (map): MapData.world_to_uv projection (pure) + the unauthored default. The Minimap rendering (_draw, the
## markers) is playtest-verified per the in-tree convention.

func test_world_to_uv_projects_xz() -> void:
	var b := Rect2(0, 0, 100, 100)
	assert_eq(MapData.world_to_uv(Vector3(0, 0, 0), b), Vector2(0, 0), "min corner -> (0,0)")
	assert_eq(MapData.world_to_uv(Vector3(50, 0, 50), b), Vector2(0.5, 0.5), "centre -> (0.5, 0.5)")
	assert_eq(MapData.world_to_uv(Vector3(100, 9, 100), b), Vector2(1, 1), "max corner -> (1,1); the Y axis is ignored")

func test_world_to_uv_handles_offset_bounds() -> void:
	var b := Rect2(-50, -50, 100, 100)
	assert_eq(MapData.world_to_uv(Vector3(0, 0, 0), b), Vector2(0.5, 0.5), "the world origin is the centre of a centred map")
	# Off-origin, so an offset applied to the wrong axis (or not at all) cannot hide behind the symmetric centre.
	assert_eq(MapData.world_to_uv(Vector3(-50, 0, 25), b), Vector2(0.0, 0.75),
		"the rect's min X is the map's left edge and world Z +25 sits three quarters down a -50..50 span")

func test_world_to_uv_scales_each_axis_by_its_own_extent() -> void:
	# A NON-SQUARE rect (a long east-west level). Dividing both axes by one extent would squash the player dot
	# off the drawn level on one axis while the square fixtures above stay green.
	var b := Rect2(10, -20, 200, 40)
	assert_eq(MapData.world_to_uv(Vector3(110, 3, -10), b), Vector2(0.5, 0.25),
		"u = (110-10)/200 along the 200-wide X span, v = (-10+20)/40 along the 40-deep Z span")
	assert_eq(MapData.world_to_uv(Vector3(210, 0, 20), b), Vector2(1, 1),
		"the far corner of a non-square rect is still (1,1)")

func test_world_to_uv_degenerate_bounds_centre() -> void:
	assert_eq(MapData.world_to_uv(Vector3(5, 0, 5), Rect2(0, 0, 0, 0)), Vector2(0.5, 0.5), "zero-size bounds -> centre (no div-by-zero)")
	# ONE collapsed axis is just as degenerate: a zero-depth rect must not divide by zero on Z while X is fine.
	assert_eq(MapData.world_to_uv(Vector3(5, 0, 5), Rect2(0, 0, 100, 0)), Vector2(0.5, 0.5),
		"zero-depth bounds -> centre, never an inf/NaN marker position")
	assert_eq(MapData.world_to_uv(Vector3(5, 0, 5), Rect2(0, 0, 0, 100)), Vector2(0.5, 0.5),
		"zero-width bounds -> centre too")
	assert_eq(MapData.world_to_uv(Vector3(5, 0, 5), Rect2(0, 0, -10, 100)), Vector2(0.5, 0.5),
		"a negative extent (a flipped rect typed into the inspector) is degenerate, not a mirrored map")

func test_unauthored_map_data_still_projects_a_real_spread() -> void:
	# A MapData created by hand (or scaffolded before its bounds are filled in) must already project positions
	# onto the map rather than collapse every dot onto the degenerate-bounds centre, and the level origin (where
	# the level templates put their spawn) must land ON the image.
	var m := MapData.new()
	var origin := MapData.world_to_uv(Vector3.ZERO, m.world_bounds)
	assert_true(origin.x >= 0.0 and origin.x <= 1.0 and origin.y >= 0.0 and origin.y <= 1.0,
		"the world origin projects inside the default map (got %s)" % origin)
	var east := MapData.world_to_uv(Vector3(10, 0, 0), m.world_bounds)
	var south := MapData.world_to_uv(Vector3(0, 0, 10), m.world_bounds)
	assert_gt(east.x, origin.x, "moving +X moves the dot right on an unauthored map (not the degenerate centre)")
	assert_gt(south.y, origin.y, "moving +Z moves the dot down on an unauthored map")
	m = null
