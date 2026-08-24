extends GutTest

## FloorplanSection — the pure geometry brain behind the HUD minimap (scripts/ui/floorplan_section.gd).
## Everything risky about the minimap lives here as a static so it can be pinned off-tree, the HudSway /
## NavMeshAudit / Compass.project_to_edge split. The widget's PAINTING is playtest-verified; the projection,
## the band quantisation, the redraw gate and the navmesh fan are proven here.
##
## The load-bearing one is test_view_transform_rotate_puts_forward_at_screen_up: "rot = +yaw" is derived in
## the script's header, and a sign error there is invisible in code review but rotates the whole map backwards.

const FS := preload("res://scripts/ui/floorplan_section.gd")

## A synthetic NavigationMesh with no bake and no tree — enough for the fan/band/transform contracts.
func _mesh(verts: PackedVector3Array, polys: Array) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.set_vertices(verts)
	for p in polys:
		nm.add_polygon(p)
	return nm


# --- px_per_metre -------------------------------------------------------------------------------------

func test_px_per_metre_uses_the_short_axis() -> void:
	# A 200x100 box showing 40 m across its SHORT axis -> 100 px / 40 m.
	assert_almost_eq(FS.px_per_metre(Vector2(200, 100), 40.0, 1.0), 2.5, 0.0001,
			"the short axis sets the scale, so a non-square box never crops the promised span")

func test_px_per_metre_zoom_shows_fewer_metres() -> void:
	var one := FS.px_per_metre(Vector2(108, 108), 40.0, 1.0)
	var two := FS.px_per_metre(Vector2(108, 108), 40.0, 2.0)
	assert_almost_eq(two, one * 2.0, 0.0001, "zoom 2 shows half the metres -> twice the px/m (zooms IN)")
	var half := FS.px_per_metre(Vector2(108, 108), 40.0, 0.5)
	assert_almost_eq(half, one * 0.5, 0.0001, "zoom 0.5 shows twice the metres (zooms OUT)")

func test_px_per_metre_degenerate_inputs_are_safe() -> void:
	assert_almost_eq(FS.px_per_metre(Vector2.ZERO, 40.0, 1.0), 1.0, 0.0001, "zero rect -> 1.0, no divide by zero")
	assert_almost_eq(FS.px_per_metre(Vector2(108, 108), 0.0, 1.0), 1.0, 0.0001, "zero span -> 1.0")
	assert_almost_eq(FS.px_per_metre(Vector2(108, 108), 40.0, 0.0), 1.0, 0.0001, "zero zoom -> 1.0")
	assert_almost_eq(FS.px_per_metre(Vector2(108, 108), 40.0, -3.0), 1.0, 0.0001, "negative zoom -> 1.0")


# --- view_transform -----------------------------------------------------------------------------------

func test_view_transform_centres_the_player() -> void:
	var rect := Vector2(108, 108)
	var centre := Vector2(37.5, -12.25)
	for rotate in [true, false]:
		for zoom in [0.5, 1.0, 2.0, 3.0]:
			var ppm := FS.px_per_metre(rect, 40.0, zoom)
			var view := FS.view_transform(centre, 1.1, ppm, rect, rotate)
			var p: Vector2 = view * centre
			assert_almost_eq(p.x, rect.x * 0.5, 0.001,
					"the player's own world position always lands on the box centre (rotate=%s zoom=%s)" % [rotate, zoom])
			assert_almost_eq(p.y, rect.y * 0.5, 0.001, "...on both axes")

func test_view_transform_north_up_is_axis_locked() -> void:
	var rect := Vector2(100, 100)
	var centre := Vector2(5, 7)
	for yaw in [0.0, 0.9, PI, -2.2]:
		var view := FS.view_transform(centre, yaw, 2.0, rect, false)
		assert_almost_eq(view.get_rotation(), 0.0, 0.0001, "north-up never rotates, whatever the yaw (%s)" % yaw)
		var east: Vector2 = view * (centre + Vector2(1, 0))
		assert_almost_eq(east.x, 52.0, 0.001, "+world X goes RIGHT")
		assert_almost_eq(east.y, 50.0, 0.001, "...with no vertical component")
		var south: Vector2 = view * (centre + Vector2(0, 1))
		assert_almost_eq(south.y, 52.0, 0.001, "+world Z goes DOWN — the MapData.world_to_uv handedness")
		assert_almost_eq(south.x, 50.0, 0.001, "...with no horizontal component")

