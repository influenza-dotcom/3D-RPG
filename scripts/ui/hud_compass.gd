class_name HudCompass
extends Control

## @system HUD Compass
## @seam Code-built by ui.gd at the TOP CENTRE, riding the `_weighted` HUD-weight carrier with the minimap and the clock — so it sways, ghosts and bends through the HUD curve like every other readout. That makes it the DELIBERATE EXCEPTION to ui.gd's moved-vs-pinned rule, which would otherwise pin a bearing; the trade and its layout bill are written out in that header. Layout comes from GameSettings.hud.compass_*, paint from MenuStyle.hud.compass_* (the same skin group the screen-edge Compass already owns), and the player's on/off is polled LIVE off Settings.compass_enabled so an Options change bites the same frame with no HUD rebuild (the minimap_enabled / clock_enabled idiom).
## @seam IT OWNS THE TOP BAND, so everything in the centre-top column below it is pushed down by UI.centre_column_top_for — the ladder rides ui.gd's `_centre_column` carrier and player_hud.gd parents into it. Widen this tape (compass_size.y) and the whole column slides; it never collides. ⭐The column is PINNED while this tape SWAYS, so compass_column_gap is a sway budget rather than breathing room — shrink it and the rose lands on the enemy health bar on the next hard flick.
## @seam ⭐RIDING THE CARRIER MEANS THE LOCAL VIEWPORT IS NOT THE WORLD'S. While the HUD curve is up, `_weighted` is reparented into a SubViewport that holds no Camera3D at all, so `get_viewport().get_camera_3d()` answers null there — the tape would freeze at whatever bearing it last painted. `_active_camera()` is the fix and every camera read goes through it.
## @seam Reads the ACTIVE Camera3D's yaw — the SAME source Minimap._camera_yaw uses, so the tape and the floorplan's north tick can never disagree about which way is north. It is a READER only.
## @seam Marker pips come from the `compass` group (Groups.COMPASS) — the SAME WorldMarker / QuestObjective channel the screen-edge Compass draws chevrons for. Drop one WorldMarker and it shows on both surfaces; there is no second registry to author. (That edge overlay is RETIRED — nothing instantiates it — so in a shipped run this tape is the only surface that channel reaches.)
## @seam SECOND PIP CHANNEL, and the one the player authors: their TRACKED waypoint (GameState.tracked_waypoint — at most one pin per profile) draws a pip at its own bearing, tinted from the minimap's waypoint palette so a pin is the same colour on the tape as on the corner box. It is read off the LEDGER rather than from any node (a waypoint has no presence in the world), and only while it belongs to the level being played. ⭐GameState.waypoints_rev is folded into the repaint signature for it: the pin's bearing says nothing about whether it is still tracked, still on this level, or still there at all.
## @risk World NORTH is -Z and EAST is +X. That is baked into bearing_from_yaw / bearing_between here, into Minimap's north tick (MapGlyph.north_dir) and into DayNightSky's sun arc; re-basing any one of them alone silently makes the compass lie.
## @risk The tape pauses with the tree, so it freezes during a dialogue — correct (the player cannot turn), and ui.gd hides it for the conversation anyway.
## @test res://tests/test_hud_compass.gd
##
## The HUD's BEARING readout: a horizontal heading tape across the top-centre of the screen, marked with the
## eight cardinal/intercardinal letters, minor degree ticks between them, a pip for every active
## objective/point-of-interest marker at ITS bearing, and a pip for the place the PLAYER declared they are
## walking to (the tracked map pin — the in-world Mark Waypoint key sets one in a single press).
##
## WHY IT EXISTS. The minimap is the only other bearing instrument, and in its shipped HEADING-UP mode it has
## no fixed direction at all — the plan turns under a fixed caret, so spinning on the spot moves every
## landmark and nothing on screen says which way you are pointing. (Its north tick is a spoke on a 108 px rim;
## minimap.gd's own comment records that a LETTER there would be a smudge.) A tape reads a bearing at a glance
## without a map, and it survives the map being switched off entirely.
##
## WHY A DRAWN TAPE AND NOT LABELS. At the 792x444 canvas (nearest-upscaled ~2.4x to the window) the letters
## slide CONTINUOUSLY across the band — a Label per cardinal would need eight nodes re-positioned every frame,
## each re-shaping its glyph run to draw the same "N". One _draw stamps the visible handful and nothing else.
##
## THE HEADING GATE. The tape only changes when the CAMERA turns, a marker moves, or the pin ledger is written
## to. All three are folded to a scalar and compared before asking for a repaint (the minimap's idle-gate
## idiom, and HudClock's minute gate) — a standing-still player pays one float compare, one small group walk
## and one bounded ledger read a frame, not a full vector repaint.
## `_drawn_heading` is seeded outside 0..360 so the FIRST processed frame always paints (a player who happens
## to spawn facing exactly north must not be mistaken for "unchanged since boot").

