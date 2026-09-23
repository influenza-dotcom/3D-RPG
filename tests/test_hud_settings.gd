extends GutTest

## HudSettings (GameSettings.hud) and the minimap half of HudSkin (MenuStyle.hud): the HUD's AUTHOR-TIME numbers,
## retuned from resources/tuning/HudSettings.tres and resources/ui/hud_skin.tres with no code. Most tests here do NOT
## pin those numbers. They load the SHIPPED resources, feed them through the production rules that consume them (ui.gd's
## HP-bar sizing statics and a live UI layer's bottom-left bar cluster, FloorplanSection's band / cut / merge / filter / redraw maths, MapGlyph's alert ring, a real
## HudClock Label's line box) and assert the outcome the player would see if a retune broke it, so a retune that keeps
## the outcome stays green. The exact pins left are ship decisions (their messages name the decision) and the money
## readout's owner-requested timings.

const HUD_TRES := "res://resources/tuning/HudSettings.tres"
const SKIN_TRES := "res://resources/ui/hud_skin.tres"
## Loaded by path for its MINIMAP_ZOOM_MIN/MAX consts, the clamp every zoom the player can pick lives inside.
const SETTINGS_SCRIPT := "res://managers/Settings.gd"
## By path, never the class_name: ui.gd builds the clock from this same path (the class_name-cache reason).
const CLOCK_SCRIPT := "res://scripts/ui/hud_clock.gd"
## The scanner implant tiers. Each tier's REACH is its own script's export default, because a runtime chip install
## builds the ability from the script and never reads the scene (see tests/test_minimap_scan.gd).
const SCANNER_SCRIPTS := [
	"res://scripts/components/abilities/bio_scanner.gd",
	"res://scripts/components/abilities/deep_scanner.gd",
]
## One brush-stair riser. CLAUDE.md: this project's brush stairs have 0.5 m risers.
const STAIR_RISER_M := 0.5
## The max HP HudSettings.hp_bar_max_width is sized for ("232 seats the default 8-segment look whole").
const DEFAULT_LOOK_HP := 8.0


func _hud() -> HudSettings:
	return load(HUD_TRES) as HudSettings

func _skin() -> HudSkin:
	return load(SKIN_TRES) as HudSkin

## How far apart two tints read: the largest RGB channel difference (alpha ignored). 0.2 is ~51/255, a step no
## player mistakes for the same colour.
func _channel_gap(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))

## Pixels per world metre the corner box draws at `zoom`, through the widget's own scale rule.
func _box_ppm(h: HudSettings, zoom: float) -> float:
	return FloorplanSection.px_per_metre(h.minimap_size, h.minimap_world_span, zoom)

## An axis-aligned rectangle cut ring in world XZ metres (the FloorplanSection ring format).
func _rect_ring(x0: float, z0: float, x1: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])

## Total inked length of a flat draw_multiline pair list: a merged pile's union perimeter, measurable on paper.
func _inked(pairs: PackedVector2Array) -> float:
	var total := 0.0
	@warning_ignore("integer_division")
	var n := pairs.size() / 2
	for i in n:
		total += pairs[i * 2].distance_to(pairs[i * 2 + 1])
	return total


func test_registered_on_game_settings() -> void:
	assert_not_null(GameSettings.hud, "hud is registered on GameSettings")


