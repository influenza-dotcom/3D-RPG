extends GutTest

## Rank 31 (HudSettings): the HUD tuning group registered on GameSettings, replacing the hardcoded ui.gd consts
## (colors / sizes / fonts / timings for the HP bar, money readout, toasts, crosshair). A designer tunes the HUD
## from resources/tuning/HudSettings.tres — no code. Defaults must equal the former consts (byte-identical HUD).

func test_registered_on_game_settings() -> void:
	assert_not_null(GameSettings.hud, "hud is registered on GameSettings")

func test_defaults_match_the_former_consts() -> void:
	var h := HudSettings.new()
	assert_eq(h.hud_font_size, 32, "hud_font_size default preserved")
	assert_eq(h.crosshair_size, Vector2(4, 4), "crosshair_size default preserved")
	assert_eq(h.hp_seg_size, Vector2(26, 16), "hp_seg_size default preserved")
	assert_almost_eq(h.hp_seg_gap, 3.0, 0.001, "hp_seg_gap default preserved")
	assert_eq(h.hp_seg_fill, Color(0.86, 0.16, 0.16, 0.96), "hp_seg_fill default preserved")
	assert_eq(h.stamina_bar_size, Vector2(116, 6), "stamina_bar_size default preserved")
	assert_eq(h.stamina_fill, Color(0.18, 0.75, 0.95, 0.92), "stamina_fill default preserved")
	assert_almost_eq(h.rep_toast_hold, 2.5, 0.001, "rep_toast_hold default preserved")
	assert_eq(h.rep_toast_font_size, 10, "rep_toast_font_size default preserved")
	assert_eq(h.money_color, Color(1.0, 0.86, 0.3), "money_color default preserved")
	assert_eq(h.money_debt_color, Color(1.0, 0.5, 0.4),
		"money_debt_color ships as the loss red — the readout's in-debt tint matches the -N float's family")
	assert_almost_eq(h.money_delta_time, 0.8, 0.001, "money_delta_time default preserved")
	h = null


func test_aim_cluster_sway_is_a_whisper_of_the_panel() -> void:
	var h := HudSettings.new()
	assert_almost_eq(h.hud_sway_aim_scale, 0.12, 0.001,
		"the crosshair + stamina ring ride the panel spring at ~12%% — subtle by design (aim reference, not HUD mass)")
	assert_lt(h.hud_sway_aim_scale, 0.5,
		"the aim share must stay well under the panel's — large reticle motion reads as aim error")
	h = null


## The Minimap group: the top-right procedural floorplan's AUTHOR-TIME geometry (the player-facing on/off,
## rotate mode and zoom live on Settings, and every colour on MenuStyle.hud). Pins the shipped numbers AND
## the two invariants that are easy to break by nudging a knob:
##   - the box must be whole-pixel (a fractional size rasterizes into a ragged comb under the 792x444
##     canvas's ~2.4x nearest upscale — the same trap ui.gd.hp_display_seg_width documents);
##   - the bare tracker top must stay 8.0, because that is the byte-identical pre-minimap layout the
##     corner returns to when the player turns the map off.
func test_minimap_geometry_defaults() -> void:
	var h := HudSettings.new()
	assert_eq(h.minimap_size, Vector2(108, 108), "minimap box size")
	assert_eq(h.minimap_inset, Vector2(8, 8), "minimap top-right inset")
	assert_almost_eq(h.minimap_tracker_gap, 6.0, 0.001, "gap between the box and the tracker's first line")
	assert_almost_eq(h.minimap_tracker_bare_top, 8.0, 0.001,
		"map OFF returns the tracker to its historical y — the corner must not keep a hole where the map was")
	assert_true(h.minimap_rides_hud_weight, "the map is corner furniture: it carries HUD weight by default")
	assert_almost_eq(h.minimap_world_span, 40.0, 0.001, "metres across the short axis at zoom 1")
	assert_almost_eq(h.minimap_cut_height, 1.2, 0.001, "chest-height section cut")
	assert_almost_eq(h.minimap_band_height, 2.6, 0.001, "one storey: deck cache quantum + marker fade span")
	assert_almost_eq(h.minimap_band_hysteresis, 0.6, 0.001, "band-exit margin")
	assert_gt(h.minimap_band_hysteresis, 0.5,
		"MUST exceed one 0.5 m stair riser (CLAUDE.md) — at or below it, a single step next to a band boundary swaps the whole floorplan, which is the reported 'map changes wildly when I jump' bug")
	assert_lt(h.minimap_band_hysteresis, h.minimap_band_height * 0.5,
		"...but well under half a storey, or you keep drawing a floor you have genuinely left")
	assert_almost_eq(h.minimap_max_solid_span, 120.0, 0.001, "void-seal reject")
	assert_almost_eq(h.minimap_min_solid_span, 0.35, 0.001, "trim/speckle reject")
	assert_true(h.minimap_merge_solids,
		"the wall layer ships MERGED: a level is built out of overlapping boxes and a floorplan must not be drawn as one")
	assert_gt(h.minimap_merge_weld, 0.0,
		"MUST be nonzero or the merge is inert on the commonest case there is — two brushes sharing a face exactly still ink that face from both sides, because a line lying precisely ON a clip polygon's boundary survives the difference")
	assert_lt(h.minimap_merge_weld * (h.minimap_size.y / h.minimap_world_span), 1.0,
		"...but under ONE PIXEL at the shipped scale, or the hidden-line test starts eating real gaps between real solids")
	assert_almost_eq(h.minimap_redraw_pos_eps, 0.02, 0.001, "idle gate: metres")
	assert_almost_eq(h.minimap_redraw_yaw_eps, 0.004, 0.0001, "idle gate: radians")
	h = null


