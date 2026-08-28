extends GutTest

## MapGlyph (scripts/ui/map_glyph.gd) — the minimap's marker SHAPE vocabulary. Statics only, so every
## assertion here runs off-tree with no widget, no navmesh, no player and no autoloads (the
## test_floorplan_section.gd model).
##
## What is pinned here is the part that is invisible when it breaks: a glyph is 4-6 px on a 108 px box, so a
## polygon wound the wrong way, sized inconsistently between two shapes, or pointing 180 degrees out reads as
## "the map looks a bit off" rather than as a bug. The allegiance mapping is pinned hardest, because
## Minimap.npc_dot_color reads the SAME two facts for hue — a body drawn as an ally diamond in hostile red
## would be worse than either channel alone.

## Loaded BY PATH, not by class_name, so the suite survives a stale global class cache (the ui.gd
## STAMINA_RING_SCRIPT idiom that test_minimap.gd follows for the same reason).
const MAP_GLYPH := "res://scripts/ui/map_glyph.gd"

## Disposition ints are passed IN to MapGlyph (it keeps a no-dependency promise), so the test supplies the
## same two the widget does.
const HOSTILE := Disposition.Kind.HOSTILE
const FRIENDLY := Disposition.Kind.FRIENDLY
const NEUTRAL := Disposition.Kind.NEUTRAL


func _g() -> GDScript:
	return load(MAP_GLYPH)


# --- the shapes themselves -----------------------------------------------------------------------------

## Each shape must produce the vertex count its silhouette needs. Wrong counts are how a "hexagon" quietly
## becomes a square that nobody can tell from the TECH glyph.
func test_each_shape_has_its_own_vertex_count() -> void:
	var g := _g()
	assert_eq(g.shape_points(g.Shape.TRIANGLE, 5.0).size(), 3, "a triangle is three points")
	assert_eq(g.shape_points(g.Shape.DIAMOND, 5.0).size(), 4, "a diamond is four")
	assert_eq(g.shape_points(g.Shape.SQUARE, 5.0).size(), 4, "so is a square — it is a rotated diamond")
	assert_eq(g.shape_points(g.Shape.HEXAGON, 5.0).size(), 6, "a hexagon is six")
	assert_eq(g.shape_points(g.Shape.CIRCLE, 5.0).size(), g.CIRCLE_SIDES,
			"a circle is CIRCLE_SIDES-gon — the point where a polygon stops reading as one at this size")
	assert_eq(g.shape_points(g.Shape.CROSS, 5.0).size(), 12, "a plus sign is twelve points")
	assert_eq(g.shape_points(g.Shape.CHEVRON, 5.0).size(), 4, "an arrowhead with a notched tail is four")

## A non-positive radius must yield NOTHING, not a degenerate polygon. Godot's draw calls no-op on an empty
## point list, so a designer who zeroes a glyph size gets no marker rather than a stray pixel or a crash.
func test_a_zero_radius_draws_nothing() -> void:
	var g := _g()
	for shape in [g.Shape.CIRCLE, g.Shape.TRIANGLE, g.Shape.DIAMOND, g.Shape.SQUARE, g.Shape.HEXAGON,
			g.Shape.CROSS, g.Shape.CHEVRON]:
		assert_eq(g.shape_points(shape, 0.0).size(), 0, "radius 0 is an empty polygon for shape %s" % shape)
		assert_eq(g.shape_points(shape, -3.0).size(), 0, "and so is a negative radius for shape %s" % shape)

## THE ORIENTATION CONTRACT: vertex 0 points screen-UP (-Y, since Godot 2D is +Y down). Every shape builder
## and the player caret share this convention, which is what lets a glyph and the caret rotate together.
func test_first_vertex_points_screen_up() -> void:
	var g := _g()
	for shape in [g.Shape.CIRCLE, g.Shape.TRIANGLE, g.Shape.DIAMOND, g.Shape.HEXAGON]:
		var p: Vector2 = g.shape_points(shape, 6.0)[0]
		assert_almost_eq(p.x, 0.0, 0.0001, "vertex 0 sits on the vertical axis for shape %s" % shape)
		assert_almost_eq(p.y, -6.0, 0.0001, "...and points UP (-Y), not down, for shape %s" % shape)

