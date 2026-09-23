extends GutTest

## The BANKING curves — every pure static the Ledger's economy is built on, exercised off-tree with no nodes
## (the long_range_bonus_for mold): `EconomySettings.bank_interest_for`, `credit_line_for`,
## `credit_limit_for_sheet`, and the STANDING term folded into `credit_rating_for`.
##
## The account is ONE SIGNED number — positive is savings, negative is debt — so interest is one branch that
## can never run twice or drift between two ledgers. That single-field design is what these tests pin.
##
## ⭐A bare `EconomySettings.new()` ships an EMPTY `credit_underwriting` array (a flat market where every build
## rates the baseline), so anything about RATINGS uses the live resource via _live_eco(). `.new()` is correct
## only for pinning script-default knobs.

const StatBudgetScript := preload("res://scripts/ui/stat_budget.gd")
const CREDIT_FLOOR: int = StatBudgetScript.STAT_MIN  ## the allocator's bounds — the same ones the cart and Player forward
const CREDIT_CEIL: int = StatBudgetScript.STAT_MAX
const IMPLANT_CHOICE_PATH := "res://scripts/ui/implant_choice.gd"


func _live_eco() -> EconomySettings:
	return GameSettings.economy


## A full six-key creation sheet — what StatBudget.to_dict always produces. NEVER pass {} to the rater: an
## empty dict means "no application on file" and fails OPEN to the score ceiling.
func _sheet(values: Dictionary) -> Dictionary:
	var out := {}
	for stat in CharacterStats.STAT_NAMES:
		out[stat] = int(values.get(stat, 0))
	return out


# --- Interest: one signed branch ---------------------------------------------------------------------------

func test_interest_is_one_signed_branch() -> void:
	# Savings and debt are the SAME field with opposite signs, so one formula serves both and they can never
	# both run in a period, drift to different periods, or need reconciling.
	assert_eq(EconomySettings.bank_interest_for(1000.0, 0.02, 0.005, 0.05), 5.0,
		"a positive balance earns the SAVINGS rate (1000 x 0.005)")
	assert_eq(EconomySettings.bank_interest_for(-1000.0, 0.02, 0.005, 0.05), -20.0,
		"a negative balance is charged the DEBT rate (1000 x 0.02) and the delta stays negative")
	assert_eq(EconomySettings.bank_interest_for(0.0, 0.02, 0.005, 0.05), 0.0,
		"an empty account neither earns nor owes")


func test_debt_compounds_faster_than_savings_grow() -> void:
	# ⭐THE COUNTERWEIGHT. If debt did not outrun savings, "borrow the maximum and sit on it" would be free
	# money; the asymmetry is what makes the credit line a lever with a cost rather than a strictly better
	# wallet. Pinned as a RELATIONSHIP so a designer can retune both rates without breaking the suite.
	var eco := _live_eco()
	assert_gt(eco.bank_debt_interest_rate, eco.bank_savings_interest_rate,
		"debt must compound strictly faster than savings grow, or borrowing-and-hoarding is a free lunch")
	var owed := absf(EconomySettings.bank_interest_for(-1000.0, eco.bank_debt_interest_rate,
			eco.bank_savings_interest_rate, 0.0))
	var earned := EconomySettings.bank_interest_for(1000.0, eco.bank_debt_interest_rate,
			eco.bank_savings_interest_rate, 0.0)
	assert_gt(owed, earned, "…and the same balance costs more as debt than it earns as savings")


func test_interest_suppresses_sub_coin_dust() -> void:
	# A 3-zorkmid balance must not dribble out sub-coin postings (or spam a toast every dawn for nothing).
	assert_eq(EconomySettings.bank_interest_for(-2.0, 0.02, 0.005, 0.05), 0.0,
		"a posting under min_posting is suppressed entirely rather than rounded to a stray coin")
	assert_ne(EconomySettings.bank_interest_for(-2.0, 0.02, 0.005, 0.0), 0.0,
		"…and a zero min_posting turns the suppression off (the designer's switch)")


func test_interest_rates_at_zero_are_the_off_switch() -> void:
	assert_eq(EconomySettings.bank_interest_for(-5000.0, 0.0, 0.0, 0.0), 0.0,
		"both rates at 0 = the feature is OFF; even a huge debt never grows (the rent_amount convention)")
	assert_eq(EconomySettings.bank_interest_for(5000.0, 0.0, 0.0, 0.0), 0.0,
		"…and savings never grow either")


