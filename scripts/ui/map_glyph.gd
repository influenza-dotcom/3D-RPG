class_name MapGlyph
extends RefCounted

## @system Minimap
## @seam The pure SHAPE vocabulary the HUD minimap paints its markers with: shape_points() returns a closed polygon in SCREEN pixels (markers paint after draw_set_transform_matrix(IDENTITY), so a glyph is zoom-invariant by construction), npc_shape()/npc_is_hollow() map a body's live allegiance onto one of those shapes, and StationMarker.glyph_shape()/glyph_angle() map a station's Kind onto the rest.
## @seam SHAPE is the primary channel and HUE is the secondary one, deliberately: at marker radius ~4 px a salmon neutral and a red hostile are the same dot (and Settings.colorblind_safe_cues exists precisely because hue is contested), so the hostile/friendly/neutral distinction is carried by triangle/circle/ring FIRST and by CBPalette second.
## @risk Fill vs stroke is the family separator (NPCs are FILLED and small, stations are STROKED and larger). Painting a station filled — or an NPC stroked — collapses the two families into one alphabet, because TRIANGLE means "hostile body" in one and "somewhere to rest" in the other.
## @test res://tests/test_map_glyph.gd
##
## STATICS ONLY — no nodes, no tree access, no autoload reads, no Settings/GameSettings/MenuStyle — so every
## bit of maths here is provable off-tree exactly the way FloorplanSection, HudSway and Compass.project_to_edge
## are. The widget (scripts/ui/minimap.gd) keeps the impure half: scanning groups, reading dispositions, and
## choosing colours off MenuStyle.
##
## WHY A SEPARATE BRAIN FROM FloorplanSection. That one owns the PROJECTION (world metres -> pixels) and the
## section cut; this one owns marker ART in pixels and never sees a world coordinate or the view matrix. The
## two never need each other's numbers, and keeping them apart is what lets the glyph alphabet be unit-tested
## without a NavigationMesh.
##
## SCREEN CONVENTION. Godot 2D has +Y DOWN, so "up" is -Y. Every polygon here is built with its first vertex
## pointing screen-UP at angle 0, which is the same convention FloorplanSection.arrow_angle hands the player
## caret — so a glyph and the caret rotate identically when the map is in heading-up mode.

## The marker alphabet. Seven shapes, chosen to stay mutually distinguishable at a ~4-6 px radius on a 108 px
## box: they differ in VERTEX COUNT and silhouette, not in fine detail that the nearest upscale would eat.
## Order is stable — Kind -> Shape mappings and the tests index it by name, never by number.
enum Shape {
	CIRCLE,    ## a 12-gon; reads as a round dot / ring at this size
	TRIANGLE,  ## vertex up — the "threat" caret. RESERVED for hostiles in the NPC family
	DIAMOND,   ## a 4-gon vertex-up
	SQUARE,    ## a 4-gon rotated 45 deg from DIAMOND, so its EDGES are axis-aligned
	HEXAGON,   ## a 6-gon vertex-up
	CROSS,     ## a 12-point plus sign (concave — see shape_points)
	CHEVRON,   ## a filled arrowhead pointing up, with a notched tail
}

## Sides used to fake a circle. 12 is the point where a polygon stops reading as a polygon at 4-6 px; the same
## number FloorplanSource.ROUND_SIDES uses to facet a capsule/cylinder, for the same reason.
const CIRCLE_SIDES := 12

## Arm half-width of CROSS as a fraction of its radius. 0.36 keeps the plus readable rather than reading as a
## fat square at 5 px.
const CROSS_ARM := 0.36

## CHEVRON's tail notch depth as a fraction of its radius — how deep the V is cut into the arrowhead.
const CHEVRON_NOTCH := 0.45


## A closed polygon for `shape`, centred on (0, 0), sized to `radius` PIXELS, rotated `angle` radians
## clockwise-on-screen. Feed the result to draw_colored_polygon (filled) or draw_polyline (stroked — the
## caller re-appends the first point to close the loop; see closed()).
##
## A non-positive radius returns an EMPTY array rather than a degenerate polygon: Godot's draw calls treat an
## empty point list as a no-op, so a designer who zeroes a glyph size gets no marker instead of a crash or a
## single stray pixel.
static func shape_points(shape: int, radius: float, angle: float = 0.0) -> PackedVector2Array:
	if radius <= 0.0:
		return PackedVector2Array()
	match shape:
		Shape.CIRCLE:
			return ngon(CIRCLE_SIDES, radius, angle)
		Shape.TRIANGLE:
			return ngon(3, radius, angle)
		Shape.DIAMOND:
			return ngon(4, radius, angle)
		Shape.SQUARE:
			# A 4-gon is a DIAMOND; rotating it an eighth turn puts the flats on the axes. Sharing ngon here
			# rather than hand-writing four corners is what keeps SQUARE and DIAMOND provably the same size.
			return ngon(4, radius, angle + PI * 0.25)
		Shape.HEXAGON:
			return ngon(6, radius, angle)
		Shape.CROSS:
			return _cross_points(radius, angle)
		Shape.CHEVRON:
			return _chevron_points(radius, angle)
	return ngon(CIRCLE_SIDES, radius, angle)


