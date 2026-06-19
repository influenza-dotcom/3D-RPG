extends GutTest

## Slice 10 (map): MapData.world_to_uv projection (pure) + defaults. The Minimap rendering (_draw, the markers)
## is playtest-verified per the in-tree convention.

func test_world_to_uv_projects_xz() -> void:
	var b := Rect2(0, 0, 100, 100)
	assert_eq(MapData.world_to_uv(Vector3(0, 0, 0), b), Vector2(0, 0), "min corner -> (0,0)")
	assert_eq(MapData.world_to_uv(Vector3(50, 0, 50), b), Vector2(0.5, 0.5), "centre -> (0.5, 0.5)")
	assert_eq(MapData.world_to_uv(Vector3(100, 9, 100), b), Vector2(1, 1), "max corner -> (1,1); the Y axis is ignored")

func test_world_to_uv_handles_offset_bounds() -> void:
	var b := Rect2(-50, -50, 100, 100)
	assert_eq(MapData.world_to_uv(Vector3(0, 0, 0), b), Vector2(0.5, 0.5), "the world origin is the centre of a centred map")

func test_world_to_uv_degenerate_bounds_centre() -> void:
	assert_eq(MapData.world_to_uv(Vector3(5, 0, 5), Rect2(0, 0, 0, 0)), Vector2(0.5, 0.5), "zero-size bounds -> centre (no div-by-zero)")

func test_mapdata_defaults() -> void:
	var m := MapData.new()
	assert_eq(m.world_bounds, Rect2(-50, -50, 100, 100), "default world bounds")
	assert_null(m.map_texture, "no texture by default")
	m = null
