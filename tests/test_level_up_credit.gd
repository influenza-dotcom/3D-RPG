extends GutTest

## ⭐THE TRAINER DOES NOT LEND. `Player.credit_limit()` rates the live permanent stat sheet and LevelUp is the
## only till that sells entries on it, so a raise bought on credit underwrites its own loan (the full measured
## ladder is in the level_up.gd header). Two station knobs close it: `accepts_credit` (gate 1, default OFF) and
## `requires_settled_account` (gate 2, default ON — the buy-on-credit, sell-for-cash laundry defeats gate 1 alone).
## The card must agree with the till: a row that lights up must be a raise the station serves, and the price it
## quotes must be what leaves the player. Those are driven on the REAL authored card below (only _rebuild runs;
## the Player stays detached and its _ready never runs).
##
## ⭐GameState is an AUTOLOAD — account / rail / record are SHARED MUTABLE STATE across the whole suite.
## Snapshot and restore, or a balance left behind by another file turns a refusal test green for the wrong reason.

const PLAYER_PATH := "res://scripts/player/player.gd"
const CHARACTER_PATH := "res://scripts/player/character.gd"
const SCREEN_SCENE := "res://scenes/ui/level_up_screen.tscn"

var _prev_account: float
var _prev_method: String
var _prev_standing: float
var _prev_profile: bool


func before_each() -> void:
	_prev_account = GameState.account
	_prev_method = GameState.payment_method
	_prev_standing = GameState.credit_standing
	_prev_profile = GameState.profile_active
	GameState.account = 0.0
	GameState.credit_standing = 0.0
	GameState.payment_method = "debit"


func after_each() -> void:
	GameState.account = _prev_account
	GameState.payment_method = _prev_method
	GameState.credit_standing = _prev_standing
	GameState.profile_active = _prev_profile


## The deterministic sheet test_payment.gd uses: it rates 850 and earns the FULL 2100 zm line, so a refusal
## below can only be the policy — never an accidentally-empty credit line. Total level is 0 (10+10-5-5-5-5),
## so a station with cost_per_level 0 prices every raise at exactly base_cost.
func _player(cash: float) -> Variant:
	var p = load(PLAYER_PATH).new()
	p.money = cash
	var sheet := CharacterStats.new()
	sheet.gunplay = 10
	sheet.strength = 10
	sheet.endurance = -5
	sheet.agility = -5
	sheet.streetwise = -5
	sheet.larceny = -5
	p.stats = sheet
	return p


func _station(cost: int) -> LevelUp:
	var lv := LevelUp.new()
	lv.base_cost = cost
	lv.cost_per_level = 0.0
	return lv


func _fee() -> float:
	return GameSettings.economy.bank_noncash_fee_fraction


## Paint the REAL level-up card (the authored scene, chrome bound by its own _ready) for this station + player and
## read back what the player would see. Only _rebuild runs — open_level_up wants a live in-tree player — and
## _rebuild asks the detached Player nothing but the payment seam the station itself gates on.
func _paint_card(lv: LevelUp, p: Variant) -> Dictionary:
	var screen = (load(SCREEN_SCENE) as PackedScene).instantiate()
	add_child_autofree(screen)
	screen._station = lv
	screen._player = p
	screen._rebuild()
	var lit := 0
	var dimmed := 0
	var dim_matches_lock := true
	var price := NAN
	for row in screen._rows.get_children():
		var btn := row.get_child(0) as Button
		var cols := row.get_child(1).get_child(0) as Control
		if btn.disabled:
			dimmed += 1
		else:
			lit += 1
		if (cols.modulate.a < 1.0) != btn.disabled:
			dim_matches_lock = false
		price = _last_number((cols.get_child(cols.get_child_count() - 1) as Label).text)
	var card := {
		"lit": lit,
		"dimmed": dimmed,
		"dim_matches_lock": dim_matches_lock,
		"price": price,
		"wallet": _last_number((screen._money_label as Label).text),
		"rail_shown": (screen._rail_btn as Control).visible,
		"notice_shown": (screen._credit_notice as Control).visible,
		"notice": (screen._credit_notice as Label).text,
	}
	screen._station = null  # the caller frees the station + player; the card must not outlive them holding handles
	screen._player = null
	return card