## Degrees in a full turn, and the arc between two cardinal letters. NOT designer knobs: they are the
## definition of a compass, and an "eleven-point rose" would be a different instrument, not a retuned one.
const FULL_TURN := 360.0
const CARDINAL_STEP := 45.0

## Repaint thresholds. A heading move under a third of a degree cannot shift a glyph by a whole canvas pixel
## at any sane span, and a marker bearing is quantised to whole degrees before it enters the signature below.
const HEADING_EPS := 0.3

## The heading last painted, in degrees. -1 is the "nothing painted yet" seed — outside 0..360, so the first
## frame always stamps even when facing due north.
var _drawn_heading: float = -1.0
## Signature of the PIP SET last painted, across BOTH channels: the group markers' quantised bearings, the
## waypoint ledger's revision, and the tracked pin's own quantised bearing. A pip that has not moved a whole
## degree is not a repaint; one appearing, expiring, being untracked or crossing a degree boundary is.
var _drawn_pips: int = 0


func _ready() -> void:
	# Every HUD element in this project is explicitly IGNORE: the default MOUSE_FILTER_STOP would make this
	# band eat clicks across the whole top of the screen.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	# A HIDDEN COMPASS COSTS NOTHING — not a camera read, not a group walk (the minimap's opening line, same
	# reasoning). ui.gd owns the hiding; this makes OFF genuinely free rather than a hidden node still working.
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var cam := _active_camera()
	if cam == null:
		return
	var heading := bearing_from_yaw(camera_yaw(cam))
	var sig := _pip_signature(cam)
	if sig == _drawn_pips and absf(wrapf(heading - _drawn_heading, -180.0, 180.0)) < HEADING_EPS:
		return
	_drawn_heading = heading
	_drawn_pips = sig
	queue_redraw()


## Cheap change-detector for BOTH pip channels: each group marker's bearing rounded to a whole degree, folded
## together with the waypoint ledger's revision and the tracked pin's own rounded bearing. Two different sets
## colliding on one int would cost a missed repaint for a single frame, which is why this is a hash and not a
## promise — the heading gate above repaints anyway the moment the player turns, and a marker that moves
## without the player turning is a slow world event.
##
## ⭐waypoints_rev IS THE HALF THAT CANNOT BE DERIVED FROM THE BEARING. Untracking the pin, deleting it,
## tracking a different one at the same bearing, or walking through a LevelDoor into a level it does not
## belong to all leave the arithmetic below unchanged while changing what must be inked — and a standing
## player passes the heading gate, so nothing else would ever ask for the repaint. GameState bumps that
## counter on every ledger write INCLUDING a level swap, which is exactly the set of events this needs.
func _pip_signature(cam: Camera3D) -> int:
	var sig := 0
	var eye := Vector2(cam.global_position.x, cam.global_position.z)
	for n in get_tree().get_nodes_in_group(Groups.COMPASS):
		if n is Node3D:
			var wp: Vector3 = (n as Node3D).global_position
			sig = sig * 31 + int(roundf(bearing_between(eye, Vector2(wp.x, wp.z))))
	sig = sig * 31 + GameState.waypoints_rev
	var rec := tracked_pin()
	if not rec.is_empty():
		var pin: Vector3 = rec.get("pos")
		sig = sig * 31 + int(roundf(bearing_between(eye, Vector2(pin.x, pin.z))))
	return sig


