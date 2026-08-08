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