func test_view_transform_rotate_puts_forward_at_screen_up() -> void:
	# THE DERIVATION TEST. Godot forward at yaw t is (-sin t, -cos t) in the XZ plane; heading-up must put a
	# point 10 m ahead directly ABOVE the caret, at every yaw. A sign slip here mirrors the whole map.
	var rect := Vector2(100, 100)
	var centre := Vector2(-4, 11)
	var ppm := 2.0
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5, 2.37]:
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var view := FS.view_transform(centre, yaw, ppm, rect, true)
		var ahead: Vector2 = view * (centre + fwd * 10.0)
		assert_almost_eq(ahead.x, 50.0, 0.001, "10 m ahead stays on the caret's column at yaw %s" % yaw)
		assert_almost_eq(ahead.y, 30.0, 0.001, "...and 10 m * 2 px/m ABOVE it (screen -y) at yaw %s" % yaw)

func test_view_transform_scales_by_ppm() -> void:
	var rect := Vector2(100, 100)
	var a := FS.view_transform(Vector2.ZERO, 0.0, 3.0, rect, false)
	var p0: Vector2 = a * Vector2.ZERO
	var p1: Vector2 = a * Vector2(4, 0)
	assert_almost_eq(p0.distance_to(p1), 12.0, 0.001, "4 m at 3 px/m draws 12 px apart")


# --- arrow_angle --------------------------------------------------------------------------------------

func test_arrow_angle_is_zero_in_heading_up() -> void:
	for yaw in [0.0, 1.0, -2.5, PI]:
		assert_almost_eq(FS.arrow_angle(yaw, true), 0.0, 0.0001,
				"heading-up welds the caret pointing up and turns the world under it")

func test_arrow_angle_is_negative_yaw_in_north_up() -> void:
	for yaw in [0.0, 1.0, -2.5, PI]:
		assert_almost_eq(FS.arrow_angle(yaw, false), -yaw, 0.0001,
				"north-up freezes the world and spins the caret instead")


# --- stroke_width -------------------------------------------------------------------------------------

func test_stroke_width_survives_the_view_scale() -> void:
	for ppm in [0.5, 1.0, 2.7, 9.0]:
		assert_almost_eq(FS.stroke_width(2.0, ppm) * ppm, 2.0, 0.0001,
				"a 2 px stroke renders 2 px wide at any zoom (px/m = %s)" % ppm)

func test_stroke_width_zero_is_the_hairline_sentinel() -> void:
	assert_almost_eq(FS.stroke_width(0.0, 2.7), -1.0, 0.0001,
			"0 px -> Godot's -1.0 transform-INDEPENDENT hairline (the shipped default disarms the fatten trap)")
	assert_almost_eq(FS.stroke_width(-4.0, 2.7), -1.0, 0.0001, "negative is the same sentinel")


# --- band_floor / deck_key / cut_plane ------------------------------------------------------------------

func test_band_floor_quantises() -> void:
	assert_almost_eq(FS.band_floor(0.0, 2.6), 0.0, 0.0001, "the ground band starts at 0")
	assert_almost_eq(FS.band_floor(2.4, 2.6), 0.0, 0.0001, "still the ground band just under the ceiling")
	assert_almost_eq(FS.band_floor(3.0, 2.6), 2.6, 0.0001, "one storey up")
	assert_almost_eq(FS.band_floor(-0.1, 2.6), -2.6, 0.0001, "a basement floors DOWN, not toward zero")
	assert_almost_eq(FS.band_floor(5.0, 0.0), 5.0, 0.0001, "a zero band degrades to identity, never a divide by zero")

func test_deck_key_is_stable_inside_a_band() -> void:
	var k := FS.deck_key(0.0, 2.6)
	assert_eq(FS.deck_key(0.4, 2.6), k, "walking around one floor never re-slices the deck")
	assert_eq(FS.deck_key(2.4, 2.6), k, "...right up to the band's ceiling")

func test_deck_key_differs_across_bands() -> void:
	assert_ne(FS.deck_key(3.0, 2.6), FS.deck_key(0.0, 2.6), "a storey up is a different deck")
	assert_ne(FS.deck_key(-1.0, 2.6), FS.deck_key(0.0, 2.6), "a basement is a different deck")