## THE MONEY READOUT (top-left): the zorkmid total wears a debt tint while the wallet is negative, and its +N gain
## and -N spend floats read in different colours.
func test_money_hud_tints_debt_apart_from_gold_and_gains_apart_from_losses() -> void:
	var h: HudSettings = _hud()
	assert_gt(_channel_gap(h.money_debt_color, h.money_color), 0.2,
		"an in-debt wallet must not read as solvent: the debt tint has to sit visibly apart from the gold total")
	assert_gt(_channel_gap(h.money_gain_color, h.money_loss_color), 0.2,
		"a +N gain and a -N spend must not float up in the same colour")
	assert_eq(h.money_debt_color, Color(1.0, 0.5, 0.4),
		"money_debt_color ships as the loss red — the readout's in-debt tint matches the -N float's family")
	assert_almost_eq(h.money_delta_time, 0.8, 0.001, "money_delta_time default preserved")
	assert_almost_eq(h.money_readout_hold, 1.5, 0.001,
		"the flashed total holds long enough to read after the +N/-N float (0.8 s) is already gone")
	assert_gt(h.money_readout_fade, 0.0, "a zero fade pops the total off instead of fading it (owner asked for a fade)")
	h = null


## THE SEGMENTED HP BAR (bottom-left), sized by ui.gd's own statics from the shipped knobs: one segment per HP until
## the width budget, then shrinking, then consolidating.
func test_the_hp_bar_fits_its_budget_in_whole_pixels_at_every_max_hp() -> void:
	var h: HudSettings = _hud()
	var bad: Array[String] = []
	for max_hp in range(1, 301):
		var count := UI.hp_display_seg_count(float(max_hp), h.hp_bar_max_width, h.hp_seg_gap, h.hp_seg_min_width)
		var w := UI.hp_display_seg_width(count, h.hp_bar_max_width, h.hp_seg_gap, h.hp_seg_size.x)
		var drawn := float(count) * w + float(count - 1) * h.hp_seg_gap
		if drawn > h.hp_bar_max_width + 0.001:
			bad.append("max_hp %d draws %.1f px (budget %.1f)" % [max_hp, drawn, h.hp_bar_max_width])
		if w != floorf(w):
			bad.append("max_hp %d draws %.2f px segments" % [max_hp, w])
	assert_true(bad.is_empty(),
		"the HP bar must stay inside hp_bar_max_width in WHOLE-pixel segments at every max HP, or it crowds the hotbar / rasterizes into a ragged comb under the ~2.4x upscale: %s" % [bad.slice(0, 6)])
	h = null

func test_the_default_eight_hp_look_draws_whole_authored_segments() -> void:
	var h: HudSettings = _hud()
	var count := UI.hp_display_seg_count(DEFAULT_LOOK_HP, h.hp_bar_max_width, h.hp_seg_gap, h.hp_seg_min_width)
	assert_eq(count, int(DEFAULT_LOOK_HP),
		"at the 8-HP look every HP is its own drawn segment: consolidation must not kick in at the default")
	assert_eq(UI.hp_display_seg_width(count, h.hp_bar_max_width, h.hp_seg_gap, h.hp_seg_size.x), h.hp_seg_size.x,
		"the budget seats the 8-HP look at the AUTHORED segment width instead of shrinking it")
	h = null

