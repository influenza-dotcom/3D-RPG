extends GutTest

## CharacterStats — the RPG stat sheet (carried by EVERY Character, player and NPC) and its effect formulas,
## plus the seams that consume them. The load-bearing contract: a BASELINE sheet is perfectly NEUTRAL (all
## multipliers 1.0, all bonuses 0), so adding the stat system changed nothing until a stat is authored off
## baseline. The spawn effects (_apply_stats) live on Character, so the player and NPCs share one code path.

const PLAYER_PATH := "res://scripts/player/player.gd"
const NPC_PATH := "res://scripts/npc/npc.gd"
const MERCHANT_PATH := "res://scripts/components/merchant.gd"


func _sheet(str_v := 0, per := 0, gun := 0, end := 0, street := 0) -> CharacterStats:
	var s := CharacterStats.new()
	s.strength = str_v
	s.persuasion = per
	s.gunplay = gun
	s.endurance = end
	s.streetwise = street
	return s


func test_baseline_sheet_is_perfectly_neutral() -> void:
	var s := CharacterStats.new()
	assert_almost_eq(s.carry_bonus(), 0.0, 0.0001, "baseline strength adds no capacity")
	assert_almost_eq(s.max_hp_bonus(), 0.0, 0.0001, "baseline endurance adds no HP")
	assert_almost_eq(s.buy_price_mult(), 1.0, 0.0001, "baseline persuasion changes no buy price")
	assert_almost_eq(s.sell_price_mult(), 1.0, 0.0001, "baseline persuasion changes no sell price")
	assert_almost_eq(s.sway_mult(), 1.0, 0.0001, "baseline gunplay changes no aim sway")
	assert_almost_eq(s.rep_gain_mult(), 1.0, 0.0001, "baseline streetwise changes no rep gain")
	assert_almost_eq(s.rep_loss_mult(), 1.0, 0.0001, "baseline streetwise changes no rep loss")
	s = null


func test_stat_formulas_move_the_right_direction() -> void:
	var s := _sheet(2, 5, 5, 5, 5)
	assert_almost_eq(s.carry_bonus(), 4.0, 0.0001, "strength 2 -> +4 carry capacity (rule a)")
	assert_almost_eq(s.max_hp_bonus(), 25.0, 0.0001, "endurance 5 -> +25 max HP (rule d)")
	assert_almost_eq(s.buy_price_mult(), 0.8, 0.0001, "persuasion 5 -> buys 20% cheaper (rule b)")
	assert_almost_eq(s.sell_price_mult(), 1.2, 0.0001, "persuasion 5 -> sells 20% higher (rule b)")
	assert_almost_eq(s.sway_mult(), 0.6, 0.0001, "gunplay 5 -> 40% steadier aim (rule c)")
	assert_almost_eq(s.rep_gain_mult(), 1.4, 0.0001, "streetwise 5 -> positive rep lands 40% bigger (rule e)")
	assert_almost_eq(s.rep_loss_mult(), 0.6, 0.0001, "streetwise 5 -> negative rep lands 40% smaller (rule e)")
	var naive := _sheet(0, 0, 0, 0, -1)
	assert_gt(naive.rep_loss_mult(), 1.0, "a NEGATIVE (below-baseline) streetwise makes scandals cost MORE")
	s = null
	naive = null


func test_get_stat_by_name_for_dialogue_checks() -> void:
	var s := _sheet(7, 6, 5, 5, 5)
	assert_eq(s.get_stat(&"strength"), 7, "get_stat resolves strength by name (dialogue checks, rule f)")
	assert_eq(s.get_stat(&"persuasion"), 6, "get_stat resolves persuasion by name")
	assert_eq(s.get_stat(&"no_such_stat"), CharacterStats.BASELINE,
		"an unknown stat name reads BASELINE — a typo'd dialogue check is neutral, not a crash or freebie")
	s = null


func test_dialogue_choice_gains_an_optional_skill_check() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.required_stat, &"", "no check by default — existing dialogue is untouched")
	assert_eq(c.required_value, 0, "no threshold by default")
	c.required_stat = &"persuasion"
	c.required_value = 6
	assert_eq(c.required_stat, &"persuasion", "a choice can require a named stat (rule f)")
	c = null


func test_apply_stats_stamps_hp_and_carry_capacity() -> void:
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.carry_capacity = 10.0
	p.stats = _sheet(2, 0, 0, 3, 0)  # strength 2, endurance 3
	p._apply_stats()
	assert_almost_eq(p.max_hp, 115.0, 0.0001, "endurance 3 -> +15 max HP, stamped before hp seeds")
	assert_almost_eq(p.carry_capacity, 14.0, 0.0001, "strength 2 -> +4 carry capacity")
	p.free()


func test_npc_applies_stats_too() -> void:
	# Stats live on Character, so an NPC stamps endurance/strength exactly like the player — proving the
	# sheet is for every character, not just the player. _apply_stats is pure, safe off-tree (no _ready).
	var n = load(NPC_PATH).new()
	n.max_hp = 100.0
	n.carry_capacity = 10.0
	n.stats = _sheet(2, 0, 0, 3, 0)  # strength 2, endurance 3
	n._apply_stats()
	assert_almost_eq(n.max_hp, 115.0, 0.0001, "an NPC's endurance stamps its max_hp (shared Character path)")
	assert_almost_eq(n.carry_capacity, 14.0, 0.0001, "an NPC's strength stamps its carry_capacity")
	n.free()


func test_merchant_prices_respect_persuasion() -> void:
	var m = load(MERCHANT_PATH).new()
	m.buy_mult = 1.0
	m.sell_mult = 1.0
	var it := Item.new()
	it.value = 100
	assert_eq(m.buy_price(it), 100, "no buyer -> the bare markup price (NPCs / tests unchanged)")
	var p = load(PLAYER_PATH).new()
	p.stats = _sheet(0, 5)  # persuasion 5
	assert_eq(m.buy_price(it, p), 80, "persuasion 5 buys at 80% (rule b)")
	assert_eq(m.sell_price(it, p), 120, "persuasion 5 sells at 120% (rule b)")
	p.free()
	m.free()
	it = null
