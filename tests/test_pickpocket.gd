extends GutTest

## The PICKPOCKET steal-GATE — LootScreen._pickpocket_can_lift, the pure rule for WHAT a live pickpocket may lift:
## loose cash + valueless junk always, the weapon in their hands only past the equipped threshold, and everything
## else only under the skill-scaled value allowance. Called as a static on the loaded script (no autoload instance,
## no tree). The caught ROLL itself is RNG at the seam; the probability math it rolls against is pinned separately in
## test_player_stats (pickpocket_catch_chance / pickpocket_value_allowance).

const LOOT_PATH := "res://scripts/ui/loot_screen.gd"

const NPC_PATH := "res://scripts/npc/npc.gd"

func _settings() -> PickpocketSettings:
	var s := PickpocketSettings.new()
	s.base_value_allowance = 10.0
	s.value_allowance_per_point = 5.0
	s.equipped_pickpocket_threshold = 8
	s.base_catch_chance = 0.35
	s.catch_chance_per_point = 0.03
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

func test_value_gate_scales_with_skill() -> void:
	var ls = load(LOOT_PATH)
	var st := _settings()  # allowance = 10 + pickpocket*5; a 30-value item needs pickpocket >= 4
	assert_false(ls._pickpocket_can_lift(_item(30.0), null, _sheet(3), st),
		"pickpocket 3 (allowance 25) can't lift a 30-value item unnoticed")
	assert_true(ls._pickpocket_can_lift(_item(30.0), null, _sheet(4), st),
		"pickpocket 4 (allowance 30) can lift it")

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

func test_success_percent_negative_when_unliftable() -> void:
	var ls = load(LOOT_PATH)
	var st := _settings()  # allowance = 10 + pickpocket*5
	assert_eq(ls._pickpocket_success_percent(_item(30.0), null, _sheet(3), st), -1,
		"an over-allowance item can't be lifted at all -> -1 (the tooltip shows a reason, not a %)")
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