func test_negative_interest_knobs_cannot_pay_a_debtor() -> void:
	# Every rate reads through maxf, so a mis-authored negative can only ever mean "off" — never a debt that
	# pays you to hold it (the mirror of the level-up negative-cost bug).
	assert_eq(EconomySettings.bank_interest_for(-1000.0, -0.5, 0.005, 0.0), 0.0,
		"a NEGATIVE debt rate is floored to 0 — carrying a balance can never CREDIT the player")
	assert_eq(EconomySettings.bank_interest_for(1000.0, 0.02, -0.5, 0.0), 0.0,
		"a NEGATIVE savings rate is floored to 0 — deposits can never silently drain")


func test_shipped_banking_keeps_its_counterweights() -> void:
	# The SHIPPED economy (the live resource), pinned as the design rules the numbers exist to serve rather than
	# the numbers themselves, so a retune that keeps the rules passes and one that breaks them fails.
	var eco := _live_eco()
	assert_gt(eco.bank_noncash_fee_fraction, 0.0,
		"SHIP DECISION: the non-cash fee ships ON — at 0 the account strictly dominates pocket cash (safe, spendable, interest-bearing) and carrying cash stops being a choice")
	assert_lt(eco.bank_noncash_fee_fraction, 1.0,
		"…and stays a fraction: a fee of 100%+ would bill more in service charge than the purchase itself")
	assert_gt(eco.bank_savings_interest_rate, 0.0,
		"SHIP DECISION: savings interest ships ON (0 is the documented off-switch)")
	assert_lt(eco.bank_debt_interest_rate, 1.0,
		"a per-IN-GAME-DAY rate of 1.0+ would double a debt every dawn — the per-real-day misreading the knob's UNIT note warns about")
	# Dust suppression must only swallow DUST: a balance the size of one credit quote step has to accrue on both sides.
	var step := eco.credit_limit_step
	assert_lt(EconomySettings.bank_interest_for(-step, eco.bank_debt_interest_rate, eco.bank_savings_interest_rate,
			eco.bank_interest_min_posting), 0.0,
		"a %s-zorkmid debt must accrue interest at dawn — min_posting may not silence a real balance" % step)
	assert_gt(EconomySettings.bank_interest_for(step, eco.bank_debt_interest_rate, eco.bank_savings_interest_rate,
			eco.bank_interest_min_posting), 0.0,
		"…and %s zorkmids of savings must earn something" % step)
	assert_lte(eco.bank_min_transaction, Zorkmids.QUANTUM,
		"SHIP DECISION: terminals process any amount out of the box — even the smallest coin can be deposited or withdrawn")


# --- The live credit line ----------------------------------------------------------------------------------

func test_credit_line_is_identity_while_growth_is_off() -> void:
	# ⭐The shipped default (per_level 0) must not move a single zorkmid — the growth term is an opt-in knob,
	# not a behaviour change smuggled in with the ATM.
	assert_eq(EconomySettings.credit_line_for(2050.0, 40, 0.0, 6000.0, 50.0), 2050.0,
		"with growth off, the line IS the rated limit at any total level")
	assert_eq(EconomySettings.credit_line_for(0.0, 40, 0.0, 6000.0, 50.0), 0.0,
		"…including a declined applicant, who stays declined however high their level")


func test_credit_line_grows_with_total_level_when_enabled() -> void:
	assert_eq(EconomySettings.credit_line_for(2050.0, 40, 25.0, 6000.0, 50.0), 3050.0,
		"with growth on, each point of total level adds credit_limit_per_level (2050 + 40x25)")
	assert_eq(EconomySettings.credit_line_for(2050.0, 400, 25.0, 6000.0, 50.0), 6000.0,
		"…clamped at the lifetime ceiling, so a long run can't mint an unbounded line")


func test_credit_line_never_shrinks_below_the_rated_limit() -> void:
	# ⭐maxi(0, total_level) matters: a zero-sum creation build sums to 0 and a DUMPED build sums NEGATIVE.
	# A weak build has already been penalised once by the EXPOSURE line; the line must not be docked twice.
	assert_eq(EconomySettings.credit_line_for(2050.0, -30, 25.0, 6000.0, 50.0), 2050.0,
		"a net-negative sheet keeps its full rated limit — the growth term floors at zero, never subtracts")