func test_cut_plane_sits_above_the_origin() -> void:
	assert_almost_eq(FS.cut_plane(12.0, 1.2), 13.2, 0.0001,
			"the cut is chest height above the player's feet — never a downward raycast")


# --- needs_redraw -------------------------------------------------------------------------------------

func test_needs_redraw_is_false_when_still() -> void:
	assert_false(FS.needs_redraw(Vector2(3, 4), Vector2(3, 4), 1.0, 1.0, 0.02, 0.004),
			"a standing, still player costs literally nothing")
	assert_false(FS.needs_redraw(Vector2(3, 4), Vector2(3.01, 4), 1.0, 1.002, 0.02, 0.004),
			"sub-epsilon jitter does not repaint")

func test_needs_redraw_true_past_the_epsilon() -> void:
	assert_true(FS.needs_redraw(Vector2(3, 4), Vector2(3.5, 4), 1.0, 1.0, 0.02, 0.004), "a step repaints")
	assert_true(FS.needs_redraw(Vector2(3, 4), Vector2(3, 4), 1.0, 1.2, 0.02, 0.004), "a turn repaints")

func test_needs_redraw_wraps_the_yaw_seam() -> void:
	# The +-PI seam: without wrapf this reads as a full-circle flick every frame the player faces backwards.
	assert_false(FS.needs_redraw(Vector2.ZERO, Vector2.ZERO, PI - 0.001, -PI + 0.001, 0.02, 0.02),
			"crossing +-PI is a tiny turn, not a 2PI one")


# --- marker_alpha -------------------------------------------------------------------------------------

func test_marker_alpha_full_on_this_floor() -> void:
	assert_almost_eq(FS.marker_alpha(0.0, 2.6, 0.3), 1.0, 0.0001, "a marker at the player's height is solid")

func test_marker_alpha_fades_to_floor_alpha() -> void:
	assert_almost_eq(FS.marker_alpha(2.6, 2.6, 0.3), 0.3, 0.0001, "a full band away sits at the floor alpha")
	assert_almost_eq(FS.marker_alpha(-9.0, 2.6, 0.3), 0.3, 0.0001, "and never fades past it, above or below")

func test_marker_alpha_is_monotone() -> void:
	var prev := 2.0
	for dy in [0.0, 0.5, 1.0, 1.5, 2.0, 2.6, 5.0]:
		var a: float = FS.marker_alpha(dy, 2.6, 0.3)
		assert_lte(a, prev, "alpha never rises as the marker gets further away vertically (dy=%s)" % dy)
		assert_gte(a, 0.3, "...and never drops below the floor alpha")
		prev = a


# --- walkable_triangles -------------------------------------------------------------------------------

func test_walkable_triangles_null_navmesh_is_empty() -> void:
	# Must return empty and push NO engine error — GUT 9.6 fails the whole suite on one.
	var out := FS.walkable_triangles(null, Transform3D.IDENTITY, -1.0, 1.0)
	assert_eq(out.size(), 0, "a level with no baked navmesh simply has no walkable fill")

func test_walkable_triangles_unbaked_mesh_is_empty() -> void:
	var nm := NavigationMesh.new()
	assert_eq(FS.walkable_triangles(nm, Transform3D.IDENTITY, -1.0, 1.0).size(), 0, "0 polygons -> empty, no error")
	nm = null

func test_walkable_triangles_band_filters() -> void:
	# Two quads, one at y 0 and one at y 10. A [-1, 1) band keeps exactly one.
	var nm := _mesh(PackedVector3Array([
			Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
			Vector3(0, 10, 0), Vector3(1, 10, 0), Vector3(1, 10, 1), Vector3(0, 10, 1),
		]), [PackedInt32Array([0, 1, 2, 3]), PackedInt32Array([4, 5, 6, 7])])
	var out := FS.walkable_triangles(nm, Transform3D.IDENTITY, -1.0, 1.0)
	assert_eq(out.size(), 6, "one quad fans to 2 triangles = 6 vertices; the storey above is filtered out")
	for p in out:
		assert_lte(p.x, 1.001, "only the ground quad's footprint survives")
	nm = null