## THE WORLD'S ACTIVE CAMERA, resolved so it survives being nested inside a SubViewport.
##
## ⭐`get_viewport()` IS NOT THE WORLD'S VIEWPORT HERE. This widget rides ui.gd's `_weighted` carrier, and
## whenever the player has the HUD curve on, that carrier is reparented into a hand-built SubViewport whose
## only job is to be barrel-warped — it renders 2D and holds no Camera3D whatsoever. The local read returns
## null there, and a compass that quietly stops updating whenever an unrelated Options row is on is precisely
## the kind of silent wrong this instrument must not be. So: take the local camera when there is one (the
## cheap, correct answer for an un-nested build) and fall back to the ROOT viewport's, which is where the
## game's 3D actually renders regardless of how deep this Control has been reparented.
##
## Minimap._camera_yaw has the same exposure and degrades differently — to the player BODY's rotation, which
## is a near-enough bearing for a floorplan but would be wrong here, because the tape reports where you are
## LOOKING and the body does not turn with the mouse in every stance.
func _active_camera() -> Camera3D:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		return cam
	var tree := get_tree()
	return tree.root.get_camera_3d() if tree != null and tree.root != null else null


## The ACTIVE camera's yaw, in the project's shared convention: a yaw of t means a forward of
## (-sin t, -cos t), so 0 faces world -Z. Identical to Minimap._camera_yaw and to the atan2 ui.gd's sway
## measurement uses — one convention, three readers. Pure given the camera; unit-tested through
## bearing_from_yaw below.
static func camera_yaw(cam: Node3D) -> float:
	var fwd: Vector3 = -cam.global_transform.basis.z
	return atan2(-fwd.x, -fwd.z)


## COMPASS BEARING (degrees clockwise from north, 0..360) for a camera yaw. World north is -Z and east is
## +X, so yaw 0 is due north and a POSITIVE yaw turns toward WEST — hence the negation. Pure — unit-tested.
static func bearing_from_yaw(yaw: float) -> float:
	return fposmod(-rad_to_deg(yaw), FULL_TURN)


## COMPASS BEARING from one point to another on the world XZ plane (both are (x, z), NOT (x, y)). Same
## north=-Z / east=+X basis as bearing_from_yaw, so a marker due north of the player reads 0 and one due
## east reads 90. Pure — unit-tested.
static func bearing_between(from_xz: Vector2, to_xz: Vector2) -> float:
	var d := to_xz - from_xz
	if d.length_squared() < 0.000001:
		return 0.0
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), FULL_TURN)


## Signed shortest angle (-180..180) from `heading` to `bearing`. The wrap is what makes the tape seamless:
## facing 350 with a marker at 010 must read +20, never -340. Pure — unit-tested.
static func delta_deg(bearing: float, heading: float) -> float:
	return wrapf(bearing - heading, -180.0, 180.0)


## Where a bearing lands on the tape, in px from the band's left edge. The band shows `span_deg` degrees
## across its full `width`, centred on the heading — so the heading itself is always dead centre, which is
## what makes the fixed index caret above it truthful. Pure — unit-tested.
static func tape_x(bearing: float, heading: float, span_deg: float, width: float) -> float:
	if span_deg <= 0.0:
		return width * 0.5
	return width * 0.5 + delta_deg(bearing, heading) / span_deg * width


## Is a bearing inside the visible window at all? Tested in DEGREES rather than against the pixel rect, so
## the answer does not change with the band's width and a caller can skip the projection entirely. Pure.
static func on_tape(bearing: float, heading: float, span_deg: float) -> bool:
	return absf(delta_deg(bearing, heading)) <= span_deg * 0.5


## Opacity for ink at `x` on a `width`-wide band: full in the middle, ramping to 0 across `fade_px` at each
## end. WHY IT EXISTS: without it a cardinal letter POPS into existence at the band edge as you turn, which
## reads as a glitch rather than as a scale sliding past. fade_px 0 disables it (hard edges). Pure — unit-tested.
static func edge_alpha(x: float, width: float, fade_px: float) -> float:
	if fade_px <= 0.0:
		return 1.0
	return clampf(minf(x, width - x) / fade_px, 0.0, 1.0)