## The last number painted in a label ("[PH] Your zorkmids: 103.5" -> 103.5, "103 zm" -> 103). NAN when none.
func _last_number(text: String) -> float:
	var re := RegEx.new()
	re.compile("-?\\d+(?:\\.\\d+)?")
	var hits := re.search_all(text)
	if hits.is_empty():
		return NAN
	return float(hits[hits.size() - 1].get_string())


# --- the shipping default ----------------------------------------------------------------------------------

func test_the_station_ships_refusing_credit() -> void:
	var lv := LevelUp.new()
	assert_false(lv.accepts_credit,
		"LevelUp must ship accepts_credit OFF — that IS the fix, not an opt-in. A designer re-arming it on one station is a deliberate choice; the DEFAULT must not sell permanent stat points on borrowed money")
	assert_true(lv.requires_settled_account,
		"...and requires_settled_account ON, which is the half that actually holds: refusing the credit RAIL alone is defeated by buying on credit and selling the goods straight back for cash")
	lv.free()


func test_the_only_shipped_station_inherits_the_refusal() -> void:
	# The one LevelUp in shipped content rides the medicine person, instanced from levelup.tscn with no
	# overrides — so it takes the script default. If someone later authors accepts_credit = true onto an
	# instance, that is a design statement, and this is where they will be asked to justify it.
	var scene := load("res://scenes/components/levelup.tscn") as PackedScene
	assert_not_null(scene, "levelup.tscn loads")
	var lv := scene.instantiate()
	assert_false(bool(lv.get(&"accepts_credit")), "the authored drop-in does not override the refusal")
	assert_true(bool(lv.get(&"requires_settled_account")), "...nor the solvency gate")
	lv.free()


# --- the refusal itself ------------------------------------------------------------------------------------

func test_the_credit_line_cannot_buy_a_stat_point() -> void:
	GameState.payment_method = "credit"
	var p = _player(0.0)          # not one coin in hand, and nothing banked...
	var lv := _station(100)
	assert_gt(p.credit_left(), 100.0, "precondition: the Ledger WOULD lend far more than the price")
	assert_true(p.can_pay(100.0), "precondition: on an ordinary till the armed CREDIT rail covers it")
	assert_false(p.can_pay(100.0, false), "...and the SAME predicate refuses it for a till that does not lend")
	assert_false(lv.level_up_stat(p, &"gunplay"), "so the trainer refuses the raise")
	assert_eq(int(p.stats.gunplay), 10, "the stat did NOT move")
	assert_eq(GameState.account, 0.0, "and not one zorkmid of debt was opened")
	lv.free()
	p.free()


func test_the_self_funding_ladder_is_closed() -> void:
	# ⭐THE REGRESSION THIS FILE EXISTS FOR. A fresh all-zero sheet rates 432 and opens a 200 zm line; on a
	# lending till that line bought 51 points, because each point re-rated the borrower upward. Sixty presses
	# by a player holding NOTHING must now buy nothing at all.
	GameState.payment_method = "credit"
	var p = load(PLAYER_PATH).new()
	var lv := LevelUp.new()
	lv.base_cost = 1
	lv.cost_per_level = 1.5
	assert_gt(p.credit_limit(), 0.0, "precondition: the bank rates this character a real line")
	assert_eq(lv.total_level(p), 0, "precondition: a baseline sheet is total level 0")
	for _i in 60:
		lv.level_up_stat(p, &"gunplay")
	assert_eq(lv.total_level(p), 0, "sixty presses funded only by the credit line bought NOTHING")
	assert_eq(GameState.account, 0.0, "and opened no debt — the ladder never gets its first rung")
	lv.free()
	p.free()


func test_the_refusal_is_fail_closed_when_savings_fall_short() -> void:
	GameState.payment_method = "credit"
	GameState.account = 40.0      # banked, but not enough
	var p = _player(0.0)
	var lv := _station(100)
	assert_false(lv.level_up_stat(p, &"gunplay"), "40 banked cannot reach 100 without crossing zero")
	assert_eq(GameState.account, 40.0, "and the refusal moved NOTHING — no partial draw, no goods")
	assert_eq(int(p.stats.gunplay), 10, "the stat is untouched")
	lv.free()
	p.free()


# --- what must still work ------------------------------------------------------------------------------------

