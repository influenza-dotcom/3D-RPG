extends GutTest

## THE TOP-CENTRE HEADING TAPE (scripts/ui/hud_compass.gd) and the band it reserves.
##
## Three families of invariant, none of which survives being eyeballed once:
##  - THE BEARING BASIS. World north is -Z and east is +X, and that basis is shared with the minimap's north
##    tick (MapGlyph.north_dir) and the day/night sun arc. A sign flip here does not error — it produces a
##    compass that is confidently, silently wrong, which is the worst failure a navigation instrument has.
##  - THE BAND HANDOFF. The tape owns the top band, and everything PlayerHud builds down the middle of the
##    screen is pushed below it by UI.centre_column_top_for. Nothing at runtime can see the collision: the
##    ladder is code-positioned and the tape draws itself, so an overlap is just ink on ink.
##  - THE TRACKED-PIN CHANNEL. The tape draws a second pip for the player's OWN nav point, read off
##    GameState's ledger. Which pin that is, and whether the repaint gate can see it change, are both
##    invisible at runtime: a pip that never appears and a pip that never clears both look like a quiet band.
##
## HudCompass can be constructed here but never PAINTED (its _draw needs a viewport and a live Camera3D), so
## the maths lives in pure statics and the ledger reads in their own accessors, and both are pinned off-tree —
## the FloorplanSection / Compass.project_to_edge / UI.quest_tracker_top_for idiom. The pixel LOOK is
## playtest-verified; these are not.

const COMPASS := preload("res://scripts/ui/hud_compass.gd")
const BAR := preload("res://scripts/ui/enemy_health_bar.gd")
## The corner box, loaded BY PATH purely to cross-check ONE shared rule (the waypoint palette lookup) — the
## tape must agree with it about a pin's colour, and the two carry their own copies of that lookup on purpose.
const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"

## The 792-wide UI canvas (project.godot viewport_width 396 x stretch scale 0.5) — the same constant
## tests/test_minimap_hud_layout.gd and tests/test_enemy_health_bar.gd pin against.
const CANVAS_W := 792.0
## Its HEIGHT, which the sway budget below needs and the top-right stack never did: the lens-breath scale
## pivots on the canvas CENTRE, so how far it drags the tape depends on the canvas being 444 tall.
const CANVAS_H := 444.0
## Never loaded — the waypoint ledger keys on the PATH STRING alone.
const LEVEL := "res://tests/_fake_level_tape.tscn"
const LEVEL_B := "res://tests/_fake_level_tape_b.tscn"

var _saved_level: String = ""

## ⭐THE TRACKED-PIN TESTS BELOW MUTATE A LIVE AUTOLOAD (GameState is the running profile), so the ledger is
## cleared on the way in AND on the way out — the tests/test_waypoints.gd isolation rule. current_level_path
## is written directly rather than through set_current_level(), which has side effects. The pure-maths tests
## above neither notice nor care.
func before_each() -> void:
	_saved_level = GameState.current_level_path
	GameState.waypoints.clear()
	GameState.current_level_path = LEVEL

func after_each() -> void:
	GameState.waypoints.clear()
	GameState.current_level_path = _saved_level


# ---------------------------------------------------------------- the bearing basis

func test_yaw_zero_is_due_north() -> void:
	assert_almost_eq(COMPASS.bearing_from_yaw(0.0), 0.0, 0.0001,
			"the project's yaw 0 faces world -Z, which IS due north")

func test_positive_yaw_turns_toward_west() -> void:
	# The whole sign question in one assert: Minimap._camera_yaw's atan2(-fwd.x, -fwd.z) grows as the
	# forward swings toward -X, and -X is WEST. Getting this backwards mirrors the entire rose.
	assert_almost_eq(COMPASS.bearing_from_yaw(deg_to_rad(90.0)), 270.0, 0.0001,
			"yaw +90 deg faces -X = west = bearing 270")
	assert_almost_eq(COMPASS.bearing_from_yaw(deg_to_rad(-90.0)), 90.0, 0.0001,
			"yaw -90 deg faces +X = east = bearing 90")
	assert_almost_eq(COMPASS.bearing_from_yaw(deg_to_rad(180.0)), 180.0, 0.0001,
			"yaw 180 deg faces +Z = south")

func test_bearing_from_yaw_wraps_into_one_turn() -> void:
	assert_almost_eq(COMPASS.bearing_from_yaw(deg_to_rad(-450.0)), 90.0, 0.0001,
			"an unwrapped camera yaw still answers a bearing in 0..360")

