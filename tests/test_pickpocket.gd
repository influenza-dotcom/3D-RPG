extends GutTest

## The PICKPOCKET risk layer — LootScreen's pure statics for WHAT a live pickpocket may attempt and at WHAT odds:
## _pickpocket_can_lift (the only hard refusal left: the drawn weapon below the equipped threshold — VALUE never
## refuses since the gate-to-risk change) and _pickpocket_catch_for / _pickpocket_success_percent (the skill-bent
## catch chance PLUS over_value_risk per zorkmid above the allowance — one formula behind the hover % and the
## take's roll). Called as statics on the loaded script (no autoload instance, no tree). The caught ROLL itself is
## RNG at the seam; the base probability math is pinned separately in test_player_stats.

const LOOT_PATH := "res://scripts/ui/loot_screen.gd"

const NPC_PATH := "res://scripts/npc/npc.gd"

func _settings() -> PickpocketSettings:
	var s := PickpocketSettings.new()
	s.base_value_allowance = 10.0
	s.value_allowance_per_point = 5.0
	s.equipped_pickpocket_threshold = 8
	s.base_catch_chance = 0.35
	s.catch_chance_per_point = 0.03
	s.over_value_risk = 0.004  # +0.4% catch per zorkmid above the allowance (the value-RISK slope)
	return s

func _item(value: float, id := &"trinket") -> Item:
	var it := Item.new()
	it.id = id
	it.value = value
	return it

## The pickpocket mechanic is now driven by the merged LARCENY stat (it absorbed the old PICKPOCKET). `lar` is the
## larceny value; the steal-gate / catch math reads it exactly where it used to read pickpocket.
func _sheet(lar: int) -> CharacterStats:
	var s := CharacterStats.new()
	s.larceny = lar
	return s

func test_valueless_and_cash_always_lift() -> void:
	var ls = load(LOOT_PATH)
	var st := _settings()
	assert_true(ls._pickpocket_can_lift(_item(0.0), null, _sheet(0), st),
		"a valueless item always pockets, even at pickpocket 0")
	assert_true(ls._pickpocket_can_lift(_item(9999.0, Zorkmids.ITEM_ID), null, _sheet(0), st),
		"loose cash (a zorkmids stack) always pockets regardless of amount")

func test_value_never_refuses_it_raises_risk_instead() -> void:
	# THE GATE-TO-RISK CHANGE (user: "why can't you ATTEMPT to pickpocket valuable things like microchips?").
	# An over-allowance item is attemptable at any skill — the overage lands in the CAUGHT chance instead.
	var ls = load(LOOT_PATH)
	var st := _settings()  # allowance = 10 + larceny*5; catch = 0.35 - 0.03/pt + 0.004/zm over
	assert_true(ls._pickpocket_can_lift(_item(30.0), null, _sheet(3), st),
		"larceny 3 (allowance 25) may now ATTEMPT a 30-value item — value no longer padlocks the click")
	# larceny 3: catch 0.26 + 5 overage * 0.004 = 0.28 -> 72%. larceny 4: overage 0 -> catch 0.23 -> 77%.
	assert_eq(ls._pickpocket_success_percent(_item(30.0), null, _sheet(3), st), 72,
		"...at reduced odds: the 5-zm overage costs 2% on top of the skill catch (72%, not 74%)")
	assert_eq(ls._pickpocket_success_percent(_item(30.0), null, _sheet(4), st), 77,
		"one more larceny point absorbs the overage entirely — back on the plain skill curve")

func test_microchip_is_a_gamble_that_scales_with_larceny() -> void:
	# The motivating case: a 250-zm chip. A novice sees an HONEST 0% (attemptable, guaranteed bust — the
	# tooltip says so); an invested thief sees a real gamble. This is the skill-investment payoff in one row.
	var ls = load(LOOT_PATH)
	var st := _settings()
	var chip := _item(250.0, &"chip_laser_sight")
	assert_true(ls._pickpocket_can_lift(chip, null, _sheet(0), st),
		"even at larceny 0 the chip is ATTEMPTABLE — no more flat 'too valuable' refusal")
	assert_eq(ls._pickpocket_success_percent(chip, null, _sheet(0), st), 0,
		"larceny 0: 240-zm overage buries the roll — an honest 0% (catch clamps at 100%)")
	# larceny 12: base catch clamps to 0 (0.35 - 0.36), allowance 70 -> overage 180 * 0.004 = 0.72 catch.
	assert_eq(ls._pickpocket_success_percent(chip, null, _sheet(12), st), 28,
		"larceny 12 turns the chip into a 28% gamble — investment buys real odds, not just a wider free band")
	assert_almost_eq(ls._pickpocket_catch_for(chip, _sheet(12), st), 0.72, 0.0001,
		"...and the hover % is 1 - the exact catch the take will roll (one formula, two readers)")