## SQUARE is DIAMOND rotated an eighth turn — same size, edges on the axes instead of corners. Sharing ngon
## is what makes that provable rather than a matter of two hand-written vertex lists agreeing by luck.
func test_square_is_a_diamond_turned_an_eighth() -> void:
	var g := _g()
	var d: PackedVector2Array = g.shape_points(g.Shape.DIAMOND, 4.0)
	var s: PackedVector2Array = g.shape_points(g.Shape.SQUARE, 4.0)
	assert_almost_eq(d[0].length(), s[0].length(), 0.0001, "both inscribe the same radius")
	assert_almost_eq(absf(s[0].x), absf(s[0].y), 0.0001, "a square's corner sits on the diagonal")
	assert_almost_eq(absf(d[0].x), 0.0, 0.0001, "...where a diamond's sits on the axis")

## Every vertex of a regular shape must be exactly `radius` from the centre — the property that makes two
## different shapes at the same authored px read as the same visual weight.
func test_regular_shapes_inscribe_their_radius() -> void:
	var g := _g()
	for shape in [g.Shape.CIRCLE, g.Shape.TRIANGLE, g.Shape.DIAMOND, g.Shape.SQUARE, g.Shape.HEXAGON]:
		for p in g.shape_points(shape, 7.0):
			assert_almost_eq(p.length(), 7.0, 0.0001, "shape %s keeps every vertex on the radius" % shape)

## Rotation must turn the shape without resizing it — the guard against a rotation written as a shear.
func test_rotation_preserves_size() -> void:
	var g := _g()
	var a: PackedVector2Array = g.shape_points(g.Shape.TRIANGLE, 5.0, 0.0)
	var b: PackedVector2Array = g.shape_points(g.Shape.TRIANGLE, 5.0, PI * 0.5)
	assert_eq(a.size(), b.size(), "same point count either way")
	for i in b.size():
		assert_almost_eq(b[i].length(), 5.0, 0.0001, "a rotated vertex keeps its radius")
	assert_almost_eq(b[0].x, 5.0, 0.0001, "a quarter turn puts the up-vertex at screen-right")

## CROSS must actually be a plus — its arms narrower than its span — or it renders as a fat square and
## collides with the TECH glyph.
func test_cross_is_narrower_across_its_arms_than_its_span() -> void:
	var g := _g()
	var pts: PackedVector2Array = g.shape_points(g.Shape.CROSS, 10.0)
	var max_x := 0.0
	var min_abs_x := INF
	for p in pts:
		max_x = maxf(max_x, absf(p.x))
		min_abs_x = minf(min_abs_x, absf(p.x))
	assert_almost_eq(max_x, 10.0, 0.0001, "the arms reach the full radius")
	assert_lt(min_abs_x, max_x * 0.5, "and the waist is well inside it — this is what makes it read as a plus")


# --- ring / offset helpers ------------------------------------------------------------------------------

## closed() is what stops a stroked glyph showing a notch: draw_polyline strokes an OPEN path, so the ring
## has to come back to its first point.
func test_closed_repeats_the_first_point() -> void:
	var g := _g()
	var pts: PackedVector2Array = g.shape_points(g.Shape.DIAMOND, 3.0)
	var ring: PackedVector2Array = g.closed(pts)
	assert_eq(ring.size(), pts.size() + 1, "closing adds exactly one point")
	assert_eq(ring[ring.size() - 1], ring[0], "...and it is the first one again")

## Degenerate inputs pass through rather than erroring — closing a single point is meaningless, not a fault.
func test_closed_passes_through_degenerate_input() -> void:
	var g := _g()
	assert_eq(g.closed(PackedVector2Array()).size(), 0, "an empty ring stays empty")
	assert_eq(g.closed(PackedVector2Array([Vector2.ONE])).size(), 1, "a single point stays single")

func test_offset_translates_every_point() -> void:
	var g := _g()
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(1.0, 2.0)])
	var moved: PackedVector2Array = g.offset(pts, Vector2(10.0, 20.0))
	assert_eq(moved[0], Vector2(10.0, 20.0), "the origin moves to the centre")
	assert_eq(moved[1], Vector2(11.0, 22.0), "and everything else moves with it")


# --- the allegiance mapping ----------------------------------------------------------------------------