func test_banked_savings_still_buy_a_stat_point() -> void:
	# The refusal is about CREDIT, not about the ledger. Savings are money already earned and death-safe either
	# way — refusing them (the Merchant.accepts_ledger shape, which is cash-only) would be the WRONG knob.
	GameState.payment_method = "credit"   # armed, and deliberately irrelevant here
	GameState.account = 500.0
	var p = _player(0.0)
	var lv := _station(100)
	assert_true(lv.level_up_stat(p, &"gunplay"), "banked savings are not credit — the trainer takes them")
	assert_eq(int(p.stats.gunplay), 11, "and the point lands")
	assert_almost_eq(GameState.account, 500.0 - 100.0 * (1.0 + _fee()), 0.01,
		"the account paid the price PLUS the non-cash service charge, exactly as at any other till")
	assert_gt(GameState.account, 0.0, "and never crossed zero")
	lv.free()
	p.free()


func test_pocket_cash_still_buys_a_stat_point() -> void:
	GameState.payment_method = "credit"
	var p = _player(200.0)
	var lv := _station(100)
	assert_true(lv.level_up_stat(p, &"gunplay"), "cash in hand always serves")
	assert_almost_eq(float(p.money), 100.0, 0.01, "and pays no service charge — cash is free BY CONSTRUCTION")
	assert_eq(GameState.account, 0.0, "the ledger was never touched")
	lv.free()
	p.free()


func test_a_free_raise_still_serves_a_debtor() -> void:
	# The zero-cost branch is load-bearing and PREDATES this fix: creation permits an all(-5) sheet, so
	# total_level goes negative and the curve FLOORS at 0. A free service must serve a wallet in the red (the
	# New Game implant purchase can legitimately start a run negative). The credit refusal must not quietly
	# become a "no training while you owe" rule — that is a different decision, and nobody asked for it.
	GameState.account = -500.0
	var p = load(PLAYER_PATH).new()
	var s := CharacterStats.new()
	s.strength = -5
	s.endurance = -5
	s.gunplay = -5
	s.agility = -5
	s.streetwise = -5
	s.larceny = -5
	p.stats = s
	var lv := LevelUp.new()
	lv.base_cost = 1
	lv.cost_per_level = 1.5
	assert_eq(lv.level_up_cost(p), 0.0, "precondition: the curve floors at 0 below baseline")
	assert_true(lv.level_up_stat(p, &"strength"), "a FREE raise still serves a character deep in debt")
	assert_eq(int(p.stats.strength), -4, "and the point landed")
	assert_eq(GameState.account, -500.0, "while the debt was neither paid nor deepened")
	lv.free()
	p.free()
	s = null


func test_a_designer_can_re_arm_the_line() -> void:
	# The knob is a real knob: ON restores the old behaviour exactly, so a loan-shark trainer is authorable.
	# This is also the NEGATIVE CONTROL for every refusal above — it proves they fail on the policy and not
	# because the test player is somehow broke.
	GameState.payment_method = "credit"
	var p = _player(0.0)
	var lv := _station(100)
	lv.accepts_credit = true
	assert_true(lv.level_up_stat(p, &"gunplay"), "a lending station serves the raise off the line")
	assert_eq(int(p.stats.gunplay), 11, "the point lands")
	assert_lt(GameState.account, 0.0, "and it opens the debt the default now refuses to open")
	lv.free()
	p.free()


# --- the seam stays backward compatible ------------------------------------------------------------------------

func test_the_one_argument_call_is_still_the_permissive_one() -> void:
	# EVERY existing till calls the seam with one argument, and RespecStation.do_respec reaches it duck-typed
	# through has_method — which vouches for the NAME, never the arity. The new parameter must therefore
	# default to the old behaviour, byte for byte.
	GameState.payment_method = "credit"
	var p = _player(10.0)
	assert_eq(p.can_pay(100.0), p.can_pay(100.0, true), "can_pay(cost) == can_pay(cost, true)")
	assert_eq(p.spendable(), p.spendable(true), "spendable() == spendable(true)")
	assert_eq(p.charge_total(100.0), p.charge_total(100.0, true), "charge_total(cost) == charge_total(cost, true)")
	assert_eq(bool(p.quote(100.0)["ok"]), bool(p.quote(100.0, true)["ok"]), "quote(cost) == quote(cost, true)")
	assert_true(p.can_pay(100.0), "and the permissive default still reaches the credit line")
	p.free()