## THE BOTTOM-LEFT BAR CLUSTER, laid out by a LIVE UI layer: adding it to the tree runs _ready, which builds the
## HUD-weight carrier, the HP bar and the stamina track from the shipped knobs (the test_hud_curve.gd idiom). The
## stamina track is the LOWEST thing in that corner — the Accessibility fallback readout, always built (the ring
## toggle only swaps which of the two is visible) — so it is the one a retune or a re-layout pushes off the edge.
func test_the_bottom_left_bar_cluster_stays_on_screen() -> void:
	var h: HudSettings = _hud()
	var ui := UI.new()
	add_child_autofree(ui)
	assert_true(ui._weighted != null and ui._hp_bar != null and ui._stamina_bg != null,
		"precondition: _ready must build the HUD-weight carrier, the HP bar and the stamina track")
	if ui._weighted == null or ui._hp_bar == null or ui._stamina_bg == null:
		return
	# The HP segments are built once a player's max HP is known (_update_hp_bar); seat the default 8-HP look the
	# same way, through the same rebuild, so the segments have real rects to measure against.
	ui._rebuild_hp_segments(int(DEFAULT_LOOK_HP))
	var screen: Rect2 = ui._weighted.get_global_rect()  # full-rect carrier: the canvas the corner cluster lives on
	var track: Rect2 = ui._stamina_bg.get_global_rect()
	var seg_bottom := -INF
	for seg in ui._hp_bar.get_children():
		seg_bottom = maxf(seg_bottom, (seg as Control).get_global_rect().end.y)
	assert_true(screen.has_area() and track.has_area(), "precondition: the carrier and the track both laid out with a real size")
	assert_gt(track.get_center().y, screen.get_center().y,
		"precondition: the track is laid out in the BOTTOM half (the corner it is anchored to), not parked at the origin")
	assert_true(screen.encloses(track),
		"the stamina track under the HP bar must sit wholly on screen, or the fallback readout is cropped (track %s, screen %s)" % [track, screen])
	assert_eq(ui._hp_bar.get_child_count(), int(DEFAULT_LOOK_HP), "precondition: the rebuild seated one segment per HP")
	assert_true(track.position.y >= seg_bottom,
		"the stamina track hangs UNDER the HP segments, never across them (track top %.1f, segment bottom %.1f)" % [track.position.y, seg_bottom])
	assert_lt(h.stamina_bar_size.y, h.hp_seg_size.y,
		"the stamina track is the SLIM bar tucked under the HP segments: as tall as them, the pair reads as two health bars")
	h = null

func test_bar_fills_read_against_their_tracks() -> void:
	var h: HudSettings = _hud()
	assert_gt(h.hp_seg_fill.get_luminance(), h.hp_seg_empty.get_luminance() + 0.1,
		"live HP must read clearly brighter than the drained track, or a hurt bar looks full")
	assert_gt(h.hp_seg_low.get_luminance(), h.hp_seg_fill.get_luminance(),
		"the last-segment tint GLOWS HOTTER than live HP, or low health gives no warning")
	assert_gt(h.stamina_fill.get_luminance(), h.stamina_empty.get_luminance() + 0.1,
		"stamina fill must read clearly brighter than its drained track")
	assert_gt(_channel_gap(h.stamina_low, h.stamina_fill), 0.2,
		"nearly-exhausted stamina must change colour visibly, or the player sprints into an empty bar")
	h = null

func test_the_reticle_box_is_a_whole_pixel_square() -> void:
	var h: HudSettings = _hud()
	assert_gt(h.crosshair_size.x, 0.0, "a zero box hides the reticle entirely")
	assert_eq(h.crosshair_size.x, h.crosshair_size.y,
		"both reticle shaders disc the box by UV distance: a non-square box draws an OVAL crosshair")
	assert_eq(h.crosshair_size, h.crosshair_size.floor(),
		"a fractional reticle box rasterizes lopsided under the 792x444 canvas's ~2.4x nearest upscale")
	h = null


func test_aim_cluster_sway_is_a_whisper_of_the_panel() -> void:
	var h := HudSettings.new()
	assert_almost_eq(h.hud_sway_aim_scale, 0.0, 0.001,
		"reticle ships fully pinned (user call 2026-08-26 'remove the sway on the crosshair') — the aim cluster does NOT ride the panel spring")
	assert_lt(h.hud_sway_aim_scale, 0.5,
		"if ever raised again, the aim share must stay well under the panel's — large reticle motion reads as aim error")
	h = null


## THE MINIMAP's author-time geometry (the top-right procedural floorplan). The box's rect and its reflow are pinned
## in tests/test_minimap_hud_layout.gd + tests/test_minimap_scene.gd; what is pinned here is what each GEOMETRY knob
## is for, driven through the FloorplanSection statics minimap.gd calls with them.

