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

const CREDIT_FLOOR := -5   ## StatBudget.STAT_MIN
const CREDIT_CEIL := 10    ## StatBudget.STAT_MAX


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


func test_banking_knob_defaults() -> void:
	# The shipped economy — the feature's authored contract. These are SCRIPT defaults, so .new() is correct.
	var s := EconomySettings.new()
	assert_eq(s.bank_debt_interest_rate, 0.02, "debt compounds at 2%/in-game-day")
	assert_eq(s.bank_savings_interest_rate, 0.005, "savings grow at 0.5%/in-game-day — a 4:1 spread")
	assert_eq(s.bank_noncash_fee_fraction, 0.03,
		"the non-cash purchase fee ships at 3% — THE counterweight that keeps pocket cash worth carrying")
	assert_eq(s.bank_min_transaction, 0.0, "terminals process any amount out of the box")
	assert_eq(s.credit_limit_per_level, 0.0,
		"the per-level credit growth ships OFF, so the live line is byte-identically the creation formula")
	s = null


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


func test_credit_limit_for_sheet_chains_the_whole_rating() -> void:
	# New Game's cart and the live in-run line MUST quote the same number for the same sheet, or the player is
	# told two different things about the same file.
	var eco := _live_eco()
	var build := _sheet({&"gunplay": 10, &"strength": 10, &"endurance": -5, &"agility": -5,
		&"streetwise": -5, &"larceny": -5})
	var score := EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL)
	var direct := EconomySettings.credit_limit_for(score, eco.credit_score_min, eco.credit_score_max,
			eco.credit_limit_max, eco.credit_limit_step, eco.credit_limit_curve)
	assert_eq(EconomySettings.credit_limit_for_sheet(build, eco, CREDIT_FLOOR, CREDIT_CEIL, 0), direct,
		"the one-call chain equals rating -> limit -> line computed by hand, so the two surfaces can't drift")
	assert_eq(EconomySettings.credit_limit_for_sheet(build, null, CREDIT_FLOOR, CREDIT_CEIL, 0), 0.0,
		"a null economy degrades to no credit rather than crashing the New Game flow")


# --- STANDING: the earned half of the score ----------------------------------------------------------------

func test_standing_defaults_to_zero_so_new_game_rates_the_build_alone() -> void:
	# ⭐A fresh character has NO payment history. The 4-arg call (what the implant screen uses) must equal the
	# 5-arg call with zero standing, or New Game would silently score against a record nobody has yet.
	var eco := _live_eco()
	var build := _sheet({&"gunplay": 5, &"endurance": -5})
	assert_eq(EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL),
		EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL, 0.0),
		"omitting standing is exactly the same as passing zero — the creation screen's contract")


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
