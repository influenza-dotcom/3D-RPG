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
	assert_almost_eq(h.minimap_wall_width, 0.0, 0.001,
		"ships at the hairline sentinel, which is transform-INDEPENDENT — strokes cannot fatten with zoom")
	assert_almost_eq(h.minimap_max_solid_span, 120.0, 0.001, "void-seal reject")
	assert_almost_eq(h.minimap_min_solid_span, 0.35, 0.001, "trim/speckle reject")
	assert_almost_eq(h.minimap_marker_floor_alpha, 0.3, 0.001, "off-floor markers fade rather than lie")
	assert_almost_eq(h.minimap_marker_edge_margin, 5.0, 0.001, "off-box chevron ring inset")
	assert_almost_eq(h.minimap_outline_width, 1.0, 0.001, "contrast rim px")
	assert_almost_eq(h.minimap_redraw_pos_eps, 0.02, 0.001, "idle gate: metres")
	assert_almost_eq(h.minimap_redraw_yaw_eps, 0.004, 0.0001, "idle gate: radians")
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