func test_cash_and_valueless_carry_no_value_risk() -> void:
	# Loose cash is pocketed loose, not appraised mid-lift: a fat wallet rolls the PLAIN skill catch, never the
	# overage slope (else robbing a rich mark would be paradoxically harder than a poor one per coin).
	var ls = load(LOOT_PATH)
	var st := _settings()
	assert_eq(ls._pickpocket_success_percent(_item(9999.0, Zorkmids.ITEM_ID), null, _sheet(0), st), 65,
		"a 9999-zm coin tile reads the plain 65% (1 - 0.35) — no value-risk on cash")
	assert_eq(ls._pickpocket_success_percent(_item(0.0), null, _sheet(0), st), 65,
		"valueless junk likewise sits on the plain skill curve")

func test_equipped_weapon_gated_by_threshold() -> void:
	var ls = load(LOOT_PATH)
	var st := _settings()  # equipped_pickpocket_threshold 8
	var weapon := _item(0.0, &"pistol")  # the DRAWN weapon; the equipped rule ignores its value
	assert_false(ls._pickpocket_can_lift(weapon, weapon, _sheet(7), st),
		"below the equipped threshold, the weapon in their hands stays out of reach")
	assert_true(ls._pickpocket_can_lift(weapon, weapon, _sheet(8), st),
		"at/above the threshold, a master thief lifts the drawn weapon too")

func test_null_inputs_fail_safe() -> void:
	var ls = load(LOOT_PATH)
	assert_false(ls._pickpocket_can_lift(null, null, _sheet(20), _settings()), "a null item lifts nothing")
	assert_false(ls._pickpocket_can_lift(_item(5.0), null, null, _settings()), "a null sheet lifts nothing")
	assert_false(ls._pickpocket_can_lift(_item(5.0), null, _sheet(20), null), "null settings lift nothing")

## The hover SUCCESS readout (LootScreen._pickpocket_success_percent) — 1 - catch chance for a liftable item, -1 for
## anything the steal-gate refuses. The same math the caught roll faces, so the number the player sees IS the risk.
func test_success_percent_is_one_minus_catch() -> void:
	var ls = load(LOOT_PATH)
	var st := _settings()  # base catch 0.35, -0.03 per point
	# pickpocket 0: catch 0.35 -> 65% success. pickpocket 5: catch 0.20 -> 80% success.
	assert_eq(ls._pickpocket_success_percent(_item(0.0), null, _sheet(0), st), 65,
		"at pickpocket 0 a freely-liftable item reads 65% (1 - 0.35 catch)")
	assert_eq(ls._pickpocket_success_percent(_item(0.0), null, _sheet(5), st), 80,
		"each pickpocket point removes 3% catch -> 80% at pickpocket 5")

func test_success_percent_negative_only_for_the_padlocked_drawn_weapon() -> void:
	# -1 (the padlock reason instead of a %) now means exactly ONE thing: the drawn weapon below the equipped
	# threshold. It is the last hard refusal — physically out of reach, not merely risky.
	var ls = load(LOOT_PATH)
	var st := _settings()
	var weapon := _item(0.0, &"pistol")
	assert_eq(ls._pickpocket_success_percent(weapon, weapon, _sheet(7), st), -1,
		"the drawn weapon below the equipped threshold reads -1 (padlocked), not a chance")
	assert_true(ls._pickpocket_success_percent(weapon, weapon, _sheet(8), st) >= 0,
		"at/above the threshold the drawn weapon becomes a real, rollable lift")

func test_catch_buff_raises_success() -> void:
	var ls = load(LOOT_PATH)
	var st := _settings()
	# A +5 pickpocket status buff (mod) lifts the odds exactly like 5 real points would: 65% -> 80%.
	assert_eq(ls._pickpocket_success_percent(_item(0.0), null, _sheet(0), st, 5.0), 80,
		"an active pickpocket buff folds into the shown odds (mod arg)")

## The one-strike lockout (NPC.pickpocket_allowed / mark_pickpocket_caught) — Talkable._can_pickpocket ANDs this in
## so a botched steal shuts a mark's pockets for good. Built off-tree (no _ready per the repo's NPC-test rule); the
## flag is a pure bool with no tree access.
func test_npc_pickpocket_lockout_latches() -> void:
	var npc = load(NPC_PATH).new()
	assert_true(npc.pickpocket_allowed(), "a fresh NPC allows a pickpocket attempt")
	npc.mark_pickpocket_caught()
	assert_false(npc.pickpocket_allowed(), "once caught, the mark refuses further attempts for good")
	npc.free()