## The storey hysteresis: the drawn floor must survive a single stair riser but follow a genuine change of storey.
func test_one_stair_riser_never_swaps_the_drawn_floor_but_a_new_storey_does() -> void:
	var h: HudSettings = _hud()
	var band := h.minimap_band_height
	var hyst := h.minimap_band_hysteresis
	for start in [band - 0.001, band - 0.1, band - STAIR_RISER_M * 0.5]:
		var drawn := FloorplanSection.sticky_band_key(0, false, start, band, hyst)
		assert_eq(drawn, 0, "sanity: standing at y=%.3f draws storey 0" % start)
		assert_eq(FloorplanSection.sticky_band_key(drawn, true, start + STAIR_RISER_M, band, hyst), 0,
			"one riser UP from y=%.3f crosses the storey boundary but must NOT swap the whole floorplan (the 'map changes wildly' bug)" % start)
	for start in [0.0, 0.001, 0.1]:
		assert_eq(FloorplanSection.sticky_band_key(0, true, start - STAIR_RISER_M, band, hyst), 0,
			"one riser DOWN from y=%.3f must not swap the floorplan either" % start)
	assert_eq(FloorplanSection.sticky_band_key(0, true, band * 1.5, band, hyst), 1,
		"standing half-way up the storey above, the map must show THAT storey: a margin of half a storey keeps drawing a floor you have left")
	assert_eq(FloorplanSection.sticky_band_key(0, true, -band * 0.5, band, hyst), -1,
		"...and likewise the storey below")
	h = null

func test_the_section_cut_slices_the_storey_you_stand_on_above_its_steps() -> void:
	var h: HudSettings = _hud()
	var band := h.minimap_band_height
	for floor_y in [0.0, band, -band * 2.0]:
		var cut := FloorplanSection.cut_plane(floor_y, h.minimap_cut_height)
		assert_eq(FloorplanSection.deck_key(cut, band), FloorplanSection.deck_key(floor_y, band),
			"standing on the floor at y=%s, the section cut must slice THAT storey's walls, not the storey above" % floor_y)
		assert_gt(cut - floor_y, STAIR_RISER_M,
			"the cut must pass above a stair riser, or every step and kerb inks as a wall")
	h = null

func test_the_merge_weld_closes_a_shared_brush_face_but_keeps_a_one_pixel_gap() -> void:
	var h: HudSettings = _hud()
	assert_true(h.minimap_merge_solids,
		"SHIP DECISION: the wall layer ships MERGED: a level is built out of overlapping boxes and a floorplan must not be drawn as one")
	var shared: Array[PackedVector2Array] = [_rect_ring(0, 0, 2, 2), _rect_ring(2, 0, 4, 2)]
	assert_almost_eq(_inked(FloorplanSection.silhouette(shared, PackedVector2Array(), 0.0)), 16.0, 0.001,
		"control: with no weld, two brushes sharing a face still ink that face from both sides")
	assert_lt(_inked(FloorplanSection.silhouette(shared, PackedVector2Array(), h.minimap_merge_weld)), 12.001,
		"at the shipped weld the shared face is gone and the pair draws as ONE 4x2 room (12 m of outline), not two boxes")
	var st = load(SETTINGS_SCRIPT)
	var gap_m := 1.0 / _box_ppm(h, st.MINIMAP_ZOOM_MAX)
	var apart: Array[PackedVector2Array] = [_rect_ring(0, 0, 2, 2), _rect_ring(2.0 + gap_m, 0, 4.0 + gap_m, 2)]
	assert_almost_eq(_inked(FloorplanSection.silhouette(apart, PackedVector2Array(), h.minimap_merge_weld)), 16.0, 0.001,
		"a real gap one screen pixel wide at the most magnified zoom (%.3f m) must still draw both walls: the weld may not eat real gaps between real solids" % gap_m)
	h = null