func test_bearing_between_uses_the_same_north_is_minus_z_basis() -> void:
	var here := Vector2(10.0, 10.0)  # (x, z), NOT (x, y)
	assert_almost_eq(COMPASS.bearing_between(here, Vector2(10.0, 0.0)), 0.0, 0.0001,
			"a marker at LOWER z is north of us")
	assert_almost_eq(COMPASS.bearing_between(here, Vector2(20.0, 10.0)), 90.0, 0.0001,
			"a marker at HIGHER x is east of us")
	assert_almost_eq(COMPASS.bearing_between(here, Vector2(10.0, 20.0)), 180.0, 0.0001,
			"a marker at HIGHER z is south of us")
	assert_almost_eq(COMPASS.bearing_between(here, Vector2(0.0, 10.0)), 270.0, 0.0001,
			"a marker at LOWER x is west of us")

func test_bearing_between_coincident_points_is_not_a_nan() -> void:
	# A marker standing exactly on the player (a quest beacon on the pickup you are holding) must answer a
	# real bearing, not a NaN that poisons every downstream tape_x for the frame.
	assert_almost_eq(COMPASS.bearing_between(Vector2(5.0, 5.0), Vector2(5.0, 5.0)), 0.0, 0.0001,
			"a zero-length offset degrades to 0, never NaN")


# ---------------------------------------------------------------- the tape projection

func test_delta_crosses_the_seam_the_short_way() -> void:
	# Facing 350 with a marker at 010 is twenty degrees to the RIGHT, not 340 to the left. Without the wrap
	# the pip flies off the tape once a turn.
	assert_almost_eq(COMPASS.delta_deg(10.0, 350.0), 20.0, 0.0001, "350 -> 010 reads +20")
	assert_almost_eq(COMPASS.delta_deg(350.0, 10.0), -20.0, 0.0001, "010 -> 350 reads -20")

func test_the_heading_itself_lands_dead_centre() -> void:
	# The fixed index caret is painted at width * 0.5 and claims to mark the bearing the player faces. That
	# claim is only true if this is exact.
	assert_almost_eq(COMPASS.tape_x(137.0, 137.0, 120.0, 300.0), 150.0, 0.0001,
			"the heading projects to the centre of the band, where the index caret sits")

func test_the_span_maps_to_the_full_width() -> void:
	assert_almost_eq(COMPASS.tape_x(60.0, 0.0, 120.0, 300.0), 300.0, 0.0001,
			"half a span to the right is the band's right edge")
	assert_almost_eq(COMPASS.tape_x(300.0, 0.0, 120.0, 300.0), 0.0, 0.0001,
			"half a span to the left (bearing 300 from heading 0) is the band's left edge")

func test_tape_x_survives_a_zero_span() -> void:
	assert_almost_eq(COMPASS.tape_x(90.0, 0.0, 0.0, 300.0), 150.0, 0.0001,
			"a zero/negative span answers the centre rather than dividing by zero")

func test_on_tape_is_decided_in_degrees() -> void:
	assert_true(COMPASS.on_tape(59.0, 0.0, 120.0), "just inside half a span is on the tape")
	assert_false(COMPASS.on_tape(61.0, 0.0, 120.0), "just outside half a span is not")
	assert_true(COMPASS.on_tape(5.0, 355.0, 120.0), "the window works across the 360 -> 0 seam")


# ---------------------------------------------------------------- the edge fade

func test_edge_alpha_ramps_out_at_both_ends() -> void:
	assert_almost_eq(COMPASS.edge_alpha(0.0, 300.0, 26.0), 0.0, 0.0001, "ink at the left edge is invisible")
	assert_almost_eq(COMPASS.edge_alpha(300.0, 300.0, 26.0), 0.0, 0.0001, "ink at the right edge is invisible")
	assert_almost_eq(COMPASS.edge_alpha(150.0, 300.0, 26.0), 1.0, 0.0001, "ink at the centre is full strength")
	assert_almost_eq(COMPASS.edge_alpha(13.0, 300.0, 26.0), 0.5, 0.0001, "half a fade in is half opacity")

func test_edge_alpha_zero_fade_is_hard_edges() -> void:
	assert_almost_eq(COMPASS.edge_alpha(0.0, 300.0, 0.0), 1.0, 0.0001,
			"fade 0 disables the ramp entirely rather than dividing by zero")


