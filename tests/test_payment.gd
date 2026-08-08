extends GutTest

## THE PAYMENT SEAM — `Character.spendable/charge_total/can_pay/charge` and the `Player` override that adds
## the bank account and the credit line. Every priced transaction in the game (merchant, healer, chip
## installer, level-up, respec) now gates on `can_pay` and debits through `charge`, so a bug here is a bug in
## every purchase — which is why this suite runs the seam off-tree with no nodes at all.
##
## THREE RAILS, ONE DEBIT ORDER: cash on hand -> banked savings -> (CREDIT only) past zero onto the line.
##   * CASH is free to spend and lost on death.
##   * SAVINGS are death-safe and cost `bank_noncash_fee_fraction` to spend.
##   * CREDIT is the same draw continued below zero, up to the live limit.
## DEBIT declines rather than crossing zero; CREDIT is the identical order allowed to keep going.
##
## ⭐GameState is an AUTOLOAD, so the account/rail/record are SHARED MUTABLE STATE across the whole suite.
## Every test here snapshots and restores them (the test_start_menu Settings idiom) — without that, a suite
## that leaves a positive balance behind would make a "broke" player in some other file suddenly solvent.

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
	GameState.payment_method = "debit"


func after_each() -> void:
	GameState.account = _prev_account
	GameState.payment_method = _prev_method
	GameState.credit_standing = _prev_standing
	GameState.profile_active = _prev_profile


## A bare off-tree Player with a known stat sheet, so credit_limit() is deterministic. NEVER add it to the
## tree: its _ready wants the whole prefab (camera rig, weapon, audio) — CLAUDE.md's rule.
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


func _fee() -> float:
	return GameSettings.economy.bank_noncash_fee_fraction


# --- The base rail: a plain wallet, and structurally nothing more ------------------------------------------

func test_a_plain_character_has_no_account_and_no_line() -> void:
	# ⭐An NPC must NEVER get a bank account or a credit line. That isolation is STRUCTURAL — the account lives
	# on the GameState autoload, not on any Character field — so it cannot be forgotten by a future subclass.
	var npc = load(CHARACTER_PATH).new()
	npc.money = 25.0
	GameState.account = 99999.0  # a fortune the NPC must not see
	assert_eq(npc.spendable(), 25.0, "a base Character can spend its wallet and nothing else")
	assert_false(npc.can_pay(50.0), "…so it cannot afford a price beyond that wallet, whatever is in the bank")
	assert_true(npc.can_pay(25.0), "…and can afford exactly its wallet")
	npc.free()


func test_the_base_rail_charges_no_fee() -> void:
	var npc = load(CHARACTER_PATH).new()
	npc.money = 100.0
	assert_eq(npc.charge_total(40.0), 40.0, "a plain wallet quotes the base price with no service charge")
	assert_true(npc.charge(40.0), "…and pays it")
	assert_eq(npc.money, 60.0, "…debiting exactly the quoted total")
	npc.free()


func test_a_free_service_always_clears() -> void:
	# The RespecStation / ChipInstaller convention: a zero-cost action serves even an empty wallet — this is
	# the fix for the whole free-service-refused-while-broke class of bug.
	var npc = load(CHARACTER_PATH).new()
	npc.money = 0.0
	assert_true(npc.can_pay(0.0), "a free service is affordable to a character with nothing")
	assert_true(npc.charge(0.0), "…and charging it succeeds")
	assert_eq(npc.money, 0.0, "…moving no money")
	assert_true(npc.charge(-5.0), "a negative price is treated as free, never as a payout")
	assert_eq(npc.money, 0.0, "…and still moves nothing — a mis-authored price can't pay the player")
	npc.free()


# --- Cash first, then savings ------------------------------------------------------------------------------

