extends GutTest

## The LevelUp component: the flat Dark-Souls cost curve (the SAME price for every stat at a given level) + the
## stat-raise (charge + DELTA re-apply of strength's HP/carry). The modal + dialogue flow are in-tree (playtested);
## the LevelUp methods touch no transforms, so they run off-tree on a bare player (stats_or_default lazily makes a
## private baseline sheet).

const PLAYER_PATH := "res://scripts/player/player.gd"

## ⭐Paid services now gate on the PAYMENT SEAM (Player.can_pay/charge), which reads the SHARED GameState
## banking fields. A suite that left a positive account behind would make the "broke" player below silently
## solvent and turn a refusal test green for the wrong reason. Snapshot + restore, the test_start_menu idiom.
var _prev_account: float
var _prev_method: String

func before_each() -> void:
	_prev_account = GameState.account
	_prev_method = GameState.payment_method
	GameState.account = 0.0
	GameState.payment_method = "debit"

func after_each() -> void:
	GameState.account = _prev_account
	GameState.payment_method = _prev_method


func test_cost_rises_with_total_level() -> void:
	var lv := LevelUp.new()
	lv.base_cost = 10
	lv.cost_per_level = 10
	var p = load(PLAYER_PATH).new()
	assert_eq(lv.total_level(p), 0, "a baseline sheet (all stats 0) is total level 0")
	assert_eq(lv.level_up_cost(p), 10, "the first level costs base_cost")
	lv.free()
	p.free()


func test_cost_is_the_same_for_every_stat() -> void:
	# Dark Souls: the price depends ONLY on total level, never on WHICH stat or how high it already is. Raising a
	# maxed stat costs exactly what a fresh one does — the old per-stat opportunity cost is gone.
	var lv := LevelUp.new()
	lv.base_cost = 10
	lv.cost_per_level = 5.0
	var p = load(PLAYER_PATH).new()
	var s := CharacterStats.new()
	s.gunplay = 8   # a very high stat sitting next to fresh ones
	p.stats = s
	# total level = 8, so every stat costs base 10 + 8*5 = 50, regardless of the stat's own value.
	assert_eq(lv.level_up_cost(p, &"gunplay"), 50, "raising the already-high stat costs the flat total-level price")
	assert_eq(lv.level_up_cost(p, &"strength"), 50, "raising a fresh stat costs the SAME — no cheaper, no dearer")
	assert_eq(lv.level_up_cost(p, &"larceny"), 50, "a brand-new stat is priced the same too")
	assert_eq(lv.level_up_cost(p), 50, "the no-stat call is the same flat total-level curve")
	lv.free()
	p.free()
	s = null


func test_level_up_raises_stat_charges_and_applies_strength() -> void:
	var lv := LevelUp.new()
	lv.base_cost = 10
	lv.cost_per_level = 10
	var p = load(PLAYER_PATH).new()
	p.money = 100
	p.max_hp = 100.0
	p.hp = 100.0
	p.carry_capacity = 10.0
	assert_true(lv.level_up_stat(p, &"strength"), "an affordable strength raise succeeds")
	assert_eq(p.money, 90, "charged base_cost (10)")
	assert_eq(p.stats_or_default().get_stat(&"strength"), 1, "strength raised to 1")
	assert_almost_eq(p.max_hp, 101.5, 0.0001, "strength +1 -> +1.5 max HP (the DELTA); strength now drives HP")
	assert_almost_eq(p.hp, 101.5, 0.0001, "healed by the gained max")
	assert_almost_eq(p.carry_capacity, 12.0, 0.0001, "strength +1 -> +2 carry capacity too (both from one stat)")
	assert_eq(lv.level_up_cost(p), 20, "the next level costs more (total level is now 1)")
	lv.free()
	p.free()


func test_level_up_endurance_increases_stamina() -> void:
	var lv := LevelUp.new()
	lv.base_cost = 10
	lv.cost_per_level = 10
	var p = load(PLAYER_PATH).new()
	p.money = 100
	var old_max: float = p.stamina_max()
	p.stamina = old_max
	assert_true(lv.level_up_stat(p, &"endurance"), "an affordable endurance raise succeeds")
	assert_eq(p.stats_or_default().get_stat(&"endurance"), 1, "endurance raised to 1")
	assert_almost_eq(p.stamina_max(), old_max + CharacterStats.STAMINA_PER_ENDURANCE, 0.0001,
		"endurance +1 increases the max stamina cap")
	assert_almost_eq(p.stamina, p.stamina_max(), 0.0001,
		"raising endurance fills the newly gained stamina")
	lv.free()
	p.free()


func test_level_up_refused_when_broke() -> void:
	var lv := LevelUp.new()
	lv.base_cost = 10
	var p = load(PLAYER_PATH).new()
	p.money = 5  # < base_cost
	assert_false(lv.level_up_stat(p, &"strength"), "can't afford the raise -> refused")
	assert_eq(p.money, 5, "no charge on a refused raise")
	assert_eq(p.stats_or_default().get_stat(&"strength"), 0, "the stat is unchanged")
	lv.free()
	p.free()