## A regular polygon with its FIRST vertex pointing screen-up (-Y) at angle 0, wound clockwise on screen.
## `sides` below 3 degrades to a triangle rather than returning something undrawable.
static func ngon(sides: int, radius: float, angle: float = 0.0) -> PackedVector2Array:
	var n := maxi(sides, 3)
	var pts := PackedVector2Array()
	pts.resize(n)
	# -PI/2 is what puts vertex 0 at screen-up; TAU/n steps the rest evenly around.
	for i in n:
		var t := -PI * 0.5 + angle + TAU * (float(i) / float(n))
		pts[i] = Vector2(cos(t), sin(t)) * radius
	return pts


## The 12 points of a plus sign, wound as ONE simple (concave) polygon starting at the top-left of the upper
## arm. draw_colored_polygon triangulates a simple concave polygon, so this needs no decomposition into two
## rectangles — and one polygon is also one draw call and one stroke loop.
static func _cross_points(radius: float, angle: float) -> PackedVector2Array:
	var a := clampf(CROSS_ARM, 0.05, 0.9) * radius   ## arm half-width
	var r := radius
	var local := PackedVector2Array([
		Vector2(-a, -r), Vector2(a, -r), Vector2(a, -a),   # up arm, then out to the right
		Vector2(r, -a), Vector2(r, a), Vector2(a, a),      # right arm, then down
		Vector2(a, r), Vector2(-a, r), Vector2(-a, a),     # down arm, then out to the left
		Vector2(-r, a), Vector2(-r, -a), Vector2(-a, -a),  # left arm, back to the start
	])
	return _rotate(local, angle)


## A filled arrowhead pointing screen-up with a notched tail, so it reads as a DIRECTION (a way out, a way
## on) rather than as a solid triangle — which the NPC family reserves for "hostile".
static func _chevron_points(radius: float, angle: float) -> PackedVector2Array:
	var notch := clampf(CHEVRON_NOTCH, 0.05, 0.95) * radius
	var local := PackedVector2Array([
		Vector2(0.0, -radius),                     # tip
		Vector2(radius * 0.85, radius * 0.7),      # right wing
		Vector2(0.0, radius - notch),              # the notch, cut back up into the tail
		Vector2(-radius * 0.85, radius * 0.7),     # left wing
	])
	return _rotate(local, angle)


static func _rotate(local: PackedVector2Array, angle: float) -> PackedVector2Array:
	if is_zero_approx(angle):
		return local
	var r := Transform2D(angle, Vector2.ZERO)
	var out := PackedVector2Array()
	out.resize(local.size())
	for i in local.size():
		out[i] = r.basis_xform(local[i])
	return out