func test_walkable_triangles_is_a_multiple_of_three() -> void:
	# A convex 5-gon fans to 3 triangles. Fan integrity matters: a stray vertex shifts every triangle after it.
	var nm := _mesh(PackedVector3Array([
			Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 2), Vector3(1, 0, 3), Vector3(-1, 0, 2),
		]), [PackedInt32Array([0, 1, 2, 3, 4])])
	var out := FS.walkable_triangles(nm, Transform3D.IDENTITY, -1.0, 1.0)
	assert_eq(out.size(), 9, "a 5-gon fans to 3 triangles = 9 vertices")
	assert_eq(out.size() % 3, 0, "the buffer is always whole triangles")
	nm = null

func test_walkable_triangles_applies_the_region_transform() -> void:
	# The mesh's vertices are region-LOCAL; a level that offsets its NavigationRegion3D must not draw its
	# floor in the wrong place. Note the band is tested in WORLD space too — the offset moves it.
	var nm := _mesh(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]),
			[PackedInt32Array([0, 1, 2])])
	var xf := Transform3D(Basis.IDENTITY, Vector3(100, 0, -50))
	var out := FS.walkable_triangles(nm, xf, -1.0, 1.0)
	assert_eq(out.size(), 3, "the triangle survives the band filter at its WORLD height")
	assert_almost_eq(out[0].x, 100.0, 0.001, "the region's translation moves the fill in X")
	assert_almost_eq(out[0].y, -50.0, 0.001, "...and in Z")
	nm = null

func test_walkable_triangles_survives_out_of_range_indices() -> void:
	# A corrupt / partially-imported mesh must degrade to "no fill", never an engine error mid-draw.
	var nm := _mesh(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 0, 1)]),
			[PackedInt32Array([0, 1, 99])])
	assert_eq(FS.walkable_triangles(nm, Transform3D.IDENTITY, -1.0, 1.0).size(), 0,
			"an out-of-range polygon index is skipped, not indexed")
	nm = null


# --- sticky_band_key (the "map flips when I jump" fix) --------------------------------------------------

func test_sticky_band_takes_the_raw_answer_with_nothing_drawn() -> void:
	assert_eq(FS.sticky_band_key(0, false, 7.0, 2.6, 0.6), FS.deck_key(7.0, 2.6),
			"the first band drawn has nothing to stick to")

func test_sticky_band_holds_through_a_small_overshoot() -> void:
	# THE BUG: standing at 2.5 on a 2.6 band and rising to 2.7 crosses a boundary, and a raw quantisation
	# swapped the entire floorplan for it. Within the margin the drawn band must not move.
	assert_eq(FS.deck_key(2.7, 2.6), 1, "raw quantisation really does flip here — this is the bug")
	assert_eq(FS.sticky_band_key(0, true, 2.7, 2.6, 0.6), 0, "...and the sticky band does not")
	assert_eq(FS.sticky_band_key(0, true, -0.5, 2.6, 0.6), 0, "same just below the band's floor")

func test_sticky_band_releases_once_properly_clear() -> void:
	assert_eq(FS.sticky_band_key(0, true, 3.5, 2.6, 0.6), 1, "a full storey up does change the drawn floor")
	assert_eq(FS.sticky_band_key(0, true, -1.5, 2.6, 0.6), -1, "and so does dropping into a basement")

func test_sticky_band_clears_one_stair_riser() -> void:
	# This project's brush stairs have 0.5 m risers (CLAUDE.md). One step taken next to a boundary must not
	# swap the map, or climbing a flight strobes it.
	var band := 2.6
	var hyst := 0.6
	assert_gt(hyst, 0.5, "the shipped margin must exceed one riser or stairs flicker")
	assert_eq(FS.sticky_band_key(0, true, band + 0.4, band, hyst), 0, "one riser over the line still holds")

func test_sticky_band_is_stable_once_settled() -> void:
	# Idempotence: feeding the result back in must never oscillate, or the map alternates every frame.
	var key := 0
	for y in [2.7, 2.5, 2.8, 2.4, 2.9]:
		key = FS.sticky_band_key(key, true, y, 2.6, 0.6)
		assert_eq(key, 0, "jitter across the boundary never moves the drawn band (y=%s)" % y)

func test_sticky_band_degenerate_band_is_safe() -> void:
	assert_eq(FS.sticky_band_key(3, true, 9.0, 0.0, 0.6), FS.deck_key(9.0, 0.0),
			"a zero band cannot divide, so it falls through to the raw answer")