func test_the_solid_filters_drop_speckle_and_void_seals_but_keep_walls_and_buildings() -> void:
	var h: HudSettings = _hud()
	var half_px_m := 0.5 / _box_ppm(h, 1.0)
	assert_true(FloorplanSection.ring_is_noise(_rect_ring(0, 0, half_px_m, half_px_m), h.minimap_min_solid_span),
		"a solid under half a pixel on both axes at zoom 1 is speckle (trim, a pipe collar) and must be dropped")
	assert_false(FloorplanSection.ring_is_noise(_rect_ring(0, 0, 0.2, 4.0), h.minimap_min_solid_span),
		"a thin but LONG wall must survive the speckle filter")
	assert_false(FloorplanSection.ring_is_noise(_rect_ring(0, 0, 1.0, 1.0), h.minimap_min_solid_span),
		"a 1 m pillar is real geometry the player walks around and must be drawn")
	var span := h.minimap_world_span
	assert_false(FloorplanSection.ring_is_shell(_rect_ring(0, 0, span, span), h.minimap_max_solid_span),
		"a building as big as the corner box's whole zoom-1 view must still be drawn, not rejected as a void seal")
	var reach := h.map_pan_range
	assert_true(FloorplanSection.ring_is_shell(_rect_ring(-reach, -reach, reach, reach), h.minimap_max_solid_span),
		"a void-seal brush wrapping everything the Map tab can pan across must be dropped, or it frames every room")
	assert_false(FloorplanSection.ring_is_shell(_rect_ring(0, 0, reach * 2.0, 1.0), h.minimap_max_solid_span),
		"a merely LONG perimeter wall is legitimate geometry and must survive the void-seal filter")
	h = null

func test_the_idle_gate_repaints_before_the_plan_lags_a_pixel() -> void:
	var h: HudSettings = _hud()
	var st = load(SETTINGS_SCRIPT)
	var pos_eps := h.minimap_redraw_pos_eps
	var yaw_eps := h.minimap_redraw_yaw_eps
	var here := Vector2(10.0, -4.0)
	assert_false(FloorplanSection.needs_redraw(here, here + Vector2(0.0005, 0.0), 0.7, 0.7001, pos_eps, yaw_eps),
		"a standing player's sub-millimetre physics settle must cost no repaint")
	var one_px_m := 1.0 / _box_ppm(h, st.MINIMAP_ZOOM_MAX)
	assert_true(FloorplanSection.needs_redraw(here, here + Vector2(one_px_m, 0.0), 0.7, 0.7, pos_eps, yaw_eps),
		"walking one screen pixel at the most magnified zoom must repaint, or the plan visibly stutters behind the caret")
	var corner_px := h.minimap_size.length() * 0.5
	assert_true(FloorplanSection.needs_redraw(here, here, 0.7, 0.7 + 1.0 / corner_px, pos_eps, yaw_eps),
		"heading-up: a turn that swings the box's corner one pixel must repaint")
	h = null

func test_the_scanner_fade_stays_a_rim_on_every_scanner_tier() -> void:
	var h: HudSettings = _hud()
	assert_gte(h.minimap_scan_fade_m, 0.0,
		"a negative fade band would invert the ramp: 0 is the documented hard-clip off-switch, not a minimum")
	for path in SCANNER_SCRIPTS:
		var reach: float = load(path).get_property_default_value(&"scan_range")
		assert_gt(reach, 0.0, "sanity: %s authors a positive reach" % path)
		assert_lt(h.minimap_scan_fade_m, reach * 0.5,
			"the fade must stay a RIM of %s's %.0f m reach: past half of it the implant reads as a permanent fade rather than a reach" % [path.get_file(), reach])
	h = null

func test_the_minimap_ships_as_weighted_corner_furniture() -> void:
	assert_true(_hud().minimap_rides_hud_weight,
		"SHIP DECISION: the map carries HUD weight like every other corner readout (false welds it to the layer, the shimmer escape hatch)")

