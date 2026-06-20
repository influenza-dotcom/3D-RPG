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
	assert_almost_eq(h.rep_toast_hold, 2.5, 0.001, "rep_toast_hold default preserved")
	assert_eq(h.rep_toast_font_size, 10, "rep_toast_font_size default preserved")
	assert_eq(h.money_color, Color(1.0, 0.86, 0.3), "money_color default preserved")
	assert_almost_eq(h.money_delta_time, 0.8, 0.001, "money_delta_time default preserved")
	h = null