func test_the_policy_is_inert_on_a_plain_wallet() -> void:
	# An NPC has no account and no line — that isolation is STRUCTURAL (the account lives on the autoload).
	# Character must still ACCEPT the parameter so the Player override's signature matches: Godot errors on a
	# diverging override, so carrying it on the base class is load-bearing, not decoration.
	GameState.account = 99999.0
	GameState.payment_method = "credit"
	var npc = load(CHARACTER_PATH).new()
	npc.money = 50.0
	assert_true(npc.can_pay(50.0, false), "a plain wallet has no credit to refuse — the flag changes nothing")
	assert_true(npc.can_pay(50.0, true), "...in either direction")
	assert_false(npc.can_pay(51.0, true), "and the fortune on the autoload stays invisible to it")
	assert_true(npc.charge(50.0, false), "charge takes the flag too")
	assert_almost_eq(float(npc.money), 0.0, 0.01, "and debits the plain wallet")
	npc.free()


func test_a_vendor_still_sells_on_credit_to_the_player_the_trainer_refuses() -> void:
	# The fix is SCOPED to the station that sells the COLLATERAL — the six stats credit_limit() rates. A vendor's
	# rifle is not an entry on that sheet, so it stays buyable on the line. ⭐NOT a claim that every other till is
	# fine: ChipInstaller sells PERMANENT abilities on the credit rail with no policy at all — a real open
	# question, deliberately left alone here rather than widened into by a knob nobody asked for.
	GameState.payment_method = "credit"
	var p = _player(0.0)
	var lv := _station(100)
	assert_false(lv.level_up_stat(p, &"gunplay"), "the trainer refuses a broke player's raise on the credit line")
	assert_eq(GameState.account, 0.0, "precondition: the refusal opened no debt")
	var vendor := Merchant.new()  # never add_child: its _ready is not what is under test
	var rifle := Item.new()
	rifle.value = 100.0
	var price := vendor.buy_price(rifle, p)
	assert_true(vendor.take_payment(price, p), "the SAME player, at a ledger vendor, still buys on the credit line")
	assert_lt(GameState.account, 0.0, "and that sale really was funded by borrowing")
	rifle = null
	vendor.free()
	lv.free()
	p.free()


# --- the screen obeys the same policy --------------------------------------------------------------------------

func test_the_card_dims_every_raise_a_credit_refusing_till_refuses() -> void:
	# The rail is GLOBAL persisted state: a player can arm CREDIT at an ATM and walk in here holding nothing. The
	# card must not light a row, advertise the line in its wallet readout, or offer a rail selector that cannot
	# change the answer — otherwise it lies about a sale the till will refuse.
	GameState.payment_method = "credit"
	var p = _player(0.0)
	var lv := _station(100)
	var card := _paint_card(lv, p)
	assert_eq(card.lit + card.dimmed, 6, "precondition: the card painted one row per stat")
	assert_eq(card.lit, 0, "a player whose only money is the credit line sees every raise dimmed at a till that does not lend")
	assert_true(card.dim_matches_lock, "each dimmed row is also the locked one (the fade and the click agree)")
	assert_almost_eq(float(card.wallet), 0.0, 0.01, "the 'Your zorkmids' readout does not count a credit line this till refuses")
	assert_false(card.rail_shown, "the DEBIT/CREDIT selector hides on a till where credit cannot change the answer")
	assert_false(lv.level_up_stat(p, &"gunplay"), "...and the till agrees with the dimmed row: the raise is refused")
	lv.free()
	p.free()

	# CONTROL: the same broke, credit-armed player at a station that DOES lend sees a lit card, the line in the
	# readout and the selector — so the dim above is the station's policy, not a card that is always dark.
	var p2 = _player(0.0)
	var lender := _station(100)
	lender.accepts_credit = true
	var lent := _paint_card(lender, p2)
	assert_eq(lent.lit, 6, "a lending station lights every raise the credit line covers")
	assert_gt(float(lent.wallet), 100.0, "and its readout counts the credit line")
	assert_true(lent.rail_shown, "and it offers the rail selector")
	assert_true(lender.level_up_stat(p2, &"gunplay"), "...and that lit row is a raise the till really serves")
	lender.free()
	p2.free()


