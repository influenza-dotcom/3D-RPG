extends GutTest

## MenuStyle.wallet_color — the ONE sign-based tint seam every menu wallet readout paints through
## (the shop / level-up / chip-install headers and the implant-choice tally): gold while solvent,
## danger the moment the balance goes NEGATIVE. Implants are bought on credit, so a run can legally
## start in debt and every wallet label must show it. The HUD's top-left readout mirrors the same
## rule through HudSettings.money_debt_color (ui.gd _stamp_money_readout).

func test_wallet_color_gold_while_solvent_danger_in_debt() -> void:
	assert_eq(MenuStyle.wallet_color(12.5), MenuStyle.gold(),
		"a positive balance wears the standard wallet gold")
	assert_eq(MenuStyle.wallet_color(0.0), MenuStyle.gold(),
		"a ZERO balance is broke, not in debt — it must stay gold (danger is reserved for real debt)")
	assert_eq(MenuStyle.wallet_color(-Zorkmids.QUANTUM), MenuStyle.danger(),
		"one quantum of debt already tints danger — the wallet readouts are the debt display")


# --- The runtime "[PH]" scrub -------------------------------------------------------------------------------

func test_display_scrubs_every_placeholder_marker_and_nothing_else() -> void:
	# PlayerText.display is the by-hand scrub for surfaces that bypass atr. Leading, mid-string, repeated,
	# with-space and bare markers all go; unmarked text is identity (byte-for-byte, so a typed name survives).
	assert_eq(PlayerText.display("[PH] Pick Up"), "Pick Up", "the leading marker + its space go")
	assert_eq(PlayerText.display("Take [PH] Chrome Grin"), "Take Chrome Grin", "a mid-string marker goes")
	assert_eq(PlayerText.display("[PH] [PH] Chrome Grin acquired!"), "Chrome Grin acquired!", "repeated markers all go")
	assert_eq(PlayerText.display("[PH]Bare"), "Bare", "a marker without its space goes too")
	assert_eq(PlayerText.display("Rex the [PHONY]"), "Rex the [PHONY]", "only the exact marker is touched")
	assert_eq(PlayerText.display(""), "", "empty stays empty")
	assert_eq(PlayerText.display("Back"), "Back", "unmarked copy is identity")

func test_runtime_translation_scrubs_rendered_control_text_but_not_the_property() -> void:
	# MenuStyle._enter_tree registered PlaceholderTranslation with the TranslationServer: every auto-translated
	# Control paints its text minus the marker, while the .text PROPERTY keeps the authored string (what every
	# other test compares). atr() is the exact call Label/Button/Label3D shape through.
	var l := Label.new()
	add_child_autofree(l)
	l.text = PlayerText.PROMPT_PICK_UP
	assert_eq(l.text, PlayerText.PROMPT_PICK_UP, "the property keeps the marker — the source is never edited")
	assert_eq(l.atr(l.text), PlayerText.display(PlayerText.PROMPT_PICK_UP), "the RENDERED string has no marker")
	assert_eq(l.atr(PlayerText.BACK), PlayerText.BACK, "unmarked copy renders as itself (the scrub answers only marked strings)")
	var l3 := Label3D.new()
	add_child_autofree(l3)
	l3.text = "[PH] Rest at bonfire"
	assert_eq(l3.atr(l3.text), "Rest at bonfire", "world-space Label3D text goes through the same scrub")
	var found := false
	for loc in TranslationServer.get_loaded_locales():
		if loc == TranslationServer.get_locale():
			found = true
	assert_true(found, "the scrub is registered under the ACTIVE locale, so the server consults it")

func test_tooltip_label_is_scrubbed_by_hand() -> void:
	# The shared tooltip opts out of atr (it can carry a typed pet name), so it must scrub on assignment.
	var host := Control.new()
	add_child_autofree(host)
	MenuStyle.attach_tip(host, "[PH] A pinched muzzle.")
	MenuStyle._tip_label.text = PlayerText.display(String(host.get_meta(&"_tip_text", "")))
	assert_eq(MenuStyle._tip_label.text, "A pinched muzzle.", "the tip paints the blurb minus its marker")
