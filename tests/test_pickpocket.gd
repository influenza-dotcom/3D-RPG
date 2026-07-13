extends GutTest

## The PICKPOCKET steal-GATE — LootScreen._pickpocket_can_lift, the pure rule for WHAT a live pickpocket may lift:
## loose cash + valueless junk always, the weapon in their hands only past the equipped threshold, and everything
## else only under the skill-scaled value allowance. Called as a static on the loaded script (no autoload instance,
## no tree). The caught ROLL itself is RNG at the seam; the probability math it rolls against is pinned separately in
## test_player_stats (pickpocket_catch_chance / pickpocket_value_allowance).

const LOOT_PATH := "res://scripts/ui/loot_screen.gd"

func _settings() -> PickpocketSettings:
	var s := PickpocketSettings.new()
	s.base_value_allowance = 10.0
	s.value_allowance_per_point = 5.0
	s.equipped_pickpocket_threshold = 8
	return s

func _item(value: float, id := &"trinket") -> Item:
	var it := Item.new()
	it.id = id
	it.value = value
	return it

func _sheet(pick: int) -> CharacterStats:
	var s := CharacterStats.new()
	s.pickpocket = pick
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