## The bearings of every `step_deg` graduation visible in the window around `heading`, ASCENDING in tape
## order (leftmost first) and each already wrapped into 0..360. Returned rather than drawn so the tick row
## and the letter row can share one enumeration, and so the "the tape never skips a graduation" invariant is
## checkable off-tree. A non-positive step or span answers empty rather than looping forever. Pure — unit-tested.
static func graduations(heading: float, span_deg: float, step_deg: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if step_deg <= 0.0 or span_deg <= 0.0:
		return out
	var half := span_deg * 0.5
	# Walk the SIGNED offsets from the heading rather than absolute bearings: that keeps the enumeration in
	# tape order across the 360->0 seam without a special case for it.
	var first := ceilf((heading - half) / step_deg) * step_deg
	var b := first
	while b <= heading + half + 0.0001:
		out.append(fposmod(b, FULL_TURN))
		b += step_deg
	return out


## Which of the eight rose letters a bearing names (0 = N, 1 = NE, ... 7 = NW). Rounds, so a graduation a
## hair off 45 still names NE. Pure — unit-tested.
static func cardinal_index(bearing: float) -> int:
	return posmod(int(roundf(fposmod(bearing, FULL_TURN) / CARDINAL_STEP)), 8)


## Is this one of the four CARDINALS (N/E/S/W) rather than an intercardinal? They are inked in the major
## colour at the major size: N/E/S/W are the bearings a player actually navigates by, and eight equally loud
## glyphs on a 300 px band is a picket fence. Pure — unit-tested.
static func is_major(bearing: float) -> bool:
	return cardinal_index(bearing) % 2 == 0


func _draw() -> void:
	if not is_inside_tree():
		return
	var cam := _active_camera()
	if cam == null:
		return
	var hud: HudSettings = GameSettings.hud
	var skin: Resource = MenuStyle.hud
	var heading := bearing_from_yaw(camera_yaw(cam))
	var span: float = hud.compass_span_deg
	var w := size.x
	# The track first, so every graduation and pip below inks ON it. Drawn at full width even where the
	# fade has taken the ink to nothing: the band is the instrument's body, and a track that faded with its
	# contents would leave the letters floating on the world.
	var track: Color = skin.compass_track_color
	if track.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), track, true)
	_draw_graduations(heading, span, w, hud, skin)
	_draw_markers(cam, heading, span, w, skin)
	# The player's own destination LAST of the two pip channels, so where it shares a bearing with a quest
	# beacon the pin they set is the one on top. It is the only mark here that answers a question the player
	# asked rather than one the game did.
	_draw_tracked_pin(cam, heading, span, w, skin)
	_draw_index(w, skin)


## The graduation row: the eight rose LETTERS at their bearings, and a short tick at every intermediate
## degree mark. Both are walked from ONE graduations() enumeration, so a letter can never disagree with the
## tick row about where a bearing sits.
##
## A NAMED bearing draws its letter and NO tick, and an unnamed one draws its tick and no letter. That split
## is what keeps the band 20 px tall: the ticks hang from the top edge and the letters sit on a baseline
## below them, so neither row has to clear the other. A letter IS its graduation — an N with a tick through
## its cap reads as a struck-out glyph, not as a finer reading.
##
## ⭐compass_tick_step_deg MUST DIVIDE 45, or the rose letters stop landing on graduations and the tape
## silently loses them (the letters are drawn from this same walk, not from a second one).
func _draw_graduations(heading: float, span: float, w: float, hud: HudSettings, skin: Resource) -> void:
	var font := get_theme_default_font()
	var tick_w: float = skin.compass_tick_width_px
	var tick_px: float = skin.compass_tick_px
	var fade: float = skin.compass_edge_fade_px
	var baseline: float = skin.compass_label_baseline_px
	var outline: int = skin.compass_outline_size
	var outline_col: Color = skin.label_outline_color
	var rim: float = skin.compass_rim_px
	var stroke := FloorplanSection.stroke_width(tick_w, 1.0, Settings.native_scale())
	for b: float in graduations(heading, span, hud.compass_tick_step_deg):
		var x := tape_x(b, heading, span, w)
		var a := edge_alpha(x, w, fade)
		if a <= 0.0:
			continue
		var idx := cardinal_index(b)
		var named := absf(delta_deg(b, float(idx) * CARDINAL_STEP)) < 0.0001
		var major := is_major(b)
		var col: Color = skin.compass_major_color if major else skin.compass_minor_color
		col.a *= a
		if not named:
			# The rim FIRST, one px proud on every side (and past the bottom cap), then the tick over it.
			# With no track behind this widget a bare light tick is invisible on a bright backdrop; this is
			# the same black-outline dialect the rose letters get from draw_string_outline below.
			if rim > 0.0:
				var rc := outline_col
				rc.a *= a
				draw_line(Vector2(x, 0.0), Vector2(x, tick_px + rim), rc, stroke + rim * 2.0)
			draw_line(Vector2(x, 0.0), Vector2(x, tick_px), col, stroke)
			continue
		if font == null:
			continue
		var label := PlayerText.compass_cardinal(idx)
		var fs: int = hud.compass_font_size if major else hud.compass_minor_font_size
		# Centre the glyph run on the bearing: draw_string anchors at BASELINE-LEFT, so the run is measured
		# and shifted by half its width. The baseline is inset from the band's BOTTOM, which is why
		# compass_label_baseline_px and compass_size.y have to be authored together.
		var run := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := Vector2(x - run.x * 0.5, size.y - baseline)
		if outline > 0:
			var oc := outline_col
			oc.a *= a
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, oc)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A DOWN-POINTING CHEVRON with the same dark rim the ticks and letters carry, at `x`, hanging from `top`
## with half-width `r` (so it is 2r tall). Shared by the marker pips and the fixed index caret because they
## are the same mark at two seats — the pips sit on the band's bottom edge and the caret hangs from its top,
## and drawing them through one painter is what keeps their weight identical as the rim knob is retuned.
func _chevron(x: float, top: float, r: float, col: Color, rim: float, rim_col: Color) -> void:
	if rim > 0.0:
		# The rim triangle is the same shape grown outward: wider by `rim`, and `rim` longer at both ends, so
		# the apex keeps its point instead of being blunted by a uniform inset.
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - r - rim, top - rim), Vector2(x + r + rim, top - rim), Vector2(x, top + r * 2.0 + rim),
		]), rim_col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - r, top), Vector2(x + r, top), Vector2(x, top + r * 2.0),
	]), col)