# --- silhouette (the boolean union, drawn as lines) -----------------------------------------------------
# A level is BUILT from overlapping boxes and a floorplan must not be DRAWN as one. These pin the union by
# MEASURING it: the total inked length of a merged pile is the union's perimeter, which is a number you can
# work out on paper for each fixture below and which no amount of "looks right" can fake.

## An axis-aligned rectangle ring, xz metres.
func _rect(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## Total inked length of a flat draw_multiline pair array — the measure every union test below is written in.
func _inked(pairs: PackedVector2Array) -> float:
	var total := 0.0
	var n := pairs.size() / 2
	for i in n:
		total += pairs[i * 2].distance_to(pairs[i * 2 + 1])
	return total


func test_silhouette_leaves_a_lone_solid_exactly_alone() -> void:
	# Nothing overlaps it, so it must come back byte-identical to the plain ring — the pass may not round-trip
	# an unchanged shape through Clipper and move its vertices.
	var rings: Array[PackedVector2Array] = [_rect(0, 0, 2, 2)]
	assert_eq(FS.silhouette(rings, PackedVector2Array(), 0.05), FS.ring_edges(rings[0]),
			"a solid with no neighbour draws its own authored cut, untouched")

func test_silhouette_drops_the_buried_seams() -> void:
	# THE PICTURE THIS FEATURE EXISTS FOR: two 2x2 squares overlapping corner-on-corner. Each keeps 6 of its 8
	# metres — the 1 m of each of two sides that runs inside the neighbour is interior seam, not wall.
	var rings: Array[PackedVector2Array] = [_rect(-1, -1, 1, 1), _rect(0, 0, 2, 2)]
	var merged := FS.silhouette(rings, PackedVector2Array(), 0.0)
	assert_almost_eq(_inked(merged), 12.0, 0.001,
			"the union outline measures 12 m; drawing both rings whole would ink 16 (2 m of it buried)")
	assert_eq(merged.size() % 2, 0, "draw_multiline still needs whole pairs")

func test_silhouette_welds_an_abutting_face() -> void:
	# THE COMMON BRUSH-LEVEL CASE and the reason weld exists: two boxes sharing the x = 2 face exactly. Probed
	# against the engine, a line lying precisely ON a clip polygon's boundary SURVIVES the difference, so
	# without a tolerance that shared face is drawn twice and the merge does nothing at all here.
	var rings: Array[PackedVector2Array] = [_rect(0, 0, 2, 2), _rect(2, 0, 4, 2)]
	assert_almost_eq(_inked(FS.silhouette(rings, PackedVector2Array(), 0.0)), 16.0, 0.001,
			"weld 0 is exact-overlaps-only: the shared face is still inked from both sides")
	var welded := _inked(FS.silhouette(rings, PackedVector2Array(), 0.05))
	assert_almost_eq(welded, 11.9, 0.01,
			"welded, the pair reads as ONE 4x2 room: 12 m of union perimeter less the four 0.025 m corner trims")

func test_silhouette_swallows_a_solid_that_is_wholly_inside_another() -> void:
	var rings: Array[PackedVector2Array] = [_rect(0, 0, 10, 10), _rect(4, 4, 6, 6)]
	assert_almost_eq(_inked(FS.silhouette(rings, PackedVector2Array(), 0.05)), 40.0, 0.001,
			"a solid buried inside another is interior matter: only the outer 40 m perimeter is inked")

## THE ANNIHILATION GUARD. A copy-pasted brush is a real authoring accident, and each copy buries the other —
## so a pass that let both clip would delete the shape from the map entirely. Failing SAFE here means drawing
## the outline twice, which is invisible; failing unsafe means a wall that is simply not there.
func test_silhouette_survives_a_duplicated_brush() -> void:
	var rings: Array[PackedVector2Array] = [_rect(0, 0, 2, 2), _rect(0, 0, 2, 2)]
	assert_almost_eq(_inked(FS.silhouette(rings, PackedVector2Array(), 0.05)), 16.0, 0.001,
			"two copies of one brush both survive whole — the failure guarded against is BOTH vanishing")

func test_silhouette_clips_the_trimesh_soup_but_never_by_it() -> void:
	# A trimesh cut is an unordered segment set, so it is hidden-line trimmed by the rings and never occludes:
	# chaining it back into loops would let a hollow CSG shell's outer loop swallow the whole level.
	var rings: Array[PackedVector2Array] = [_rect(0, 0, 2, 2)]
	var soup := PackedVector2Array([
		Vector2(0.5, 1.0), Vector2(1.5, 1.0),   # buried inside the ring
		Vector2(3.0, 1.0), Vector2(4.0, 1.0),   # out in the open
	])
	var merged := FS.silhouette(rings, soup, 0.05)
	assert_almost_eq(_inked(merged), 8.0 + 1.0, 0.001,
			"the ring's 8 m plus the 1 m segment outside it; the buried segment inks nothing")

func test_silhouette_of_nothing_is_nothing() -> void:
	var none: Array[PackedVector2Array] = []
	assert_eq(FS.silhouette(none, PackedVector2Array(), 0.05).size(), 0, "no solids, no strokes, no errors")
	var soup := PackedVector2Array([Vector2.ZERO, Vector2(1, 0)])
	assert_eq(FS.silhouette(none, soup, 0.05), soup, "with no rings to clip against, a soup passes through")


# --- the silhouette's parts ------------------------------------------------------------------------------

func test_open_ring_drops_the_closing_duplicate() -> void:
	# Geometry2D.convex_hull repeats the first point and Clipper's polygon input must not.
	var closed := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0)])
	assert_eq(FS.open_ring(closed).size(), 3, "the repeat is dropped")
	assert_eq(FS.open_ring(FS.open_ring(closed)).size(), 3, "and dropping it is idempotent")