## The MAP TAB's two knobs — the only numbers the page-sized instance of the same widget owns. Everything else
## it draws with (cut height, band, solid-span rejects, merge, colours) is shared with the corner box.
func test_map_tab_span_and_wheel_step() -> void:
	var h := HudSettings.new()
	var s = load("res://managers/Settings.gd")
	assert_gt(h.map_world_span, h.minimap_world_span,
		"the map tab must show MORE world than the 108 px corner box, or the tab is just a magnifier")
	assert_gt(h.map_zoom_wheel_step, 0.0,
		"a zero wheel step makes the map's primary zoom affordance inert (the buttons step by the same amount)")
	assert_lt(h.map_zoom_wheel_step, s.MINIMAP_ZOOM_MAX - s.MINIMAP_ZOOM_MIN,
		"...and one notch must not cross the whole range, or the zoom has exactly two positions")
	h = null


## The HUD clock (row 2 of the top-right stack, scripts/ui/hud_clock.gd). ui.gd reflows the quest tracker off the
## AUTHORED box, but a Label silently grows to its font's rendered line box: an 18 px box once rendered 21 px tall
## while the tracker still reckoned 18 (probe-verified). So the box is measured against a real HudClock wearing the
## overrides ui.gd stamps, showing every face the clock can draw. (The name is referenced by
## tests/test_minimap_hud_layout.gd, which pins the stack's RELATIONS.)
func test_clock_geometry_defaults() -> void:
	var h: HudSettings = _hud()
	var clock_script = load(CLOCK_SCRIPT)
	var clock: Label = clock_script.new()
	clock.add_theme_font_size_override(&"font_size", h.clock_font_size)
	clock.add_theme_constant_override(&"outline_size", MenuStyle.hud.toast_outline_size)
	add_child_autofree(clock)
	var tallest := 0.0
	var widest := 0.0
	var widest_face := ""
	for use_24 in [true, false]:
		for minute in 1440:
			var face: String = clock_script.face_text(minute, use_24)
			clock.text = face
			var box := clock.get_minimum_size()
			tallest = maxf(tallest, box.y)
			if box.x > widest:
				widest = box.x
				widest_face = face
	assert_gt(tallest, 0.0, "sanity: the clock Label measured a real line box")
	assert_lte(tallest, h.clock_size.y,
		"the clock box must hold the RENDERED line box (%.0f px), or the Label overrides it and the tracker below draws into the digits" % tallest)
	assert_lte(widest, h.clock_size.x,
		"the widest face ('%s', %.0f px) must fit the box, or right-aligned digits spill left out of the map's column" % [widest_face, widest])
	assert_gt(h.clock_font_size, h.rep_toast_font_size,
		"the clock is a glanceable instrument, set bigger than the quest tracker's prose line under it")
	h = null

## The top-right stack when the player switches the MINIMAP off (Options -> Accessibility): the clock and the objective
## tracker must rise into the corner the map vacated. tests/test_minimap_hud_layout.gd drives the same statics with
## literal 8.0 inputs and, on the shipped knobs, only checks map-on sits lower than map-off, so a bare top retuned to
## 40-100 px (a hole where the map was) would pass there. This feeds the SHIPPED bare tops through ui.gd's own rules.
func test_turning_the_map_off_leaves_no_hole_in_the_top_right_corner() -> void:
	var h: HudSettings = _hud()
	var clock_top: float = UI.hud_clock_top_for(false, h.minimap_inset.y, h.minimap_size.y, h.clock_map_gap,
			h.clock_bare_top)
	assert_lte(clock_top, h.minimap_inset.y,
		"map OFF: the clock must rise into the corner slot the map vacated (top %.1f px, the map's top was %.1f px), not leave a hole where the map was" % [clock_top, h.minimap_inset.y])
	var tracker_top: float = UI.quest_tracker_top_for(false, h.minimap_inset.y, h.minimap_size.y, h.minimap_tracker_gap,
			h.minimap_tracker_bare_top)
	assert_lte(tracker_top, h.minimap_inset.y,
		"map OFF + clock OFF: the objective tracker must return to the historical corner (top %.1f px, the map's top was %.1f px), not leave a hole where the map was" % [tracker_top, h.minimap_inset.y])
	h = null