## One pip per WorldMarker / active objective in the `compass` group, at ITS bearing. THE SAME CHANNEL the
## screen-edge Compass reads, and deliberately so: the two surfaces answer different questions about one set
## of markers ("where on screen is it" vs "what bearing is it on"), and a second registry would let them
## disagree. Off-tape markers are simply not drawn — a compass pins nothing to its ends, because a pip parked
## at the edge would claim a bearing it does not have.
func _draw_markers(cam: Camera3D, heading: float, span: float, w: float, skin: Resource) -> void:
	var eye := Vector2(cam.global_position.x, cam.global_position.z)
	var max_d: float = GameSettings.hud.compass_marker_max_distance
	var fade: float = skin.compass_edge_fade_px
	var rim: float = skin.compass_rim_px
	var rim_col: Color = skin.label_outline_color
	var r: float = skin.compass_marker_px
	if r <= 0.0:
		return
	for n in get_tree().get_nodes_in_group(Groups.COMPASS):
		if not (n is Node3D):
			continue
		var marker := n as Node3D
		if max_d > 0.0 and cam.global_position.distance_to(marker.global_position) > max_d:
			continue
		var b := bearing_between(eye, Vector2(marker.global_position.x, marker.global_position.z))
		if not on_tape(b, heading, span):
			continue
		var x := tape_x(b, heading, span, w)
		var a := edge_alpha(x, w, fade)
		if a <= 0.0:
			continue
		# The marker's OWN colour when it exports one (duck-typed, exactly as Compass.marker_color reads it),
		# else the skin's fallback gold — so one WorldMarker tint drives both compass surfaces.
		var col := marker_color(marker)
		col.a *= a
		# A downward chevron seated on the band's bottom edge: it points AT the tape, so it reads as
		# "this bearing" rather than as another graduation.
		var rc := rim_col
		rc.a *= a
		_chevron(x, size.y - r * 2.0, r, col, rim, rc)