# ---------------------------------------------------------------- the graduation walk

func test_graduations_cover_the_window_in_tape_order() -> void:
	# Facing north with a 120 deg span and 15 deg steps: 300, 315, ... 60. Nine marks, leftmost first, and
	# the walk must cross the seam without reordering (300 comes BEFORE 0 on the tape).
	var g := COMPASS.graduations(0.0, 120.0, 15.0)
	assert_eq(g.size(), 9, "a 120 deg window at 15 deg steps shows nine graduations")
	assert_almost_eq(g[0], 300.0, 0.0001, "the leftmost graduation is half a span behind the heading")
	assert_almost_eq(g[4], 0.0, 0.0001, "the middle graduation is the heading itself")
	assert_almost_eq(g[8], 60.0, 0.0001, "the rightmost graduation is half a span ahead")

func test_graduations_are_always_multiples_of_the_step() -> void:
	# The rose LETTERS are drawn from this same walk, so a graduation that drifts off its step takes an
	# N/E/S/W with it. Sampled across a full turn rather than at one convenient heading.
	for i in range(0, 360, 7):
		for b: float in COMPASS.graduations(float(i), 120.0, 15.0):
			assert_almost_eq(fposmod(b, 15.0), 0.0, 0.0001,
					"graduation %.2f (heading %d) is a whole multiple of the 15 deg step" % [b, i])

func test_graduations_refuse_a_nonsense_step() -> void:
	assert_eq(COMPASS.graduations(0.0, 120.0, 0.0).size(), 0, "a zero step answers empty, never loops forever")
	assert_eq(COMPASS.graduations(0.0, 0.0, 15.0).size(), 0, "a zero span answers empty")

func test_the_shipped_tick_step_divides_the_rose() -> void:
	# ⭐The invariant the widget's own header stars: if compass_tick_step_deg does not divide 45 the letters
	# stop landing on graduations and N/E/S/W silently vanish from the tape. Pinned against the LIVE knob so
	# a designer retuning it in the inspector trips this instead of shipping a compass with no north.
	var h := HudSettings.new()
	assert_almost_eq(fposmod(45.0, h.compass_tick_step_deg), 0.0, 0.0001,
			"compass_tick_step_deg (%.2f) must divide 45 deg" % h.compass_tick_step_deg)
	h = null


# ---------------------------------------------------------------- the rose

func test_cardinal_index_names_the_eight_points() -> void:
	assert_eq(COMPASS.cardinal_index(0.0), 0, "0 deg is N")
	assert_eq(COMPASS.cardinal_index(45.0), 1, "45 deg is NE")
	assert_eq(COMPASS.cardinal_index(90.0), 2, "90 deg is E")
	assert_eq(COMPASS.cardinal_index(180.0), 4, "180 deg is S")
	assert_eq(COMPASS.cardinal_index(315.0), 7, "315 deg is NW")
	assert_eq(COMPASS.cardinal_index(359.9), 0, "just short of a full turn rounds back to N, never to an 8th point")

func test_only_the_four_cardinals_are_major() -> void:
	for b: float in [0.0, 90.0, 180.0, 270.0]:
		assert_true(COMPASS.is_major(b), "%.0f deg is a cardinal" % b)
	for b: float in [45.0, 135.0, 225.0, 315.0]:
		assert_false(COMPASS.is_major(b), "%.0f deg is an intercardinal" % b)

func test_the_rose_letters_come_from_player_text() -> void:
	# The letters are COPY (French writes O for west, and NO/SO follow it), so they must resolve through the
	# PlayerText chokepoint and not from a const array in the widget.
	assert_eq(PlayerText.compass_cardinal(0), PlayerText.COMPASS_N, "index 0 is north")
	assert_eq(PlayerText.compass_cardinal(2), PlayerText.COMPASS_E, "index 2 is east")
	assert_eq(PlayerText.compass_cardinal(6), PlayerText.COMPASS_W, "index 6 is west")
	assert_eq(PlayerText.compass_cardinal(7), PlayerText.COMPASS_NW, "index 7 is north-west")

func test_an_out_of_range_rose_index_wraps_rather_than_blanking() -> void:
	assert_eq(PlayerText.compass_cardinal(8), PlayerText.COMPASS_N, "one past the rose wraps to north")
	assert_eq(PlayerText.compass_cardinal(-1), PlayerText.COMPASS_NW, "one before the rose wraps to north-west")