## Layout invariants for the SHARED top-right corner. The minimap and the quest tracker both live there;
## the tracker's column is right-anchored at 8 px and wraps DOWNWARD with no bound, so the map has to fit
## inside that column's width or it starts overhanging text that has nowhere else to go.
func test_minimap_shares_the_top_right_corner_with_the_quest_tracker() -> void:
	var h := HudSettings.new()
	assert_eq(h.minimap_size.x, floorf(h.minimap_size.x), "whole-pixel width (the ragged-comb rule)")
	assert_eq(h.minimap_size.y, floorf(h.minimap_size.y), "whole-pixel height")
	assert_lte(h.minimap_inset.x + h.minimap_size.x, 8.0 + h.quest_tracker_width,
		"the map stays inside the tracker's own column, so test_enemy_health_bar's x clearance still bounds this corner")
	h = null


## MARKER GLYPH GEOMETRY lives on HudSkin, not HudSettings (moved 2026-08-19: a size is paint, so it sits beside its
## colour in hud_skin.tres). The sizes are an artist's call; what must survive any restyle is that each marker channel
## still READS, driven through the MapGlyph / FloorplanSection rules minimap.gd paints with.
func test_every_marker_glyph_has_a_drawable_size() -> void:
	var s: HudSkin = _skin()
	assert_gt(s.minimap_caret_px, 0.0, "a zero caret draws no player arrow: the map loses 'you are here'")
	assert_gt(s.minimap_poi_glyph_px, 0.0, "a zero POI radius silently erases every quest / vendor beacon")
	assert_gt(MapGlyph.alert_ring_px(1, s.minimap_npc_glyph_px, s.minimap_alert_ring_gap_px, s.minimap_alert_ring_step_px), 0.0,
		"a zero body glyph erases the NPC dots AND the alert ring MapGlyph would draw around them")
	s = null

func test_every_alert_tier_rings_clear_of_the_body_glyph_in_visible_steps() -> void:
	var s: HudSkin = _skin()
	# minimap.gd strokes the ring and every hollow glyph at stroke_width(glyph_stroke_px, 1.0, native_scale). At a
	# HIGH FIDELITY native_scale that value is the ink's on-screen width in logical px (0 = the 1 px hairline).
	var ink := FloorplanSection.stroke_width(s.minimap_glyph_stroke_px, 1.0, 2.0)
	var prev := 0.0
	for tier in [1, 2, 3]:
		var ring := MapGlyph.alert_ring_px(tier, s.minimap_npc_glyph_px, s.minimap_alert_ring_gap_px,
				s.minimap_alert_ring_step_px)
		assert_gt(ring - ink * 0.5, s.minimap_npc_glyph_px + ink * 0.5,
			"tier %d's ring must leave clear air outside a hollow body glyph's stroke: touching, it reads as a fatter outline, not 'it saw you'" % tier)
		if tier > 1:
			assert_gte(ring - prev, 0.5,
				"tier %d must grow the ring by at least half a pixel, the finest step that survives the ~2.4x upscale" % tier)
		prev = ring
	s = null

func test_off_floor_markers_dim_but_stay_findable() -> void:
	var s: HudSkin = _skin()
	var band := _hud().minimap_band_height
	var here := FloorplanSection.marker_alpha(0.0, band, s.minimap_marker_floor_alpha)
	var upstairs := FloorplanSection.marker_alpha(band, band, s.minimap_marker_floor_alpha)
	assert_lt(upstairs, here, "a beacon a storey away must draw dimmer than one in your room, or the map lies about where it is")
	assert_gt(upstairs, 0.0, "...but it must not vanish: an objective on another floor still has to be findable")
	assert_gt(s.minimap_floor_tick_px, 0.0,
		"SHIP DECISION: the up/down tick ships ON: without it an off-floor marker only dims and never says above or below")
	assert_gt(s.minimap_north_tick_px, 0.0,
		"SHIP DECISION: the heading-up north spoke ships ON: 0 removes the only north reference on a map that turns under you")
	s = null