## THE SHAPE HALF of the hostile/friendly/neutral distinction — the whole reason this file exists. Hue alone
## could not carry it at a 4 px glyph, and Settings.colorblind_safe_cues exists because hue is contested even
## at size.
func test_npc_shape_by_allegiance() -> void:
	var g := _g()
	assert_eq(g.npc_shape(false, HOSTILE, HOSTILE, FRIENDLY), g.Shape.TRIANGLE,
			"a hostile is the threat caret")
	assert_eq(g.npc_shape(false, FRIENDLY, HOSTILE, FRIENDLY), g.Shape.CIRCLE, "a friendly is a plain dot")
	assert_eq(g.npc_shape(false, NEUTRAL, HOSTILE, FRIENDLY), g.Shape.CIRCLE,
			"so is a neutral — the RING is what separates them, see npc_is_hollow")

## A recruited companion wins over disposition, the same precedence CBPalette.disposition_color documents —
## so the shape and the hue can never disagree about the same body.
func test_a_companion_shape_beats_its_disposition() -> void:
	var g := _g()
	assert_eq(g.npc_shape(true, HOSTILE, HOSTILE, FRIENDLY), g.Shape.DIAMOND,
			"a companion is a diamond even mid-grudge")
	assert_eq(g.npc_shape(true, NEUTRAL, HOSTILE, FRIENDLY), g.Shape.DIAMOND, "...and from neutral too")

## Only a NEUTRAL body is hollow. That ring is the cheapest possible "ignore me", and it is also the shape
## that survives the off-floor alpha fade best — an outline keeps its silhouette where a solid dot just dims.
func test_only_a_neutral_is_hollow() -> void:
	var g := _g()
	assert_true(g.npc_is_hollow(false, NEUTRAL, HOSTILE, FRIENDLY), "a bystander is an empty ring")
	assert_false(g.npc_is_hollow(false, HOSTILE, HOSTILE, FRIENDLY), "a hostile is filled")
	assert_false(g.npc_is_hollow(false, FRIENDLY, HOSTILE, FRIENDLY), "a friendly is filled")
	assert_false(g.npc_is_hollow(true, NEUTRAL, HOSTILE, FRIENDLY), "and a companion is filled, disposition aside")


# --- the alert ring ------------------------------------------------------------------------------------

## CALM draws nothing at all — the common case must cost one compare and no draw, because this runs per
## hostile per frame in a level that already repaints every frame.
func test_a_calm_hostile_has_no_ring() -> void:
	var g := _g()
	assert_eq(g.alert_ring_px(0, 4.0, 2.0, 1.5), 0.0, "CALM is no ring")
	assert_eq(g.alert_ring_px(-1, 4.0, 2.0, 1.5), 0.0, "and so is an out-of-range tier (a body that answers nothing)")
	assert_eq(g.alert_ring_px(3, 0.0, 2.0, 1.5), 0.0, "a zero-size glyph has nothing to ring")

## The ring GROWS with the tier rather than recolouring, so the threat level survives the colourblind palette
## swap. Each step is exactly one step_px further out.
func test_the_ring_grows_one_step_per_tier() -> void:
	var g := _g()
	var wary: float = g.alert_ring_px(1, 4.0, 2.0, 1.5)
	var sus: float = g.alert_ring_px(2, 4.0, 2.0, 1.5)
	var alerted: float = g.alert_ring_px(3, 4.0, 2.0, 1.5)
	assert_almost_eq(wary, 6.0, 0.0001, "WARY clears the caret by the authored gap")
	assert_almost_eq(sus - wary, 1.5, 0.0001, "SUSPICIOUS is one step further out")
	assert_almost_eq(alerted - sus, 1.5, 0.0001, "ALERTED is one more")
	assert_gt(wary, 4.0, "every ring sits OUTSIDE the caret it annotates — it must not overdraw the disposition shape")

## A tier above the enum's range clamps instead of growing without bound — a defensive clamp, since the tier
## arrives as a duck-typed int from a live NPC.
func test_the_ring_clamps_above_the_top_tier() -> void:
	var g := _g()
	assert_eq(g.alert_ring_px(9, 4.0, 2.0, 1.5), g.alert_ring_px(3, 4.0, 2.0, 1.5),
			"a nonsense tier reads as ALERTED, never as a ring off the edge of the box")


# --- vertical honesty + north --------------------------------------------------------------------------