# --- The scene-transition fade ------------------------------------------------------------------------

## Options -> Main Menu swaps scenes through black (MenuStyle.change_scene_faded). The cover is built ON THIS
## AUTOLOAD because it is the only node that survives change_scene_to_file — the scene being left is freed
## mid-transition and the one being entered doesn't exist yet, so neither can own the black.
## NOTE: every test here leaves the cover the way a finished transition does — hidden, alpha 0 — because a
## visible STOP-filter rect at layer 200 would eat the mouse for every test that runs after this file.
func test_scene_fade_cover_is_a_full_screen_black_rect_above_every_other_layer() -> void:
	MenuStyle._ensure_fade_cover()
	var layer := MenuStyle._fade_layer
	var rect := MenuStyle._fade_rect
	assert_not_null(layer, "the cover builds its own CanvasLayer")
	assert_not_null(rect, "the cover is a ColorRect")
	if layer == null or rect == null:
		return
	assert_eq(layer.layer, MenuStyle.SCENE_FADE_LAYER, "the cover sits on the transition layer")
	assert_true(layer.layer > OptionsMenu.layer, "a transition draws over the Options overlay (128), not under it")
	assert_true(layer.layer > 150, "...and over the debug console (150), the highest layer in the game")
	assert_eq(layer.process_mode, Node.PROCESS_MODE_ALWAYS,
		"the fade must still run with the tree paused or a FreezeFrame holding")
	assert_eq(rect.color, Color(0, 0, 0, 0), "black, and fully transparent until a transition tweens it up")
	assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_STOP,
		"the black eats clicks — a press landing on the menu being faded INTO is a ghost press")
	assert_eq(rect.anchor_right, 1.0, "the cover spans the screen (right anchor)")
	assert_eq(rect.anchor_bottom, 1.0, "the cover spans the screen (bottom anchor)")
	MenuStyle._ensure_fade_cover()
	assert_eq(MenuStyle._fade_rect, rect, "building it again reuses the one cover, never stacks a second")
	assert_eq(MenuStyle._fade_layer.get_child_count(), 1, "one rect on the transition layer")
	rect.visible = false

func test_scene_fade_tween_reaches_full_black_and_back() -> void:
	MenuStyle._ensure_fade_cover()
	await MenuStyle._tween_fade_cover(1.0, 0.05)
	assert_almost_eq(MenuStyle._fade_rect.color.a, 1.0, 0.0001, "the fade-out ends on FULL black — a swap under a half-transparent cover is the hard cut this seam removes")
	await MenuStyle._tween_fade_cover(0.0, 0.05)
	assert_almost_eq(MenuStyle._fade_rect.color.a, 0.0, 0.0001, "the fade-in ends fully clear")
	# A zero/negative time is an instant set, not a zero-length tween (the caller may dial a leg to 0).
	await MenuStyle._tween_fade_cover(1.0, 0.0)
	assert_eq(MenuStyle._fade_rect.color.a, 1.0, "time 0 sets the alpha on the spot")
	await MenuStyle._tween_fade_cover(0.0, 0.0)
	MenuStyle._fade_rect.visible = false

## Source pin (the swap itself can't be run here — it would change the scene out from under the whole GUT run):
## Main Menu must go through the faded swap, and the fade legs must stay perceptible. A sub-0.1s "fade" is the
## instant cut with extra steps.
func test_main_menu_swaps_through_black() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/options_menu.gd")
	assert_true(src.contains('MenuStyle.change_scene_faded("res://scenes/computerroom.tscn")'),
		"Options -> Main Menu changes scene through the fade, never with a bare change_scene_to_file")
	assert_true(MenuStyle.SCENE_FADE_OUT >= 0.15, "the fade to black is long enough to read as a fade")
	assert_true(MenuStyle.SCENE_FADE_IN >= 0.15, "so is the fade up on the other side")
