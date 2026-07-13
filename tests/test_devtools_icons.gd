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


func test_refit_zooms_to_measured_pixels_and_recentres() -> void:
	# Art spans half the render on both axes, dead-centre: zoom in ~2× (× pad), no shift.
	var centred := Render.refit(1.0, 2.0, Rect2i(96, 48, 192, 96), Vector2i(384, 192), 1.06)
	assert_almost_eq(float(centred["size"]), 0.53, 0.0001, "ortho size shrinks to the measured art fraction × pad")
	assert_almost_eq(float(centred["dx"]), 0.0, 0.0001, "centred art -> no lateral shift")
	assert_almost_eq(float(centred["dy"]), 0.0, 0.0001, "centred art -> no vertical shift")
	# Art hugging the top-left corner: the camera shifts LEFT (negative x) and UP (positive y) toward it.
	var corner := Render.refit(1.0, 2.0, Rect2i(0, 0, 96, 96), Vector2i(384, 192), 1.06)
	assert_almost_eq(float(corner["dx"]), -0.75, 0.0001, "art left of centre -> camera moves left (in view-plane units)")
	assert_almost_eq(float(corner["dy"]), 0.25, 0.0001, "art above centre -> camera moves up (screen y is inverted)")
	# Degenerate measurement -> passthrough, never a zero/NaN zoom.
	var deg := Render.refit(1.0, 2.0, Rect2i(0, 0, 0, 0), Vector2i(384, 192))
	assert_almost_eq(float(deg["size"]), 1.0, 0.0001, "an empty used rect leaves the framing unchanged")


func test_crop_rect_pads_to_aspect_without_shrinking() -> void:
	# Used pixels 100×50 inside a 400×200 render, target aspect 2:1 (a 2×1 footprint), no margin for exact math.
	var r := Render.crop_rect(Rect2i(150, 75, 100, 50), Vector2i(400, 200), 2.0, 0.0)
	assert_eq(r, Rect2i(150, 75, 100, 50), "already at the target aspect -> the used rect verbatim")
	# A tall used rect must GROW WIDE to 2:1 — never shrink (art must stay inside the crop), centred on the art.
	var tall := Render.crop_rect(Rect2i(180, 50, 40, 100), Vector2i(400, 200), 2.0, 0.0)
	assert_eq(tall.size, Vector2i(200, 100), "short axis grows out to the target aspect")
	assert_eq(tall.position, Vector2i(100, 50), "growth is centred on the used pixels")


func test_crop_rect_margin_and_edge_shift() -> void:
	# 10% margin of the larger used side (100) = 10px each way.
	var m := Render.crop_rect(Rect2i(100, 50, 100, 100), Vector2i(400, 400), 1.0, 0.1)
	assert_eq(m, Rect2i(90, 40, 120, 120), "margin_frac pads the used rect on every side")
	# Art hugging the left edge: the aspect growth would go negative -> SHIFTED back inside, size intact.
	var edge := Render.crop_rect(Rect2i(0, 50, 40, 100), Vector2i(400, 200), 2.0, 0.0)
	assert_eq(edge.size, Vector2i(200, 100), "edge clamp shifts the crop, it doesn't shrink it")
	assert_eq(edge.position.x, 0, "crop shifted flush to the image edge, not out of bounds")


func test_crop_rect_degenerate_returns_full_image() -> void:
	var r := Render.crop_rect(Rect2i(0, 0, 0, 0), Vector2i(128, 64), 2.0)
	assert_eq(r, Rect2i(0, 0, 128, 64), "an empty used rect (nothing rendered) falls back to the full image")


func test_save_png_null_image_fails_soft() -> void:
	assert_eq(Baker.save_png(null, "user://nope.png"), ERR_INVALID_DATA, "a null image returns an error, never crashes")


func test_bake_model_for_prefers_mesh_then_world_prop() -> void:
	var bare := Item.new()
	bare.id = &"bare"
	assert_null(Baker.bake_model_for(bare), "no AUTHORED model -> null (bake_item then falls back to an IconModels stand-in)")
	var prop := Item.new()
	prop.id = &"crated"
	prop.world_prop = "res://scenes/dogcrate.tscn"
	assert_not_null(Baker.bake_model_for(prop), "a world_prop-only item (the dog crate) IS bakeable now")
	var meshed := Item.new()
	meshed.id = &"meshed"
	meshed.world_model = SphereMesh.new()
	meshed.world_prop = "res://scenes/dogcrate.tscn"
	assert_eq(Baker.bake_model_for(meshed), meshed.world_model, "an explicit world_model wins over the world_prop scene")
	assert_null(Baker.bake_model_for(null), "null item -> null")
	bare = null
	prop = null
	meshed = null


func test_grid_tile_authored_icon_wins() -> void:
	var item := Item.new()
	item.id = &"zzz_no_baked_icon"
	var authored := PlaceholderTexture2D.new()
	item.icon = authored
	assert_eq(GridTile.icon_for(item), authored, "an authored Item.icon wins over the (absent) baked PNG")
	item.icon = null
	assert_null(GridTile.icon_for(item), "no authored icon + no baked PNG -> null (mesh/glyph fallback)")
	item = null


func test_grid_tile_baked_icon_absent_returns_null() -> void:
	var tile = GridTile.new()
	var item := Item.new()
	item.id = &"zzz_no_icon_exists_for_this"
	assert_null(tile._baked_icon(item), "no baked icon on disk -> null (grid falls back to the live mesh/glyph)")
	assert_null(tile._baked_icon(null), "null item -> null")
	item = null
	tile.free()


