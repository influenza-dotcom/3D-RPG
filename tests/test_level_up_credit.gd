extends GutTest

## ⭐THE TRAINER DOES NOT LEND — and this suite is the pin on WHY, because the reason is not visible from the
## line it changes. `Player.credit_limit()` rates the LIVE PERMANENT stat sheet, and the LevelUp station is the
## only till in the game that SELLS entries on that sheet. Sold on credit, the loan underwrites itself:
## measured on the shipped knobs, the first point costs 1 zm and lifts the line from 200 to 300 zm, each of the
## first fifteen purchases opens more credit than it consumes, and the ladder runs to total level 51 with
## 2022 zm owed — identically for EVERY starting build, because character creation is zero-sum so all of them
## meet the same cost curve. Stat points also survive death (Character.die() takes `money` and nothing else),
## so the loop the ONE SIGNED ACCOUNT exists to make unrepresentable comes back through the stat sheet.
## Atm.withdraw already refuses the mirror-image trade ("the credit line funds PURCHASES, never cash"), and a
## chess wager is staked in cash for exactly this reason.
##
## ⭐THE FIX IS A TILL POLICY, NOT A UI CHANGE. `LevelUp.accepts_credit` (default OFF) rides into the ONE
## affordability predicate — `can_pay(cost, allow_credit)` — so the station's gate, the screen's row dim and
## the screen's quoted total cannot disagree. Hiding the rail selector alone would be COSMETIC:
## GameState.payment_method is global persisted run state, so a player can arm CREDIT at an ATM and walk back.
##
## Off-tree, no nodes: LevelUp's methods touch no transforms, and a Player's _ready wants the whole prefab.
##
## ⭐GameState is an AUTOLOAD — account / rail / record are SHARED MUTABLE STATE across the whole suite.
## Snapshot and restore (the test_payment.gd / test_level_up.gd idiom), or a balance left behind by another
## file turns a refusal test green for the wrong reason.

const PLAYER_PATH := "res://scripts/player/player.gd"
const CHARACTER_PATH := "res://scripts/player/character.gd"

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


func test_no_other_till_changed() -> void:
	# The fix is SCOPED to the station that sells the COLLATERAL — the six stats credit_limit() rates. A heal, a
	# respec and a vendor's rifle stay buyable on credit and are not entries on that sheet, so none of them can
	# bootstrap the line. ⭐NOT a claim that every other till is fine: ChipInstaller sells PERMANENT abilities
	# (`unlock_mechanic`) on the credit rail with no policy at all. That is the same shape minus the
	# self-collateralising half — a real open question, deliberately left alone here rather than widened into by
	# a knob nobody asked for.
	GameState.payment_method = "credit"
	var p = _player(0.0)
	assert_true(p.can_pay(100.0), "the credit line is alive and well for every other counter")
	var lv := _station(100)
	assert_false(p.can_pay(100.0, lv.accepts_credit), "only the trainer reads it as unaffordable")
	lv.free()
	p.free()


# --- the screen obeys the same policy --------------------------------------------------------------------------

func test_the_screen_threads_the_station_policy_into_every_price() -> void:
	# The card needs a LIVE in-tree player to exercise, which CLAUDE.md forbids in a unit test, so the wiring is
	# pinned by SOURCE TEXT — the tests/test_payment_rail_selector.gd convention for exactly this case.
	# ⭐If a rewording breaks one of these, do not delete the assert: re-point it. The invariant is that the
	# header readout, the row dim and the quoted total all carry the SAME flag the station gates on — otherwise
	# a row lies about a sale the till will refuse, which is the divergence the payment seam exists to kill.
	var src := FileAccess.get_file_as_string("res://scripts/ui/level_up_screen.gd")
	assert_ne(src, "", "level_up_screen.gd is readable")
	assert_true(src.contains("_station.get(&\"accepts_credit\")"),
		"the screen must read THIS station's policy, duck-typed off the Node-typed handle (the shop_screen idiom)")
	assert_true(src.contains("spendable(takes_credit)"),
		"the 'Your zorkmids' readout must not advertise a line the till refuses — spendable() adds credit_left() on its OWN path, separate from _split, so it has to be passed the flag too")
	assert_true(src.contains("can_pay(cost, takes_credit)"),
		"the row dim must gate on the same predicate AND the same policy as LevelUp.level_up_stat")
	assert_true(src.contains("charge_total(cost, takes_credit)"),
		"the printed all-in price must be quoted under the policy that will charge it")
	assert_true(src.contains("_rail_btn.set_available(takes_credit)"),
		"a selector that cannot change the answer must HIDE (the shop's cash-only idiom) rather than sit there lying")
	assert_true(src.contains("PlayerText.level_up_no_credit(barred, "),
		"and the terms must be SERVED in its place — the rail is global persisted state, so a player may have armed CREDIT elsewhere and deserves to be told why it vanished")


func test_the_station_gate_carries_the_policy() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/components/level_up.gd")
	assert_ne(src, "", "level_up.gd is readable")
	assert_true(src.contains("player.can_pay(cost, accepts_credit)"),
		"the refusal must sit at the can_pay GATE: level_up_stat applies the raise before it charges, so a policy checked only at charge() would hand out the stat point for free")
	assert_true(src.contains("player.charge(cost, accepts_credit)"),
		"and the debit must run under the same policy it was gated on")


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
	# This reproduces the OUTCOME of that laundry (cash in hand, account in the red) and asserts the till is shut.
	GameState.payment_method = "credit"
	GameState.account = -103.0    # what the credit-funded purchase cost, incl. the 3% non-cash fee
	var p = _player(99.0)         # ...and what selling it straight back returned, in cash
	var lv := _station(50)
	assert_true(p.can_pay(50.0, false), "the laundered cash WOULD cover the raise — gate 1 cannot see it")
	assert_false(lv.level_up_stat(p, &"gunplay"), "gate 2 shuts the till: you cannot hold laundered cash without being in the red")
	assert_eq(int(p.stats.gunplay), 10, "no point was bought")
	# ...and squaring the debt costs MORE than the laundry returned, so the loop is strictly lossy.
	assert_gt(103.0, 99.0, "the round trip lost the service charge and the vendor spread")
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


func test_the_station_gate_carries_both_halves() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/components/level_up.gd")
	assert_true(src.contains("requires_settled_account and owes_the_ledger()"),
		"gate 2 must sit at the same refusal point as gate 1 — level_up_stat applies the raise before it charges, so anything checked later hands out the stat point for free")
	assert_true(src.contains("cost > 0.0 and requires_settled_account"),
		"...and must gate the FEE, not the service: a free raise still serves a debtor")
	var scr := FileAccess.get_file_as_string("res://scripts/ui/level_up_screen.gd")
	assert_true(scr.contains("not barred and _player.can_pay(cost, takes_credit)"),
		"the row dim must apply BOTH gates in the same order the station does, or a row lights up on a sale the till refuses")