func test_every_rose_letter_is_distinct() -> void:
	var seen := {}
	for i in range(8):
		var letter := PlayerText.compass_cardinal(i)
		assert_false(letter.is_empty(), "rose point %d has a letter" % i)
		assert_false(seen.has(letter), "rose point %d's letter (%s) is not a duplicate" % [i, letter])
		seen[letter] = true


# ---------------------------------------------------------------- the band handoff

func test_the_centre_column_clears_the_compass_band() -> void:
	assert_almost_eq(UI.centre_column_top_for(true, 3.0, 20.0, 4.0), 27.0, 0.0001,
			"with the tape up the column starts below it: top 3 + box 20 + gap 4")

func test_the_centre_column_returns_to_zero_when_the_compass_is_off() -> void:
	# ZERO, not "about zero": PlayerHud's ladder carries hand-tuned offsets measured from the canvas top, so
	# switching the compass off must reproduce the pre-compass canvas exactly rather than approximately.
	assert_almost_eq(UI.centre_column_top_for(false, 3.0, 20.0, 4.0), 0.0, 0.0001,
			"compass OFF puts the column back at the historical canvas origin")

func test_the_centre_column_tracks_the_live_knobs() -> void:
	# Derived, not hardcoded: a designer growing the tape in the inspector must slide the ladder with it, or
	# the rose draws over the enemy health bar with no error.
	var h := HudSettings.new()
	h.compass_top = 6.0
	h.compass_size = Vector2(280.0, 26.0)
	h.compass_column_gap = 5.0
	assert_almost_eq(UI.centre_column_top_for(true, h.compass_top, h.compass_size.y, h.compass_column_gap),
			37.0, 0.0001, "a taller tape pushes the whole column down by exactly its growth")
	h = null

## THE SWAY BUDGET. The tape rides ui.gd's `_weighted` carrier and the centre-top column under it does NOT,
## so the gap between them is the only thing standing between a hard flick and the rose landing on the enemy
## health bar. Nothing at runtime can see that collision — both are code-positioned and neither errors — and
## it only appears at the simultaneous worst case of two independent effects, which is exactly the class of
## bug playtesting misses. Pinned against the LIVE sway knobs so raising either one fails HERE.
func test_the_gap_absorbs_the_carriers_whole_downward_travel() -> void:
	var h := HudSettings.new()
	var band_bottom: float = h.compass_top + h.compass_size.y
	# Two channels, summed because they can peak together: the spring's offset (capped by hud_sway_max, which
	# bounds the look-rate and velocity-lean targets as ONE promise), and the lens breath, which scales the
	# carrier about the CANVAS CENTRE — so it drags a band near the top edge downward by its distance from
	# that centre times the scale cap.
	var breath: float = (CANVAS_H * 0.5 - band_bottom) * h.hud_fov_scale_max
	var travel: float = h.hud_sway_max + breath
	var column := UI.centre_column_top_for(true, h.compass_top, h.compass_size.y, h.compass_column_gap)
	var ink := BAR.ink_rect(CANVAS_W, column + h.enemy_hp_top, h.enemy_hp_size, h.enemy_hp_outline_width)
	assert_gt(ink.position.y, band_bottom + travel,
			"the enemy bar's ink (top %.1f) clears the tape's worst-case swayed bottom edge (%.1f = resting %.1f + spring %.1f + breath %.1f) — raise compass_column_gap"
					% [ink.position.y, band_bottom + travel, band_bottom, h.hud_sway_max, breath])
	h = null

func test_the_tape_never_slides_entirely_off_the_top() -> void:
	# The UPWARD budget is deliberately much tighter than the downward one, because overrunning it only CROPS
	# the band against the screen edge while overrunning the gap COLLIDES with the enemy health bar. So this
	# does NOT demand clearance for the worst case — the tape sits hard against the top on purpose and a hard
	# flick is meant to clip a few px of tick row. What it does demand is that something is always left to
	# read: the band's own height must outlast the carrier's worst-case rise, or at the extreme the whole
	# instrument leaves the screen and the player is looking at nothing.
	var h := HudSettings.new()
	var band_bottom: float = h.compass_top + h.compass_size.y
	var rise: float = h.hud_sway_max + (CANVAS_H * 0.5 - band_bottom) * h.hud_fov_scale_max
	assert_gt(band_bottom, rise,
			"at the worst-case rise (%.1f px) the tape's bottom edge (%.1f) must still be on screen — grow compass_top or compass_size.y"
					% [rise, band_bottom])
	h = null