func test_cash_is_spent_first_and_costs_no_fee() -> void:
	# Cash is fee-free and earns nothing, so spending it before banked money is always correct — and it means
	# a player who never banks anything pays exactly what they always did.
	var p = _player(100.0)
	GameState.account = 500.0
	assert_eq(p.charge_total(60.0), 60.0, "a purchase covered by pocket cash quotes the bare price")
	assert_true(p.charge(60.0), "…and goes through")
	assert_eq(p.money, 40.0, "…off the wallet")
	assert_eq(GameState.account, 500.0, "…leaving the account untouched")
	p.free()


func test_the_account_covers_the_shortfall_and_pays_the_fee() -> void:
	var p = _player(20.0)
	GameState.account = 500.0
	var quoted: float = p.charge_total(50.0)
	assert_eq(quoted, snappedf(50.0 + 30.0 * _fee(), Zorkmids.QUANTUM),
		"the fee applies ONLY to the portion the Ledger covers (30 of the 50), never to the cash half")
	assert_true(p.charge(50.0), "the split purchase goes through")
	assert_eq(p.money, 0.0, "cash is drained first")
	assert_eq(GameState.account, snappedf(500.0 - (quoted - 20.0), Zorkmids.QUANTUM),
		"…and the account covers the rest INCLUDING the service charge")
	p.free()


func test_the_quote_and_the_till_can_never_disagree() -> void:
	# ⭐charge_total is what every screen PAINTS and what charge() re-derives — the pickpocket rule: one
	# formula feeds the shown number and the actual transaction.
	var p = _player(10.0)
	for cost in [1.0, 7.5, 33.33, 100.0, 999.99]:
		# RE-FUND each iteration: purchases accumulate, and a drained account would turn a later case into a
		# refusal test by accident rather than the quote-matches-till check this is.
		p.money = 10.0
		GameState.account = 5000.0
		var before: float = p.money + GameState.account
		var quoted: float = p.charge_total(float(cost))
		assert_true(p.charge(float(cost)), "cost %s is affordable here" % cost)
		var after: float = p.money + GameState.account
		assert_almost_eq(before - after, quoted, Zorkmids.QUANTUM,
			"the total actually moved equals the quoted total for cost %s" % cost)
	p.free()


# --- DEBIT declines; CREDIT continues ----------------------------------------------------------------------

func test_debit_declines_rather_than_borrowing() -> void:
	var p = _player(0.0)
	GameState.account = 40.0
	GameState.payment_method = "debit"
	assert_false(p.can_pay(50.0), "DEBIT refuses a price beyond cash + savings — it never crosses zero")
	assert_false(p.charge(50.0), "…and the charge fails")
	assert_eq(p.money, 0.0, "FAIL-CLOSED: the wallet is untouched by a refused charge")
	assert_eq(GameState.account, 40.0, "…and so is the account. No partial draw, no goods, no debt.")
	p.free()


func test_credit_continues_the_same_draw_past_zero() -> void:
	var p = _player(0.0)
	GameState.account = 40.0
	GameState.payment_method = "credit"
	assert_true(p.can_pay(50.0), "CREDIT allows the same draw to continue onto the line")
	assert_true(p.charge(50.0), "…and it goes through")
	assert_lt(GameState.account, 0.0, "…pushing the account negative — that IS the debt")
	p.free()


func test_credit_never_costs_more_than_debit_for_an_affordable_purchase() -> void:
	# Arming CREDIT must not be a penalty: it only extends how far the same draw may go. A player who leaves
	# it armed while solvent should notice no difference at all.
	var p = _player(30.0)
	GameState.account = 500.0
	GameState.payment_method = "debit"
	var debit_quote: float = p.charge_total(100.0)
	GameState.payment_method = "credit"
	assert_eq(p.charge_total(100.0), debit_quote,
		"the same purchase quotes identically on either rail while the funds are there")
	p.free()


func test_credit_is_refused_beyond_the_line() -> void:
	var p = _player(0.0)
	GameState.payment_method = "credit"
	GameState.account = -(p.credit_limit())  # already drawn to the limit
	assert_eq(p.credit_left(), 0.0, "a fully drawn line has nothing left")
	assert_false(p.can_pay(1.0), "…so even a 1-zorkmid purchase is declined")
	assert_false(p.charge(1.0), "…and moves nothing")
	p.free()


