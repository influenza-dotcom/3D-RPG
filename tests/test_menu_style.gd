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