func test_the_enemy_health_bar_never_overlaps_the_tape() -> void:
	# The first row UNDER the column's origin is the enemy bar, and its contrast rim grows the painted band a
	# pixel on every side — so the check has to use ink_rect, never the size knob (the same rule
	# tests/test_enemy_health_bar.gd pins). This is the one collision the reflow exists to prevent.
	var h := HudSettings.new()
	var column := UI.centre_column_top_for(true, h.compass_top, h.compass_size.y, h.compass_column_gap)
	var ink := BAR.ink_rect(CANVAS_W, column + h.enemy_hp_top, h.enemy_hp_size, h.enemy_hp_outline_width)
	var band_bottom: float = h.compass_top + h.compass_size.y
	assert_gt(ink.position.y, band_bottom,
			"the enemy bar's ink (top %.1f) starts below the compass band (bottom %.1f)"
					% [ink.position.y, band_bottom])
	h = null

func test_the_stealth_badge_ladder_still_clears_the_enemy_bar_after_the_shift() -> void:
	# The ladder and the bar BOTH ride the column, so the shift is common-mode and their hand-tuned 2 px
	# clearance must be preserved exactly. Re-derived here rather than assumed: a future reflow that moved
	# only one of the two would pass every other test in this file.
	var h := HudSettings.new()
	var off := UI.centre_column_top_for(true, h.compass_top, h.compass_size.y, h.compass_column_gap)
	var ink_up := BAR.ink_rect(CANVAS_W, off + h.enemy_hp_top, h.enemy_hp_size, h.enemy_hp_outline_width)
	var ink_down := BAR.ink_rect(CANVAS_W, h.enemy_hp_top, h.enemy_hp_size, h.enemy_hp_outline_width)
	assert_almost_eq(ink_up.position.y - ink_down.position.y, off, 0.0001,
			"the bar moves by exactly the column offset — the same amount the ladder under it moves")
	h = null


# ---------------------------------------------------------------- the marker channel

func test_a_colourless_marker_falls_back_to_the_skin_tint() -> void:
	# Same contract Compass.marker_color carries, asserted separately so the tape keeps working if the
	# screen-edge component is never placed in a scene.
	var c = COMPASS.new()
	autofree(c)
	var bare := Node3D.new()  # no `color` property
	autofree(bare)
	assert_eq(c.marker_color(bare), MenuStyle.hud.compass_fallback_color,
			"a marker with no colour of its own inks in the skin's fallback gold")

func test_a_marker_with_its_own_colour_wins() -> void:
	var c = COMPASS.new()
	autofree(c)
	var marker: Node3D = load("res://scripts/components/world_marker.gd").new()
	autofree(marker)
	marker.color = Color(0.2, 0.9, 0.4)
	assert_eq(c.marker_color(marker), Color(0.2, 0.9, 0.4),
			"a WorldMarker's authored tint drives the tape pip, exactly as it drives the edge chevron")


# ---------------------------------------------------------------- the tracked-pin channel

## THE SECOND PIP SOURCE: the player's own tracked map pin, read off GameState's ledger rather than off any
## node. Everything about it that can be wrong silently is here — WHICH pin it answers, and whether the
## repaint gate can see it change — because the pip itself is drawn by a `_draw`, and a CanvasItem's _draw
## never runs headless (this file's own opening argument, and tests/test_waypoint_map.gd's).
##
## ⭐Every read off the bare `.new()` is EXPLICITLY typed, never `:=`: the widget is held in an untyped var, so
## each call is a Variant and GDScript refuses to infer from one — a parse error takes the whole file down.

## Two copies of one rule (Minimap.waypoint_color and HudCompass.waypoint_color) exist so neither widget
## depends on the other being in the scene. That is exactly the shape that drifts, so it is pinned: a pin the
## player placed must be the same colour on the corner box and on the tape, or they read as two pins.
func test_a_pin_inks_the_same_on_the_tape_as_on_the_minimap() -> void:
	var c = COMPASS.new()
	autofree(c)
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	assert_gt(palette.size(), 0, "the shipped skin authors a palette")
	for tint in range(palette.size()):
		assert_eq(c.waypoint_color(tint), mm.waypoint_color(tint),
				"tint %d inks the same on the tape as on the corner box" % tint)