## The icon-tint hook: a picked-up dog carries its live coat as RandomCoat.COAT_META, and the tile modulates its
## (white-baked) icon by that colour so the inventory art matches the actual dog. No meta -> white (a no-op multiply)
## so every other item draws unchanged; a captured tint comes back with alpha forced opaque so it recolours without
## fading the tile. This is the pure decision the drawn tile / drag-preview both feed through draw_item_icon.
func test_grid_tile_icon_modulate_from_coat_meta() -> void:
	assert_eq(GridTile.icon_modulate_for(null), Color.WHITE, "null item -> white (no tint)")
	var plain := Item.new()
	plain.id = &"zzz_no_coat"
	assert_eq(GridTile.icon_modulate_for(plain), Color.WHITE, "an item with no captured coat draws untinted (white)")
	var coated := Item.new()
	coated.id = &"zzz_coated_dog"
	coated.set_meta(RandomCoat.COAT_META, Color(0.62, 0.44, 0.26, 1.0))
	assert_eq(GridTile.icon_modulate_for(coated), Color(0.62, 0.44, 0.26, 1.0),
		"a captured coat tint modulates the icon so the tile shows the dog's real colour")
	# A stashed tint always arrives opaque; force alpha to 1 defensively so a stray non-opaque colour can't erase the art.
	var translucent := Item.new()
	translucent.id = &"zzz_translucent_coat"
	translucent.set_meta(RandomCoat.COAT_META, Color(0.4, 0.26, 0.15, 0.3))
	assert_eq(GridTile.icon_modulate_for(translucent), Color(0.4, 0.26, 0.15, 1.0),
		"the modulate alpha is forced opaque — the coat recolours the icon, never fades it")
	plain = null
	coated = null
	translucent = null


## Every shipped model-less item must build a non-empty procedural stand-in (icon_models.gd) — the "no more
## letter tiles" guarantee. Pure node construction, no renderer needed. Category/keyword routing is pinned by
## building each shipped id; the unknown-misc fallback must also produce meshes (the tinted pouch).
func test_icon_models_build_for_every_shipped_standin() -> void:
	var IconModels = load("res://addons/cybersunday_tools/dock_icons/icon_models.gd")
	var cases := [
		{"id": &"ammo_pistol", "cat": Item.Category.AMMO, "cal": &"pistol"},
		{"id": &"ammo_smg", "cat": Item.Category.AMMO, "cal": &"smg"},
		{"id": &"ammo_rifle", "cat": Item.Category.AMMO, "cal": &"rifle"},
		{"id": &"ammo_shells", "cat": Item.Category.AMMO, "cal": &"shells"},
		{"id": &"ammo_grenades", "cat": Item.Category.AMMO, "cal": &"grenades"},
		{"id": &"healthpack", "cat": Item.Category.CONSUMABLE, "heal": 6.0},
		{"id": &"lockpick", "cat": Item.Category.MISC},
		{"id": &"slice_package", "cat": Item.Category.MISC},
		{"id": &"chrome_grin", "cat": Item.Category.MISC},
		{"id": &"deadeye_optic", "cat": Item.Category.MISC},
		{"id": &"featherframe_weave", "cat": Item.Category.MISC},
		{"id": &"ironheart_locket", "cat": Item.Category.MISC},
		{"id": &"juggernaut_plate", "cat": Item.Category.MISC},
		{"id": &"kickstart_stims", "cat": Item.Category.MISC},
		{"id": &"mule_rig", "cat": Item.Category.MISC},
		{"id": &"rep_tags", "cat": Item.Category.MISC},
		{"id": &"second_wind_cell", "cat": Item.Category.MISC},
		{"id": &"trigger_bone", "cat": Item.Category.MISC},
		{"id": &"zz_totally_unknown_trinket", "cat": Item.Category.MISC},  # -> the tinted-pouch fallback
	]
	for c in cases:
		var item := Item.new()
		item.id = c["id"]
		item.category = c["cat"]
		if c.has("cal"):
			item.caliber = c["cal"]
		if c.has("heal"):
			item.heal_amount = c["heal"]
		var node = IconModels.build_for(item)
		assert_not_null(node, "%s builds a stand-in" % [c["id"]])
		if node != null:
			assert_gt(_mesh_count(node), 0, "%s stand-in has visible geometry" % [c["id"]])
			node.free()
		item = null
	assert_null(IconModels.build_for(null), "null item -> null (baker treats it as a failed bake)")


func _mesh_count(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for c in node.get_children():
		n += _mesh_count(c)
	return n


func test_grid_view_row_rotated_flags_swapped_footprints() -> void:
	var view = load("res://scripts/ui/grid_inventory_view.gd").new()
	var item := Item.new()
	item.id = &"rifle"
	item.grid_width = 4
	item.grid_height = 2
	assert_false(view._row_rotated({"item": item, "w": 4, "h": 2}), "authored footprint -> not rotated")
	assert_true(view._row_rotated({"item": item, "w": 2, "h": 4}), "swapped footprint -> rotated (draws turned 90°)")
	var square := Item.new()
	square.id = &"crate"
	square.grid_width = 2
	square.grid_height = 2
	assert_false(view._row_rotated({"item": square, "w": 2, "h": 2}), "a square footprint never reads as rotated")
	assert_false(view._row_rotated({"item": null, "w": 1, "h": 2}), "a null item never reads as rotated")
	item = null
	square = null
	view.free()


func test_icon_view_constructs() -> void:
	var v = IconView.new()
	assert_not_null(v, "the Icons tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Icons")
	v.free()