## THE TRACKED PIN'S PIP: one chevron for the place the player declared they are walking to, at its bearing,
## in the pin's own palette tint. The same _chevron at the same seat as a POI pip — a destination is a bearing
## like any other, and giving it a second silhouette would make the tape two instruments. Its TINT is what
## separates it, and it is the pin's own, so the mark on this band, the glyph on the HUD corner box and the
## ring on the Map tab all agree about which pin the player is following.
##
## ⭐DELIBERATELY NOT DISTANCE-CULLED, unlike the group markers above (compass_marker_max_distance). That knob
## exists to stop distant beacons crowding the band with places the player is not going; this pip IS the place
## they are going, and hiding it exactly when it is furthest away would retire the feature at the only range
## where a compass is the thing you navigate by.
##
## Drawing nothing is the resting state — no tracked pin, or a tracked pin on ANOTHER level (tracked_pin()
## answers {} for both). The pin is not projected across levels: a bearing to a place in a different building
## interior is a line through geometry the player cannot walk, which is a confident lie rather than a hint.
func _draw_tracked_pin(cam: Camera3D, heading: float, span: float, w: float, skin: Resource) -> void:
	# Every skin read lands in an explicitly typed local first — `skin` is a bare Resource here, so each read
	# is a Variant, and handing one straight to a typed parameter is the unsafe-argument the rest of this file
	# already avoids the same way.
	var r: float = skin.compass_marker_px
	if r <= 0.0:
		return
	var rec := tracked_pin()
	if rec.is_empty():
		return
	var pos: Vector3 = rec.get("pos")
	var b := bearing_between(Vector2(cam.global_position.x, cam.global_position.z), Vector2(pos.x, pos.z))
	if not on_tape(b, heading, span):
		return
	var fade: float = skin.compass_edge_fade_px
	var x := tape_x(b, heading, span, w)
	var a := edge_alpha(x, w, fade)
	if a <= 0.0:
		return
	var col := waypoint_color(int(rec.get("tint", 0)))
	col.a *= a
	var rim: float = skin.compass_rim_px
	var rc: Color = skin.label_outline_color
	rc.a *= a
	_chevron(x, size.y - r * 2.0, r, col, rim, rc)


## THE TRACKED PIN'S RECORD — but only while it belongs to the level being played — else {}.
##
## Asked of GameState rather than cached, for the reason its own tracked_waypoint() header gives: an index is
## precisely the thing that goes stale when a pin below it is deleted, and this widget has no signal wiring to
## invalidate a cache with (it is a bare .new() in the tests and in the QA harness). The two callers here are
## the once-a-frame signature and the paint that the signature gates, so the walk runs at most twice a frame
## over a ledger bounded by WaypointBook.MAX_PER_LEVEL.
##
## Returns the ledger's LIVE Dictionary (Godot 4 Dictionaries are references) — this widget is a reader, and
## every field it takes off the record it copies out immediately. The `pos` guard is what lets the callers
## read that key without a second type check.
func tracked_pin() -> Dictionary:
	var at := GameState.tracked_waypoint()
	if at.is_empty():
		return {}
	var level := String(at.get("level", ""))
	if level.is_empty() or level != GameState.current_level_path:
		return {}
	var rec := GameState.waypoint_at(level, int(at.get("index", -1)))
	return rec if rec.get("pos") is Vector3 else {}


## A pin's tint from its stored palette INDEX. Wrapped rather than clamped, so a save written against a longer
## palette (or a hand-edited index) still resolves to a real colour instead of collapsing onto the last entry;
## an EMPTY palette — an artist clearing the array — degrades to the single fallback slot.
##
## The SAME rule Minimap.waypoint_color carries, kept here as its own instance method rather than as a call
## into that widget for exactly the reason marker_color() below is: the tape must keep working with no minimap
## in the scene at all, and a test can call it off-tree. Unit-tested.
func waypoint_color(tint: int) -> Color:
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	if palette.is_empty():
		return MenuStyle.hud.minimap_waypoint_color
	return palette[posmod(tint, palette.size())]


## The fixed index: the caret at dead centre that the tape slides under, marking the bearing the player is
## actually facing. Without it the band is a scale with no pointer — the player has to guess which pixel
## column is "now". Drawn LAST so it is never buried by a pip that happens to share the heading.
func _draw_index(w: float, skin: Resource) -> void:
	var r: float = skin.compass_index_px
	if r <= 0.0:
		return
	var c := w * 0.5
	# Seated on the band's TOP edge pointing down, over the tick row it marks. Rimmed like everything else
	# here: the shipped gold is a LIGHT ink, and on a daylit street it would otherwise wash out exactly when
	# the player most needs to know where "now" is.
	_chevron(c, 0.0, r, skin.compass_index_color, skin.compass_rim_px, skin.label_outline_color)


## A marker's own `color` when it sets one (duck-typed — WorldMarkers/quest beacons export it), else the
## skin's fallback gold. Shares Compass.marker_color's contract exactly; kept as its own instance method
## (not a call into that class) so this widget has no dependency on the edge compass being present, and so a
## test can call it off-tree. Unit-tested.
func marker_color(marker: Node3D) -> Color:
	var raw_col: Variant = marker.get(&"color")
	return raw_col if raw_col is Color else MenuStyle.hud.compass_fallback_color