func test_level_up_rejects_unknown_stat() -> void:
	var lv := LevelUp.new()
	var p = load(PLAYER_PATH).new()
	p.money = 1000
	assert_false(lv.level_up_stat(p, &"charisma"), "an unknown stat name is rejected (no such CharacterStat)")
	assert_eq(p.money, 1000, "no charge for a bad stat name")
	lv.free()
	p.free()


# --- Sub-baseline builds: the cost curve must bottom out at FREE, never invert into a payout -----------------

## Every stat at the creation floor — the worst sheet the zero-sum allocator can express (CharacterCreation
## STAT_MIN = -5), and the one that drove total_level far enough negative to invert the price. Deliberately
## UNANNOTATED (a Variant, like every `var p = load(PLAYER_PATH).new()` above): the player is reached
## duck-typed here, and an Object-typed local would make every .money / .stats read an unsafe access.
func _sub_baseline_player():
	var p = load(PLAYER_PATH).new()
	var s := CharacterStats.new()
	for stat in CharacterStats.STAT_NAMES:
		s.set(stat, -5)
	p.stats = s
	return p


func test_cost_never_goes_negative_below_baseline() -> void:
	# THE BUG: total_level is the SUM of the six stats, and creation permits a NET-NEGATIVE build, so the raw
	# curve (base + total*per_level) priced an all(-5) sheet at 1 + (-30 * 1.5) = -44. A negative price is not a
	# discount — it inverts the transaction (see the payout test below). The curve bottoms out at 0 instead.
	var lv := LevelUp.new()
	lv.base_cost = 1
	lv.cost_per_level = 1.5
	var p = _sub_baseline_player()
	assert_eq(lv.total_level(p), -30, "precondition: six stats at the -5 creation floor sum to total level -30")
	assert_eq(lv.level_up_cost(p), 0.0,
		"a sub-baseline sheet prices at the FLOOR, not the raw curve's -44 — training a weak character is free, never paid")
	for stat in CharacterStats.STAT_NAMES:
		assert_gte(lv.level_up_cost(p, stat), 0.0,
			"no stat may EVER price negative — a negative cost passes the affordability guard and pays the player")
	lv.free()
	p.free()


func test_sub_baseline_raise_never_pays_the_player() -> void:
	# The exploit this closes: with a negative price the `money < cost` guard passed for a broke player and
	# add_money(-cost) CREDITED them, so an all(-5) build could farm ~700 zorkmids while fully repairing itself.
	# A free raise must still WORK (it's the floored price, not a refusal) — it just moves no money.
	var lv := LevelUp.new()
	lv.base_cost = 1
	lv.cost_per_level = 1.5
	var p = _sub_baseline_player()
	p.money = 0.0
	assert_true(lv.level_up_stat(p, &"strength"),
		"a zero-cost raise is FREE-BUT-LEGAL (the RespecStation convention), not refused")
	assert_eq(p.stats_or_default().get_stat(&"strength"), -4, "…and it really raised the stat")
	assert_eq(p.money, 0.0,
		"a free raise moves NO money — the wallet must never grow from levelling up")
	# Repeat the whole climb: the wallet must not accumulate a single zorkmid across the sub-baseline range.
	for i in 25:
		lv.level_up_stat(p, &"endurance")
	assert_lte(p.money, 0.0,
		"no sequence of sub-baseline raises may ever leave the player richer than they started")
	lv.free()
	p.free()


func test_a_debtor_can_still_take_a_free_raise() -> void:
	# The wallet is legitimately NEGATIVE at the start of a run (New Game buys implants ON CREDIT), and the
	# station gates the fee only when there IS one — so debt locks a debtor out of PAID raises only. This is the
	# level-up twin of the free-respec-refused-while-negative fix in RespecStation.
	var lv := LevelUp.new()
	lv.base_cost = 1
	lv.cost_per_level = 1.5
	var p = _sub_baseline_player()
	p.money = -40.0  # bought implants on credit and hasn't earned it back yet
	assert_eq(lv.level_up_cost(p), 0.0, "precondition: the sub-baseline price is floored to free")
	assert_true(lv.level_up_stat(p, &"gunplay"),
		"a FREE raise serves a wallet in debt — `money < cost` alone would refuse it at -40 < 0")
	assert_eq(p.money, -40.0, "…and the debt is untouched: a free raise is free, not a credit")
	lv.free()
	p.free()


func test_paid_raise_still_refuses_a_debtor() -> void:
	# The other half of the gate: once the price is real, a negative wallet can't cover it. Debt must not become
	# a loophole that buys stats.
	var lv := LevelUp.new()
	lv.base_cost = 10
	lv.cost_per_level = 10
	var p = load(PLAYER_PATH).new()  # baseline sheet: total level 0, so the price is the full base_cost
	p.money = -40.0
	assert_eq(lv.level_up_cost(p), 10.0, "precondition: a baseline sheet pays the real base price")
	assert_false(lv.level_up_stat(p, &"strength"), "a PAID raise still refuses a wallet that can't cover it")
	assert_eq(p.money, -40.0, "no charge, no credit, no stat")
	assert_eq(p.stats_or_default().get_stat(&"strength"), 0, "the stat is unchanged")
	lv.free()
	p.free()