## The up/down tick's direction. Half a band is the threshold: inside it, a marker is on your floor for every
## other purpose too (the section cut is taken at chest height).
func test_floor_tick_direction() -> void:
	var g := _g()
	assert_eq(g.floor_tick(0.0, 2.6), 0, "same floor, no tick")
	assert_eq(g.floor_tick(1.2, 2.6), 0, "still inside the band's half-height")
	assert_eq(g.floor_tick(2.0, 2.6), 1, "a storey up ticks UP")
	assert_eq(g.floor_tick(-2.0, 2.6), -1, "a storey down ticks DOWN")
	assert_eq(g.floor_tick(5.0, 0.0), 0, "a degenerate band never ticks rather than dividing by zero")

## North-up mode has north permanently at the top — the tick is then redundant, and the widget skips drawing
## it, but the maths must still be honest.
func test_north_is_straight_up_in_north_up_mode() -> void:
	var g := _g()
	var n: Vector2 = g.north_dir(1.234, false)
	assert_almost_eq(n.x, 0.0, 0.0001, "north-up puts north on the vertical axis whatever the player's yaw")
	assert_almost_eq(n.y, -1.0, 0.0001, "...pointing UP")

## HEADING-UP is the mode the tick exists for: the plan turns under a fixed caret, so north sweeps the rim.
## Pinned at the cardinals against FloorplanSection.view_transform's own convention.
func test_north_sweeps_the_rim_in_heading_up_mode() -> void:
	var g := _g()
	var facing_north: Vector2 = g.north_dir(0.0, true)
	assert_almost_eq(facing_north.y, -1.0, 0.0001, "facing north, north is at the top of the box")
	var facing_west: Vector2 = g.north_dir(PI * 0.5, true)
	assert_almost_eq(facing_west.x, 1.0, 0.0001, "facing west, north is to your RIGHT")
	assert_almost_eq(facing_west.y, 0.0, 0.0001, "...and level with you")
	var facing_south: Vector2 = g.north_dir(PI, true)
	assert_almost_eq(facing_south.y, 1.0, 0.0001, "facing south, north is behind you — the bottom of the box")

## Every direction it returns is a unit vector, because the widget projects it onto the rim and a
## non-normalised input would land the tick off the edge.
func test_north_dir_is_always_unit_length() -> void:
	var g := _g()
	for i in 12:
		var yaw := TAU * (float(i) / 12.0)
		assert_almost_eq(g.north_dir(yaw, true).length(), 1.0, 0.0001, "unit at yaw %s" % yaw)


## RING SEGMENTS — the noise ring's tessellation, and specifically its FLOOR.
##
## The claim this pins is not "circles look nicer with more sides", it is that the noise ring must never land
## inside the STATION GLYPH alphabet. This same file strokes station badges as ngons at
## minimap_station_glyph_px (~5 px), and shape is the minimap's primary channel, so a lightly-segmented ring at
## a walk radius would read as a large station badge rather than as a circle. Hence a floor far above
## CIRCLE_SIDES rather than the 12-16 an "it looks round enough" eyeball would pick.
func test_ring_segments_never_lands_in_the_station_glyph_alphabet() -> void:
	# A walk ring (~11 px at the shipped scale) is the dangerous size — it is exactly station-badge territory.
	assert_gt(MapGlyph.ring_segments(11.0), MapGlyph.CIRCLE_SIDES,
			"a walk-sized ring must be far better tessellated than a station ngon, or it reads as one")
	assert_gte(MapGlyph.ring_segments(11.0), 28, "...which is what the floor is for")


## Monotone and clamped at both ends: a bigger ring never gets FEWER sides, a degenerate radius still returns a
## drawable count, and a huge one stops paying for sub-pixel chords.
func test_ring_segments_is_monotone_and_clamped() -> void:
	var prev := 0
	for r in [0.0, 1.0, 11.0, 30.0, 76.0, 400.0, 10000.0]:
		var n := MapGlyph.ring_segments(float(r))
		assert_gte(n, prev, "segment count never decreases as the ring grows (at %s px)" % r)
		assert_between(n, 28, 64, "and stays inside the authored bounds (at %s px)" % r)
		prev = n
	assert_eq(MapGlyph.ring_segments(0.0), 28, "a zero radius still returns the floor rather than 0 sides")
	assert_eq(MapGlyph.ring_segments(10000.0), 64, "and an absurd one is capped")