func test_walls_ship_as_a_one_pixel_line_at_every_zoom() -> void:
	var h: HudSettings = _hud()
	var s: HudSkin = _skin()
	var st = load(SETTINGS_SCRIPT)
	for zoom in [st.MINIMAP_ZOOM_MIN, 1.0, st.MINIMAP_ZOOM_MAX]:
		var ppm := _box_ppm(h, zoom)
		assert_almost_eq(FloorplanSection.stroke_width(s.minimap_wall_width, ppm, 1.0), -1.0, 0.0001,
			"SHIP DECISION: RETRO draws walls with Godot's transform-independent hairline at zoom %s, so strokes cannot fatten as the player zooms" % zoom)
		assert_almost_eq(FloorplanSection.stroke_width(s.minimap_wall_width, ppm, 2.42) * ppm, 1.0, 0.0001,
			"HIGH FIDELITY draws the same wall one LOGICAL px wide at zoom %s" % zoom)
	h = null
	s = null

## HALF OF WHAT SEPARATES THE TWO GLYPH FAMILIES is size (the other half is stroke-vs-fill). A station drawn no
## larger than a body would put a stroked triangle and a filled one at the same weight, and TRIANGLE is the one
## shape the alphabets share.
func test_a_body_glyph_is_smaller_than_a_station_glyph() -> void:
	var s := HudSkin.new()
	assert_lt(s.minimap_npc_glyph_px, s.minimap_station_glyph_px,
		"a person reads smaller than a place — with stroke-vs-fill, this is what keeps the two alphabets apart")
	s = null

## The alert ring must clear the caret it annotates at EVERY tier, or the halo overdraws the disposition shape
## underneath and the two channels fight.
func test_the_alert_ring_always_clears_the_caret() -> void:
	var s := HudSkin.new()
	assert_gt(s.minimap_alert_ring_gap_px, 0.0, "a zero gap makes the first ring a thicker outline, not a halo")
	assert_gt(s.minimap_alert_ring_step_px, 0.0, "a zero step collapses all three tiers onto one ring")
	s = null

## THE GLOW PASS ships OFF via the alpha-as-null sentinel, so the map is pixel-identical until an artist wants
## neon. Its width must beat the stroke it sits under or it would never be visible even once switched on.
func test_the_wall_glow_ships_off_but_would_be_visible() -> void:
	var s := HudSkin.new()
	assert_eq(s.minimap_wall_glow_color.a, 0.0, "alpha 0 = off; the shipped plan draws exactly one wall pass")
	assert_gt(s.minimap_wall_glow_width, s.minimap_wall_width,
		"a glow no wider than its stroke hides completely underneath it")
	s = null

## Every authored zoom step has to survive Settings.set_minimap_zoom's clamp, or the cycle key stalls: two steps
## outside the range would clamp onto the same value and pressing the key would appear to do nothing.
func test_minimap_zoom_steps_stay_inside_the_settings_clamp() -> void:
	var h := HudSettings.new()
	var s = load("res://managers/Settings.gd")
	assert_false(h.minimap_zoom_steps.is_empty(), "an empty step list disables the zoom key entirely")
	var prev := -INF
	for z in h.minimap_zoom_steps:
		assert_between(z, s.MINIMAP_ZOOM_MIN, s.MINIMAP_ZOOM_MAX,
			"zoom step %s must survive set_minimap_zoom's clamp" % z)
		assert_gt(z, prev, "the steps must strictly ascend so the cycle reads as zooming IN, not shuffling")
		prev = z
	h = null