## The HUD clock's author-time geometry (the time-of-day readout under the map — scripts/ui/hud_clock.gd).
## Exact pins for the same reason the minimap block above carries them: these are the numbers the top-right
## stack's reflow is derived from, so a silent nudge moves the objective tracker with no error anywhere.
## The height pin is the load-bearing one — see the ⭐ note on clock_size.
func test_clock_geometry_defaults() -> void:
	var h := HudSettings.new()
	assert_eq(h.clock_size, Vector2(108, 22), "clock box: map-wide, tall enough for the rendered line box")
	assert_almost_eq(h.clock_map_gap, 3.0, 0.001, "gap between the map's bottom edge and the clock")
	assert_almost_eq(h.clock_tracker_gap, 5.0, 0.001, "gap between the clock and the tracker's first line")
	assert_almost_eq(h.clock_bare_top, 8.0, 0.001,
		"map OFF lifts the clock to the historical corner inset — no hole where the map was")
	assert_eq(h.clock_font_size, 16, "clock digit size")
	assert_gte(h.clock_size.y, float(h.clock_font_size) + 4.0,
		"the box MUST clear the font's rendered line box, not just the font size: a Label's minimum height is ascent+descent (21 px for the default face at 16), and an 18 px box was silently overridden to 21 while the tracker below still reckoned 18 — probe-verified in a real windowed boot")
	assert_lte(h.clock_size.x, h.minimap_size.x,
		"the clock must not be wider than the map it captions — both are right-anchored at the same inset")
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


## MARKER GLYPH GEOMETRY — pinned against HudSkin, not HudSettings. These moved 2026-08-19: they are the
## SIZES behind MapGlyph's shape vocabulary, and a size is paint. Leaving them here meant an artist who wanted
## a bigger station badge had to leave hud_skin.tres (where its colour is) and hunt through a tuning resource
## full of navmesh and physics numbers. The rule now: if it changes how the map LOOKS it is on the skin.
func test_minimap_glyph_geometry_defaults() -> void:
	var s := HudSkin.new()
	assert_almost_eq(s.minimap_caret_px, 5.0, 0.001, "player caret half-length (was Minimap.arrow_size)")
	assert_almost_eq(s.minimap_poi_glyph_px, 4.0, 0.001, "POI dot radius (was Minimap.marker_radius)")
	assert_almost_eq(s.minimap_npc_glyph_px, 3.6, 0.001, "body glyph radius")
	assert_almost_eq(s.minimap_station_glyph_px, 5.0, 0.001, "station glyph radius")
	assert_almost_eq(s.minimap_glyph_stroke_px, 1.0, 0.001, "hollow-glyph stroke width")
	assert_almost_eq(s.minimap_alert_ring_gap_px, 2.0, 0.001, "caret-to-first-ring gap")
	assert_almost_eq(s.minimap_alert_ring_step_px, 1.5, 0.001, "one suspicion tier's worth of growth")
	assert_almost_eq(s.minimap_floor_tick_px, 3.0, 0.001, "off-storey up/down tick length")
	assert_almost_eq(s.minimap_north_tick_px, 4.0, 0.001, "north spoke length")
	assert_almost_eq(s.minimap_wall_width, 0.0, 0.001,
		"ships at the hairline sentinel, which is transform-INDEPENDENT — strokes cannot fatten with zoom")
	assert_almost_eq(s.minimap_outline_width, 1.0, 0.001, "contrast rim px")
	assert_almost_eq(s.minimap_marker_floor_alpha, 0.3, 0.001, "off-floor markers fade rather than lie")
	assert_almost_eq(s.minimap_marker_edge_margin, 5.0, 0.001, "off-box chevron ring inset")
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