func test_the_card_quotes_the_price_that_actually_leaves_the_player() -> void:
	# Savings carry the non-cash service charge; cash does not. Whatever the card prints in the cost column must be
	# exactly what the station then takes, or the row under-quotes the sale.
	GameState.account = 500.0
	var banked = _player(0.0)
	var lv := _station(100)
	var card := _paint_card(lv, banked)
	assert_false(is_nan(float(card.price)), "precondition: the cost column painted a number")
	assert_true(lv.level_up_stat(banked, &"gunplay"), "precondition: savings buy the raise")
	assert_almost_eq(500.0 - GameState.account, float(card.price), 0.01,
		"the all-in price printed on a savings-funded row is exactly what left the account (service charge included)")
	lv.free()
	banked.free()

	GameState.account = 0.0
	var holding_cash = _player(200.0)
	var lv2 := _station(100)
	var cash_card := _paint_card(lv2, holding_cash)
	assert_true(lv2.level_up_stat(holding_cash, &"gunplay"), "precondition: pocket cash buys the raise")
	assert_almost_eq(200.0 - float(holding_cash.money), float(cash_card.price), 0.01,
		"the price printed on a cash-funded row is exactly what left the wallet (no service charge on cash)")
	lv2.free()
	holding_cash.free()


func test_the_terms_match_the_gate_that_is_actually_shut() -> void:
	var owing := PlayerText.level_up_no_credit(true, false)
	var with_savings := PlayerText.level_up_no_credit(false, true)
	var without := PlayerText.level_up_no_credit(false, false)
	assert_ne(with_savings, without, "WHOLE templates selected by the facts — never a fragment append")
	assert_ne(owing, with_savings, "a debtor is told about the debt, not lectured about rails")
	assert_true(owing.to_lower().contains("owe") or owing.to_lower().contains("square"),
		"the gate-2 line must name the actual reason the counter is shut")
	assert_true(with_savings.to_lower().contains("bank"), "a banked player is told their savings still work here")
	assert_false(without.to_lower().contains("bank"), "a player with nothing banked is not advertised a purse they cannot open")
	for s in [owing, with_savings, without]:
		assert_false(s.is_empty(), "the notice is never blank — a vanished selector with no explanation reads as a bug")
		assert_false(s.to_lower().contains("trainer"), "and never guesses the station's noun: a LevelUp is a trainer, a shrine or a bonfire depending on where it was dropped, and the one in shipped content rides a Medicine Person")


# --- gate 2: the launder route ---------------------------------------------------------------------------------

func test_a_debtor_cannot_buy_a_paid_raise() -> void:
	# Gate 2. Note the player here is RICH in cash — this is not an affordability refusal, it is the till
	# declining to take money while the Ledger is owed. can_pay would happily say yes.
	GameState.account = -50.0
	var p = _player(1000.0)
	var lv := _station(100)
	assert_true(p.can_pay(100.0, false), "precondition: they can trivially afford it out of pocket")
	assert_false(lv.level_up_stat(p, &"gunplay"), "but the till is shut while the account is in the red")
	assert_eq(int(p.stats.gunplay), 10, "the stat did not move")
	assert_almost_eq(float(p.money), 1000.0, 0.01, "and nothing was charged")
	lv.free()
	p.free()


func test_settling_up_reopens_the_till() -> void:
	# The gate is a state, not a punishment: clear the balance and the counter serves you again.
	GameState.account = -50.0
	var p = _player(1000.0)
	var lv := _station(100)
	assert_false(lv.level_up_stat(p, &"gunplay"), "shut while owing")
	GameState.account = 0.0
	assert_true(lv.level_up_stat(p, &"gunplay"), "open once square")
	assert_eq(int(p.stats.gunplay), 11, "and the point lands")
	lv.free()
	p.free()