func test_closed_polyline_closes_the_ring() -> void:
	var pl := FS.closed_polyline(_rect(0, 0, 1, 1))
	assert_eq(pl.size(), 5, "4 corners + the repeat, so the ring's LAST edge is clipped like every other one")
	assert_eq(pl[0], pl[4], "...and it really is the same point")

func test_polyline_edges_never_wraps_around() -> void:
	# The difference from ring_edges, and it matters: a clipped piece is a FRAGMENT of an outline, so joining
	# its ends would ink a chord straight across the room.
	var pl := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	assert_eq(FS.polyline_edges(pl).size(), 4, "3 points -> 2 segments, not 3")
	assert_eq(FS.ring_edges(pl).size(), 6, "...whereas the same 3 points AS A RING close up into 3")
	assert_eq(FS.polyline_edges(PackedVector2Array([Vector2.ZERO])).size(), 0, "a single point is not an edge")

func test_grow_ring_grows_on_both_axes() -> void:
	# The load-bearing direction: offset_polygon's sign is documented against the path's ORIENTATION, and an
	# occluder that SHRANK would leave every seam this pass exists to erase.
	for ring in [_rect(0, 0, 2, 2), FS.closed_polyline(_rect(0, 0, 2, 2))]:
		var g: PackedVector2Array = FS.grow_ring(ring, 0.25)
		var b := FS.ring_bounds(g)
		assert_almost_eq(b.size.x, 2.5, 0.001, "grown by delta on each side in X")
		assert_almost_eq(b.size.y, 2.5, 0.001, "...and in Z")

func test_grow_ring_of_a_reversed_winding_still_grows() -> void:
	var ring := _rect(0, 0, 2, 2)
	ring.reverse()
	var b := FS.ring_bounds(FS.grow_ring(ring, 0.25))
	assert_almost_eq(b.size.x, 2.5, 0.001, "winding must not decide the direction of the offset")

func test_grow_ring_zero_delta_is_the_ring_itself() -> void:
	var ring := _rect(0, 0, 2, 2)
	assert_eq(FS.grow_ring(ring, 0.0), ring, "weld 0 = exact overlaps only, and no Clipper round trip")
	assert_eq(FS.grow_ring(PackedVector2Array([Vector2.ZERO, Vector2(1, 0)]), 0.25).size(), 2,
			"a degenerate two-point 'ring' is handed back rather than offset")

func test_ring_contains_ring() -> void:
	var big := _rect(0, 0, 10, 10)
	assert_true(FS.ring_contains_ring(big, _rect(4, 4, 6, 6)), "wholly inside")
	assert_false(FS.ring_contains_ring(big, _rect(9, 9, 11, 11)), "poking out is NOT contained")
	assert_false(FS.ring_contains_ring(big, _rect(20, 20, 21, 21)), "nowhere near")
	assert_true(FS.ring_contains_ring(big, big),
			"a ring contains ITSELF — that is what resolves the duplicated-brush case instead of a rounding")