func test_live_credit_line_quotes_exactly_the_new_game_cart() -> void:
	# New Game's implant cart (ImplantChoice._compute_credit) and the live in-run line (Player.credit_limit ->
	# credit_limit_for_sheet with the sheet's total level) MUST quote the same number for the same fresh sheet, or
	# the player is told two different things about the same file. Driven through the REAL cart code, not a
	# re-typed copy of its chain. The builds carry a POSITIVE total level on purpose: the per-level growth term
	# ships OFF, and that ship decision is exactly what keeps the two quotes identical.
	var eco := _live_eco()
	var builds := [
		_sheet({&"gunplay": 10, &"strength": 10, &"endurance": 5}),
		_sheet({&"gunplay": 10, &"strength": 10, &"endurance": -5, &"agility": -5, &"streetwise": -5, &"larceny": -5}),
		_sheet({&"gunplay": 5, &"endurance": -5}),
		_sheet({&"streetwise": 8, &"larceny": 7, &"agility": 6, &"gunplay": 2}),
	]
	var cart: Control = load(IMPLANT_CHOICE_PATH).new()  # off-tree: _ready never runs, only the rating seam is used
	for build in builds:
		var total := 0
		for stat in build:
			total += int(build[stat])
		cart.present_build(build)
		cart._compute_credit()
		var quoted: float = cart._credit_limit
		assert_eq(EconomySettings.credit_limit_for_sheet(build, eco, CREDIT_FLOOR, CREDIT_CEIL, total), quoted,
			"SHIP DECISION (per-level growth OFF): a fresh sheet at total level %d is quoted the same line in-run as the New Game cart offered" % total)
	cart.free()


func test_credit_limit_for_sheet_honours_career_and_record() -> void:
	# The one-call chain must actually FORWARD the career and the record — a wrapper that drops either would quote
	# every player the creation number forever.
	var build := _sheet({&"gunplay": 5, &"endurance": -5})  # a MEDIOCRE build: headroom both ways, far below the cap
	var growing := _live_eco().duplicate() as EconomySettings
	growing.credit_limit_per_level = 25.0
	var at_zero := EconomySettings.credit_limit_for_sheet(build, growing, CREDIT_FLOOR, CREDIT_CEIL, 0)
	assert_lt(at_zero + 1000.0, growing.credit_limit_lifetime_max, "fixture: the grown line stays under the lifetime ceiling")
	assert_eq(EconomySettings.credit_limit_for_sheet(build, growing, CREDIT_FLOOR, CREDIT_CEIL, 40), at_zero + 1000.0,
		"with growth on, 40 total levels at 25 zm/level add exactly 1000 zm to the same sheet's line")
	var eco := _live_eco()
	var spotless := EconomySettings.credit_limit_for_sheet(build, eco, CREDIT_FLOOR, CREDIT_CEIL, 0, eco.credit_standing_max)
	var delinquent := EconomySettings.credit_limit_for_sheet(build, eco, CREDIT_FLOOR, CREDIT_CEIL, 0, -eco.credit_standing_max)
	assert_gt(spotless, delinquent,
		"the same sheet quotes a bigger line with a spotless payment record than with arrears — paying your debts must raise your credit")
	assert_eq(EconomySettings.credit_limit_for_sheet(build, null, CREDIT_FLOOR, CREDIT_CEIL, 0), 0.0,
		"a null economy degrades to no credit rather than crashing the New Game flow")
	growing = null


# --- STANDING: the earned half of the score ----------------------------------------------------------------

func test_standing_defaults_to_zero_so_new_game_rates_the_build_alone() -> void:
	# ⭐A fresh character has NO payment history. The call without a record (what the implant screen makes) must
	# rate the BUILD ALONE — the same score an economy with the record switched off gives — or New Game would
	# silently score against a record nobody has yet.
	var eco := _live_eco()
	var record_off := eco.duplicate() as EconomySettings
	record_off.credit_weight_standing = 0.0
	for build in [_sheet({&"gunplay": 5, &"endurance": -5}), _sheet({&"gunplay": 10, &"strength": 10, &"endurance": 5}),
			_sheet({&"larceny": -5, &"streetwise": -5})]:
		assert_eq(EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL),
			EconomySettings.credit_score_for(build, record_off, CREDIT_FLOOR, CREDIT_CEIL, eco.credit_standing_max),
			"omitting standing rates the build alone, exactly as if the record did not count — the creation screen's contract")
	record_off = null