func test_the_buy_sell_launder_route_is_closed() -> void:
	# ⭐THE HOLE GATE 1 ALONE LEFT OPEN, and the reason gate 2 exists. A credit line is fungible into CASH at any
	# ledger vendor: Merchant.take_payment funds the buy on the armed rail, Merchant.sell pays out in cash
	# (`player.add_money(price)`), and sell_price is clamped to only min_vendor_spread under buy_price — so the
	# round trip returns nearly the whole line as spendable coins, which a cash-taking till would accept. Worse,
	# the shipped Medicine Person carries a Merchant AND a LevelUp on the same NPC.
	# This RUNS that laundry through a real ledger vendor at its most generous buyback, then walks the cash over.
	GameState.payment_method = "credit"
	var p = _player(0.0)
	var vendor := Merchant.new()  # never add_child: only its pricing + till are under test
	vendor.sell_mult = 10.0       # a buyback far above the sticker: only the arbitrage floor limits the payout
	var goods := Item.new()
	goods.value = 100.0
	assert_true(vendor.take_payment(vendor.buy_price(goods, p), p), "precondition: the goods are bought on the credit line")
	assert_lt(GameState.account, 0.0, "precondition: ...with borrowed money")
	p.add_money(vendor.sell_price(goods, p))  # Merchant.sell's payout: straight back, in cash
	var laundered := float(p.money)
	var lv := _station(50)
	assert_true(p.can_pay(50.0, false), "the laundered cash WOULD cover the raise — gate 1 cannot see it")
	assert_false(lv.level_up_stat(p, &"gunplay"), "gate 2 shuts the till: you cannot hold laundered cash without being in the red")
	assert_eq(int(p.stats.gunplay), 10, "no point was bought")
	assert_almost_eq(float(p.money), laundered, 0.01, "and not a coin of the laundered cash was taken")
	# ...and squaring the debt costs MORE than the laundry returned (service charge + vendor spread), so the loop is lossy.
	assert_gt(-GameState.account, laundered,
		"the round trip must lose money: if the fee and the spread ever both reach zero, gate 2 is the only thing left and settling up re-opens a free laundry")
	goods = null
	vendor.free()
	lv.free()
	p.free()


func test_gate_two_is_a_designer_knob_too() -> void:
	GameState.account = -50.0
	var p = _player(1000.0)
	var lv := _station(100)
	lv.requires_settled_account = false
	assert_true(lv.level_up_stat(p, &"gunplay"), "off, a debtor with cash is served again (and the launder re-opens)")
	lv.free()
	p.free()


func test_the_card_applies_gate_two_exactly_where_the_till_does() -> void:
	# The card must shut the SAME rows the till shuts: a debtor rich in cash sees dim rows and the terms, a debtor
	# on a FREE raise still sees it lit, and a settled player at the same station sees neither. The station is a
	# lending one throughout, so gate 2 (the debt) is the only thing that changes between the three.
	GameState.account = -50.0
	var debtor = _player(1000.0)
	var lv := _station(100)
	lv.accepts_credit = true
	var shut := _paint_card(lv, debtor)
	assert_eq(shut.lit, 0, "a debtor holding plenty of cash sees every PAID raise dimmed while the Ledger is owed")
	assert_true(shut.notice_shown, "and the card serves the terms in place of a silent dead card")
	assert_true(String(shut.notice).to_lower().contains("square") or String(shut.notice).to_lower().contains("owe"),
		"...and those terms name the debt, the actual reason the counter is shut")
	assert_false(lv.level_up_stat(debtor, &"gunplay"), "the till agrees with the dimmed row")
	debtor.free()

	var free_rider = load(PLAYER_PATH).new()
	var sheet := CharacterStats.new()
	for stat in CharacterStats.STAT_NAMES:
		sheet.set(stat, -5)
	free_rider.stats = sheet
	GameState.account = -500.0
	lv.base_cost = 1
	lv.cost_per_level = 1.5
	assert_eq(lv.level_up_cost(free_rider), 0.0, "precondition: an all(-5) sheet trains for free")
	var free_card := _paint_card(lv, free_rider)
	assert_eq(free_card.lit, 6, "a FREE raise stays lit for a debtor — gate 2 gates the fee, never the service")
	assert_true(lv.level_up_stat(free_rider, &"strength"), "and the till serves exactly that lit row")
	free_rider.free()
	sheet = null

	GameState.account = 0.0
	var settled = _player(1000.0)
	lv.base_cost = 100
	lv.cost_per_level = 0.0
	var open := _paint_card(lv, settled)
	assert_eq(open.lit, 6, "CONTROL: square with the Ledger, the same station lights every raise the cash covers")
	assert_false(open.notice_shown, "and serves no terms, because nothing is shut")
	assert_true(lv.level_up_stat(settled, &"gunplay"), "and the till serves it")
	settled.free()
	lv.free()
