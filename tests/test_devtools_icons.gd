extends GutTest

## The CYBER SUNDAY Icons baker: the PURE render math (icon_render) + the soft-fail save guard are tested off-tree;
## the SubViewport render itself is editor-only (no renderer headless) and user-verified. Also pins the grid_tile
## baked-icon fallback (returns null when no icon is on disk -> the grid keeps using the live mesh / glyph).

const Render := preload("res://addons/cybersunday_tools/dock_icons/icon_render.gd")
const Baker := preload("res://addons/cybersunday_tools/dock_icons/icon_baker.gd")
const IconView := preload("res://addons/cybersunday_tools/dock_icons/icon_view.gd")
const GridTile := preload("res://scripts/ui/grid_tile.gd")


func test_pixel_size_scales_with_footprint() -> void:
	assert_eq(Render.pixel_size(1, 1, 96), Vector2i(96, 96), "a 1x1 item -> one cell square")
	assert_eq(Render.pixel_size(2, 1, 96), Vector2i(192, 96), "a 2x1 item -> a 2:1 icon (fits the boxes it takes up)")
	assert_eq(Render.pixel_size(0, 3, 96), Vector2i(96, 288), "a zero/under footprint clamps to at least one cell")


func test_normalize_unit_box_and_degenerate() -> void:
	var n := Render.normalize(AABB(Vector3(2, 2, 2), Vector3(4, 2, 2)))  # largest dim 4 -> scale 0.25
	assert_almost_eq(float(n["scale"]), 0.25, 0.0001, "largest dimension scales to 1.0")
	assert_eq(Vector3(n["ext"]), Vector3(1.0, 0.5, 0.5), "normalized extents: largest is 1.0")
	# offset centres the box on the origin: centre (4,3,3) * 0.25 = (1,0.75,0.75), negated.
	assert_eq(Vector3(n["offset"]), Vector3(-1.0, -0.75, -0.75), "offset lands the box centre on the origin")
	var deg := Render.normalize(AABB(Vector3.ZERO, Vector3.ZERO))
	assert_almost_eq(float(deg["scale"]), 1.0, 0.0001, "a degenerate AABB falls back to unit scale (no divide-by-zero)")


func test_fit_ortho_size_in_range_and_grows_with_ext() -> void:
	var cam := Transform3D(Basis(), Vector3(0, 0, 4))  # looking down -Z at the origin
	var small := Render.fit_ortho_size(cam, Vector3.ONE, 1.0)
	var big := Render.fit_ortho_size(cam, Vector3(2, 2, 2), 1.0)
	assert_almost_eq(small, 1.15, 0.001, "a unit box at 1:1 fits to 2*0.5*1.15 air = 1.15")
	assert_gt(big, small, "a bigger model needs a bigger ortho size")
	assert_between(small, 0.2, 4.0, "result is clamped into the safety range")


func test_save_png_null_image_fails_soft() -> void:
	assert_eq(Baker.save_png(null, "user://nope.png"), ERR_INVALID_DATA, "a null image returns an error, never crashes")


func test_grid_tile_baked_icon_absent_returns_null() -> void:
	var tile = GridTile.new()
	var item := Item.new()
	item.id = &"zzz_no_icon_exists_for_this"
	assert_null(tile._baked_icon(item), "no baked icon on disk -> null (grid falls back to the live mesh/glyph)")
	assert_null(tile._baked_icon(null), "null item -> null")
	item = null
	tile.free()


func test_icon_view_constructs() -> void:
	var v = IconView.new()
	assert_not_null(v, "the Icons tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Icons")
	v.free()