func test_standing_moves_the_score_both_ways() -> void:
	var eco := _live_eco()
	var build := _sheet({&"gunplay": 5, &"endurance": -5})  # a MEDIOCRE build, so there is headroom to climb
	var neutral := EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, 0.0)
	var spotless := EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, eco.credit_standing_max)
	var delinquent := EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, -eco.credit_standing_max)
	assert_gt(spotless, neutral, "a spotless record RAISES the rating — the whole point of payment history")
	assert_lt(delinquent, neutral, "…and a bad record lowers it: STANDING is the one SIGNED line")


func test_standing_is_monotone_and_bounded() -> void:
	# More standing is never worse, and the normalizer clamps, so an out-of-range value can't run the score off
	# its rails even if some future caller forgets add_credit_standing's clamp.
	var eco := _live_eco()
	var build := _sheet({&"gunplay": 5, &"endurance": -5})
	var prev := -1
	for st in [-500.0, -100.0, -50.0, 0.0, 50.0, 100.0, 500.0]:
		var s := EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, float(st))
		assert_gte(s, prev, "standing %s must not rate BELOW a worse record" % st)
		prev = s
	assert_eq(EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, 500.0),
		EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, eco.credit_standing_max),
		"standing past the max is clamped, not extrapolated")


func test_standing_does_not_break_build_monotonicity() -> void:
	# ⭐THE STRUCTURAL PROPERTY the whole credit model rests on: investing a point can never LOWER a rating and
	# dumping one can never RAISE it. STANDING is independent of every stat, so adding it must not disturb
	# that — this sweep crosses random builds with random records to prove the two axes don't interact.
	var eco := _live_eco()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210  # deterministic: the same sheets every run
	var violations := 0
	for i in 120:
		var sheet := {}
		for stat in CharacterStats.STAT_NAMES:
			sheet[stat] = rng.randi_range(CREDIT_FLOOR, CREDIT_CEIL)
		var standing := rng.randf_range(-eco.credit_standing_max, eco.credit_standing_max)
		var base := EconomySettings.credit_score_for(sheet, eco, CREDIT_FLOOR, CREDIT_CEIL, standing)
		for stat in CharacterStats.STAT_NAMES:
			if int(sheet[stat]) < CREDIT_CEIL:
				var hi := sheet.duplicate()
				hi[stat] = int(sheet[stat]) + 1
				if EconomySettings.credit_score_for(hi, eco, CREDIT_FLOOR, CREDIT_CEIL, standing) < base:
					violations += 1
			if int(sheet[stat]) > CREDIT_FLOOR:
				var lo := sheet.duplicate()
				lo[stat] = int(sheet[stat]) - 1
				if EconomySettings.credit_score_for(lo, eco, CREDIT_FLOOR, CREDIT_CEIL, standing) > base:
					violations += 1
	assert_eq(violations, 0,
		"no build move may invert at any standing — the record and the build are independent axes")


func test_a_bad_record_is_the_filed_reason() -> void:
	# The one complaint a player can act on TODAY (walk to a terminal and pay), so it outranks every build
	# criticism — telling a delinquent player about their stat allocation would be useless advice.
	var eco := _live_eco()
	var build := _sheet({&"gunplay": 5, &"endurance": -5})
	var bad := EconomySettings.credit_rating_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, -eco.credit_standing_max)
	assert_eq(bad["reason"], EconomySettings.REASON_DELINQUENT,
		"a negative record files as DELINQUENT ahead of any build line")
	var good := EconomySettings.credit_rating_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, eco.credit_standing_max)
	assert_ne(good["reason"], EconomySettings.REASON_DELINQUENT,
		"…and a good record never does")


func test_standing_weight_at_zero_disables_the_record() -> void:
	# The designer's off-switch for the earned half: conduct stops mattering, the build alone rates you.
	var eco := GameSettings.economy.duplicate() as EconomySettings
	eco.credit_weight_standing = 0.0
	var build := _sheet({&"gunplay": 5, &"endurance": -5})
	assert_eq(EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, 100.0),
		EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, -100.0),
		"with the standing weight at 0 the record is inert in both directions")
	eco = null