func test_over_limit_is_declined_not_negative_credit() -> void:
	# A limit can legitimately DROP below the current debt (a weaker sheet, a retune). That must read as
	# "no more credit", never as a negative allowance that could wrap into free money.
	var p = _player(0.0)
	GameState.payment_method = "credit"
	GameState.account = -(p.credit_limit() * 3.0)
	assert_eq(p.credit_left(), 0.0, "an over-limit account has ZERO left, never a negative allowance")
	assert_eq(p.credit_used(), snappedf(p.credit_limit() * 3.0, Zorkmids.QUANTUM),
		"…while credit_used still reports the true debt")
	assert_false(p.can_pay(1.0), "and nothing more can be borrowed")
	p.free()


func test_a_debtor_is_still_served_by_a_free_service() -> void:
	# The negative-wallet lesson, now in its account form: being in debt must not lock a player out of things
	# that cost nothing (the free-respec-refused-while-negative bug).
	var p = _player(0.0)
	GameState.account = -500.0
	GameState.payment_method = "debit"
	assert_true(p.can_pay(0.0), "a free service serves a debtor")
	assert_true(p.charge(0.0), "…and charging it succeeds")
	assert_eq(GameState.account, -500.0, "…without touching the debt")
	p.free()


func test_the_wallet_never_goes_negative_through_the_seam() -> void:
	# ⭐The wallet is CASH-ONLY now. A purchase that pushed `money` under zero would re-create the old
	# "debt hides in the wallet" model the signed account exists to replace.
	var p = _player(25.0)
	GameState.account = 1000.0
	GameState.payment_method = "credit"
	for cost in [10.0, 50.0, 500.0, 900.0]:
		p.charge(float(cost))
		assert_gte(p.money, 0.0, "cash stayed non-negative after a %s purchase" % cost)
	p.free()


func test_spendable_reports_the_armed_rail() -> void:
	var p = _player(30.0)
	GameState.account = 200.0
	GameState.payment_method = "debit"
	assert_eq(p.spendable(), 230.0, "DEBIT sees cash plus savings")
	GameState.payment_method = "credit"
	assert_eq(p.spendable(), snappedf(230.0 + p.credit_left(), Zorkmids.QUANTUM),
		"CREDIT additionally sees whatever is left on the line")
	p.free()


func test_savings_are_not_counted_while_in_debt_on_debit() -> void:
	# A negative account has no savings to spend — maxf(0, account) — so a debtor on DEBIT is cash-only.
	var p = _player(15.0)
	GameState.account = -300.0
	GameState.payment_method = "debit"
	assert_eq(p.spendable(), 15.0, "an overdrawn account contributes nothing to DEBIT spending power")
	assert_false(p.can_pay(20.0), "…so a debtor on DEBIT can only spend the cash in hand")
	p.free()


# --- The live credit line ----------------------------------------------------------------------------------

func test_the_credit_line_is_recomputed_from_the_live_sheet() -> void:
	# ⭐Recomputed, never persisted: there is no stale copy to migrate and nothing for a reboot to re-seed
	# (the failure that killed an earlier transient debt field). Raising a stat raises the line.
	var p = _player(0.0)
	var before: float = p.credit_limit()
	var sheet: CharacterStats = p.stats
	sheet.streetwise = 10  # a real, permanent improvement to the sheet
	assert_gte(p.credit_limit(), before,
		"improving the permanent stat sheet can only raise the line — the Ledger re-rates you continuously")
	p.free()


func test_a_timed_buff_cannot_inflate_the_line() -> void:
	# credit_limit reads RAW get_stat, so equipping a trinket at the terminal is not a credit exploit. This
	# pins the seam by source: the moment it started folding in status modifiers, the line would be gameable.
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true(src.contains("func credit_limit()"), "credit_limit lives on Player")
	assert_false(src.split("func credit_limit()")[1].split("func ")[0].contains("status_stat_modifier"),
		"credit_limit must never fold in status_stat_modifier — only the PERMANENT sheet sets your line")