## A save written against a longer palette — or a hand-edited index — must still resolve to a REAL colour.
## Wrapped rather than clamped, so out-of-range pins do not all collapse onto the last entry.
func test_the_pip_tint_wraps_an_out_of_range_index() -> void:
	var c = COMPASS.new()
	autofree(c)
	var palette: PackedColorArray = MenuStyle.hud.minimap_waypoint_palette
	var n: int = palette.size()
	assert_eq(c.waypoint_color(n), palette[0], "one past the end wraps to the start")
	assert_eq(c.waypoint_color(-1), palette[n - 1], "...and a negative index wraps the other way")


func test_the_tape_asks_for_the_tracked_pin_and_nothing_else() -> void:
	var c = COMPASS.new()
	autofree(c)
	var empty: Dictionary = c.tracked_pin()
	assert_eq(empty, {}, "an empty ledger draws no pip — {} is the resting state, never a null")
	GameState.add_waypoint(LEVEL, Vector3(1.0, 0.0, -9.0), "roof", "", 0, 2)
	var untracked: Dictionary = c.tracked_pin()
	assert_eq(untracked, {}, "a pin nobody tracked is not a nav point: the tape draws ONE pip, not every pin")
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	var rec: Dictionary = c.tracked_pin()
	assert_eq(rec.get("pos"), Vector3(1.0, 0.0, -9.0), "the tracked pin's own point is where the pip is drawn")
	assert_eq(rec.get("tint"), 2, "...and its own palette index is what the pip is drawn in")


## A pin on ANOTHER level is still the profile's tracked pin (the ledger keeps it), but its bearing here would
## be a line through geometry the player cannot walk — so the tape must draw nothing rather than a confident
## lie. The level filter lives in tracked_pin(), which is why it is asserted rather than assumed.
func test_a_tracked_pin_on_another_level_draws_nothing() -> void:
	var c = COMPASS.new()
	autofree(c)
	GameState.add_waypoint(LEVEL_B, Vector3(4.0, 0.0, 0.0), "elsewhere", "", 0, 0)
	GameState.set_tracked_waypoint(LEVEL_B, 0, true)
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL_B, "index": 0},
			"the profile still knows where the player was heading")
	var here: Dictionary = c.tracked_pin()
	assert_eq(here, {}, "...but this level's tape has no bearing to offer for it")


## THE GATE, which is the half that fails silently. The tape only repaints when its signature moves, so a
## ledger change the signature cannot see is a pip that never appears (and, worse, one that never CLEARS) for
## a player standing still — nothing else in _process would ever ask for the redraw.
##
## Both nodes go IN-TREE: _pip_signature walks the scene tree for the marker group, and a Camera3D's
## global_position off-tree raises a tracked engine error, which GUT counts as a failure on its own.
func test_the_waypoint_ledger_is_part_of_the_repaint_signature() -> void:
	var c = COMPASS.new()
	add_child_autofree(c)
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.current = false  # a stage prop carrying an eye position, never the view this suite renders through
	cam.global_position = Vector3.ZERO
	GameState.add_waypoint(LEVEL, Vector3(0.0, 0.0, -10.0), "north", "", 0, 0)
	var before: int = c._pip_signature(cam)
	assert_eq(c._pip_signature(cam), before,
			"a signature that moves on its own would repaint the tape every frame — the gate must be stable")
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	var tracked: int = c._pip_signature(cam)
	assert_ne(tracked, before,
			"TRACKING a pin must move the signature, or the pip never appears for a player standing still")
	GameState.set_tracked_waypoint(LEVEL, 0, false)
	assert_ne(c._pip_signature(cam), tracked,
			"UNTRACKING it must move the signature too — a pip that cannot clear is the worse half of the bug")


## The other half of the same gate: walking past a pin changes its bearing without touching the ledger and
## without turning the camera, so the pip has to slide. Quantised to whole degrees, exactly as the group
## markers are, which is what keeps a standing player from repainting on float noise.
func test_the_pips_bearing_moves_the_signature_when_the_player_walks() -> void:
	var c = COMPASS.new()
	add_child_autofree(c)
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.current = false
	cam.global_position = Vector3.ZERO
	GameState.add_waypoint(LEVEL, Vector3(0.0, 0.0, -10.0), "north", "", 0, 0)
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	var north: int = c._pip_signature(cam)
	cam.global_position = Vector3(10.0, 0.0, 0.0)  # the pin is now north-WEST of us; nothing in the ledger moved
	assert_ne(c._pip_signature(cam), north,
			"the pin's bearing is folded in, so walking sideways past it re-inks the pip at its new bearing")