## The same ring with its first point repeated, which is what draw_polyline needs to close a loop (it strokes
## an open path). Kept here rather than at the call site so "stroked glyph" is one concept in one place.
## An empty or single-point input passes through untouched — closing a point is meaningless, not an error.
static func closed(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var out := points.duplicate()
	out.append(points[0])
	return out


## Offset every point by `centre`. draw_colored_polygon / draw_polyline take absolute canvas points, and the
## shape builders above are all centred on the origin, so this is the one translation step.
static func offset(points: PackedVector2Array, centre: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] + centre
	return out


## WHICH SHAPE AN NPC WEARS, from the same two facts CBPalette.disposition_color reads — so the shape channel
## and the hue channel can never disagree about the same body (a red circle or a green triangle would be a
## worse read than either channel alone).
##
##   companion -> DIAMOND   (a distinct silhouette: an ally is neither a threat nor scenery)
##   HOSTILE   -> TRIANGLE  (the threat caret; reserved — no station wears a FILLED triangle)
##   FRIENDLY  -> CIRCLE    (a plain dot: present, not a factor)
##   anything else (NEUTRAL, or a body that answers nothing) -> CIRCLE, and the widget strokes it HOLLOW
##
## Takes ints, not Disposition.Kind, so this file keeps its no-dependency promise; the widget does the enum
## read. `is_ally` wins over `disposition` — the same precedence CBPalette documents.
static func npc_shape(is_ally: bool, disposition: int, hostile_kind: int, friendly_kind: int) -> int:
	if is_ally:
		return Shape.DIAMOND
	if disposition == hostile_kind:
		return Shape.TRIANGLE
	if disposition == friendly_kind:
		return Shape.CIRCLE
	return Shape.CIRCLE


## Is this NPC's dot drawn as an outline instead of a solid? Only the NEUTRAL/unknown case — a bystander who
## is neither threat nor ally reads as an empty ring, which is the cheapest possible way to say "ignore me"
## and the one that survives the off-floor alpha fade best (a hollow ring keeps its silhouette at 0.3 alpha
## where a solid dot just dims into the backing).
static func npc_is_hollow(is_ally: bool, disposition: int, hostile_kind: int, friendly_kind: int) -> bool:
	if is_ally:
		return false
	return disposition != hostile_kind and disposition != friendly_kind


## THE ALERT RING's radius in pixels, or 0.0 for "draw nothing". A hostile that has noticed you grows a ring
## OUTSIDE its caret: one step per suspicion tier, so the ring reads as a rising threat without moving,
## recolouring or resizing the dot itself (all three would fight the disposition channel above).
##
## `tier` is a Perception.SuspicionTier int — 0 CALM / 1 WARY / 2 SUSPICIOUS / 3 ALERTED — passed as a plain
## int to keep this file dependency-free. CALM (and any out-of-range value, which is what an NPC that answers
## nothing degrades to) returns 0.0, so the common case costs one compare and no draw.
static func alert_ring_px(tier: int, glyph_px: float, gap_px: float, step_px: float) -> float:
	if tier <= 0 or glyph_px <= 0.0:
		return 0.0
	return glyph_px + gap_px + step_px * float(mini(tier, 3) - 1)


## HOW MANY SEGMENTS A BIG DRAWN CIRCLE NEEDS — the player's noise ring, whose radius is a WORLD distance in
## pixels and so ranges from a few px to well past the box, rather than sitting at one authored glyph size.
##
## ⭐THE FLOOR IS THE POINT, and it is deliberately far above CIRCLE_SIDES. This file strokes every station
## badge as an ngon at minimap_station_glyph_px (~5 px), so a lightly-segmented ring is not merely "a bit
## faceted" — at a walk ring's ~11 px a 16-gon has 4.3 px chords, which is the exact size AND construction of a
## station glyph, and the noise ring would read as a large badge rather than as a circle. Shape is this map's
## primary channel, so the two alphabets must not be able to collide. Segments are free; the facets are not,
## especially in RETRO where the ~2.4x nearest upscale hardens every chord.
##
## Ceiling at 64: past that the chords are sub-pixel and the extra vertices buy nothing.
static func ring_segments(radius_px: float) -> int:
	return clampi(int(radius_px * 1.2), 28, 64)


## WHICH WAY AN OFF-FLOOR MARKER LIES: +1 above the drawn storey, -1 below, 0 on it. The widget draws a tiny
## tick on that side of the glyph, which is the fix for the honest-but-mute alpha fade — a beacon two storeys
## up used to just dim, leaving the player to guess whether it was far away or overhead.
##
## The band is the same GameSettings.hud.minimap_band_height the deck cache and the alpha fade key off, and
## the threshold is HALF a band: inside that, a marker is on your floor for every other purpose too (the
## section cut is taken at chest height, so a marker anywhere in your own band is at eye level with you).
static func floor_tick(dy: float, band: float) -> int:
	if band <= 0.0:
		return 0
	var half := band * 0.5
	if dy > half:
		return 1
	if dy < -half:
		return -1
	return 0


## WHERE NORTH SITS on the box rim, as a unit direction in SCREEN space (+Y down). In heading-up mode the plan
## turns under a fixed caret, so world -Z ("north", matching FloorplanSection's north-up handedness where +Z
## draws DOWN) sweeps around the rim as the player turns; in north-up mode the plan is axis-locked and north is
## always straight up, so this returns (0, -1) and the tick becomes a static label.
##
## Derivation, checked against FloorplanSection.view_transform: that matrix rotates world (x, z) by `yaw` when
## rotate is true. World north is (x, z) = (0, -1), so on screen it lands at
## Transform2D(yaw).basis_xform(Vector2(0, -1)) = (sin yaw, -cos yaw). At yaw 0 that is (0, -1) — straight up,
## which is right: facing north with the map turning under you puts north at the top.
static func north_dir(yaw: float, rotate: bool) -> Vector2:
	if not rotate:
		return Vector2(0.0, -1.0)
	return Vector2(sin(yaw), -cos(yaw))
