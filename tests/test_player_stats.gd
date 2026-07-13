extends GutTest

## CharacterStats — the RPG stat sheet (carried by EVERY Character, player and NPC) and its effect formulas,
## plus the seams that consume them. The load-bearing contract: a BASELINE sheet is perfectly NEUTRAL (all
## multipliers 1.0, all bonuses 0), so the stat system changed nothing until a stat is authored off baseline.
##
## The 2026-07 overhaul this pins: strength absorbed the old ENDURANCE (it now drives max HP + carry + melee),
## streetwise absorbed the old PERSUASION (prices + reputation), and STEALTH + PICKPOCKET are new. Every derived
## effect is a STRAIGHT LINE — there is NO soft cap: each point gives the same marginal effect forever, and the
## only clamp is the physical floor at 0 (no damage, frozen, undetectable) where a negative value is meaningless.
## The spawn effects (_apply_stats) live on Character, so the player and NPCs share one code path.

const PLAYER_PATH := "res://scripts/player/player.gd"
const NPC_PATH := "res://scripts/npc/npc.gd"
const MERCHANT_PATH := "res://scripts/components/merchant.gd"


## Bare host for CharacterStats.restamp_derived — the SAME minimal shape as PassiveItemBuffs' stub: max_hp/hp/
## carry_capacity fields, NO `damaged` signal and NO apply_stamina_max_delta method, so the chokepoint's HUD emit +
## stamina re-seed both no-op off-tree (proving the has_signal / has_method guards are load-bearing).
class _RestampHost:
	extends Node
	var max_hp: float = 10.0
	var hp: float = 10.0
	var carry_capacity: float = 5.0


func _sheet(str_v := 0, gun := 0, agi := 0, street := 0, ste := 0, pick := 0, end_v := 0) -> CharacterStats:
	var s := CharacterStats.new()
	s.strength = str_v
	s.endurance = end_v
	s.gunplay = gun
	s.agility = agi
	s.streetwise = street
	s.stealth = ste
	s.pickpocket = pick
	return s


func test_baseline_sheet_is_perfectly_neutral() -> void:
	var s := CharacterStats.new()
	assert_almost_eq(s.carry_bonus(), 0.0, 0.0001, "baseline strength adds no capacity")
	assert_almost_eq(s.max_hp_bonus(), 0.0, 0.0001, "baseline strength adds no HP")
	assert_almost_eq(s.melee_damage_mult(), 1.0, 0.0001, "baseline strength changes no melee damage")
	assert_almost_eq(s.stamina_bonus(), 0.0, 0.0001, "baseline endurance adds no stamina")
	assert_almost_eq(s.weapon_damage_mult(), 1.0, 0.0001, "baseline gunplay changes no gun damage")
	assert_almost_eq(s.headshot_damage_bonus(), 1.0, 0.0001, "baseline gunplay changes no headshot bonus")
	assert_almost_eq(s.sway_mult(), 1.0, 0.0001, "baseline gunplay changes no aim sway")
	assert_almost_eq(s.buy_price_mult(), 1.0, 0.0001, "baseline streetwise changes no buy price")
	assert_almost_eq(s.sell_price_mult(), 1.0, 0.0001, "baseline streetwise changes no sell price")
	assert_almost_eq(s.rep_gain_mult(), 1.0, 0.0001, "baseline streetwise changes no rep gain")
	assert_almost_eq(s.rep_loss_mult(), 1.0, 0.0001, "baseline streetwise changes no rep loss")
	assert_almost_eq(s.move_speed_mult(), 1.0, 0.0001, "baseline agility changes no move speed")
	assert_almost_eq(s.jump_mult(), 1.0, 0.0001, "baseline agility changes no jump")
	assert_almost_eq(s.detection_rate_mult(), 1.0, 0.0001, "baseline stealth changes no detection rate")
	assert_almost_eq(s.pickpocket_catch_chance(0.35, 0.03), 0.35, 0.0001, "baseline pickpocket leaves the base catch chance")
	assert_almost_eq(s.pickpocket_value_allowance(10.0, 5.0), 10.0, 0.0001, "baseline pickpocket leaves the base value allowance")
	s = null


func test_strength_drives_hp_carry_and_melee() -> void:
	# STRENGTH merged in the old Endurance: it now drives max HP AND carry AND melee damage.
	var s := _sheet(5)  # strength 5
	assert_almost_eq(s.carry_bonus(), 10.0, 0.0001, "strength 5 -> +10 carry capacity (2.0/pt)")
	assert_almost_eq(s.max_hp_bonus(), 7.5, 0.0001, "strength 5 -> +7.5 max HP (1.5/pt; strength absorbed Endurance)")
	assert_almost_eq(s.melee_damage_mult(), 1.25, 0.0001, "strength 5 -> +25% melee damage (5%/pt)")
	var weak := _sheet(-100)
	assert_almost_eq(weak.melee_damage_mult(), 0.0, 0.0001, "worse forever: a deeply negative strength floors melee at 0, never negative (no heal-the-target)")
	s = null
	weak = null


func test_endurance_drives_stamina_capacity() -> void:
	var s := _sheet(0, 0, 0, 0, 0, 0, 5)
	assert_almost_eq(s.stamina_bonus(), 50.0, 0.0001, "endurance 5 -> +50 max stamina (10/pt)")
	var tired := _sheet(0, 0, 0, 0, 0, 0, -3)
	assert_almost_eq(tired.stamina_bonus(), -30.0, 0.0001, "negative endurance lowers max stamina linearly")
	s = null
	tired = null


func test_gunplay_drives_gun_damage_and_aim() -> void:
	var s := _sheet(0, 5)  # gunplay 5
	assert_almost_eq(s.weapon_damage_mult(), 1.25, 0.0001, "gunplay 5 -> +25% gun damage (5%/pt)")
	assert_almost_eq(s.headshot_damage_bonus(), 1.25, 0.0001, "gunplay 5 -> +25% headshot punch")
	assert_almost_eq(s.sway_mult(), 0.6, 0.0001, "gunplay 5 -> 40% steadier aim (8%/pt)")
	s = null


func test_agility_speeds_movement_and_jump() -> void:
	var fast := _sheet(0, 0, 4)  # agility 4
	assert_almost_eq(fast.move_speed_mult(), 1.2, 0.0001, "agility 4 -> +20% move speed")
	assert_almost_eq(fast.jump_mult(), 1.2, 0.0001, "agility 4 -> +20% jump velocity")
	var slow := _sheet(0, 0, -2)
	assert_almost_eq(slow.move_speed_mult(), 0.9, 0.0001, "agility -2 -> 10% slower")
	var frozen := _sheet(0, 0, -100)
	assert_almost_eq(frozen.move_speed_mult(), 0.0, 0.0001, "worse forever: a deeply negative agility floors at 0 (the old 0.2 soft floor is gone)")
	fast = null
	slow = null
	frozen = null


func test_streetwise_drives_prices_and_reputation() -> void:
	# STREETWISE merged in the old Persuasion: it now drives BOTH shop prices AND reputation scaling.
	var s := _sheet(0, 0, 0, 5)  # streetwise 5
	assert_almost_eq(s.buy_price_mult(), 0.8, 0.0001, "streetwise 5 -> buys 20% cheaper")
	assert_almost_eq(s.sell_price_mult(), 1.2, 0.0001, "streetwise 5 -> sells 20% higher")
	assert_almost_eq(s.rep_gain_mult(), 1.4, 0.0001, "streetwise 5 -> positive rep 40% bigger")
	assert_almost_eq(s.rep_loss_mult(), 0.6, 0.0001, "streetwise 5 -> negative rep 40% smaller")
	var naive := _sheet(0, 0, 0, -1)
	assert_gt(naive.rep_loss_mult(), 1.0, "a NEGATIVE streetwise makes scandals cost MORE")
	s = null
	naive = null


func test_stealth_slows_detection() -> void:
	var sneaky := _sheet(0, 0, 0, 0, 5)  # stealth 5
	assert_almost_eq(sneaky.detection_rate_mult(), 0.75, 0.0001, "stealth 5 -> enemy meter fills 25% slower (5%/pt)")
	var clumsy := _sheet(0, 0, 0, 0, -4)
	assert_almost_eq(clumsy.detection_rate_mult(), 1.2, 0.0001, "stealth -4 -> spotted 20% FASTER (worse forever)")
	var ghost := _sheet(0, 0, 0, 0, 25)
	assert_almost_eq(ghost.detection_rate_mult(), 0.0, 0.0001, "very high stealth floors the rate at 0 — effectively undetectable (reaches 0, no plateau)")
	sneaky = null
	clumsy = null
	ghost = null


func test_pickpocket_catch_and_allowance() -> void:
	var thief := _sheet(0, 0, 0, 0, 0, 5)  # pickpocket 5
	assert_almost_eq(thief.pickpocket_catch_chance(0.35, 0.03), 0.20, 0.0001, "pickpocket 5 -> catch chance 0.35 - 5*0.03 = 0.20")
	assert_almost_eq(thief.pickpocket_value_allowance(10.0, 5.0), 35.0, 0.0001, "pickpocket 5 -> lift value up to 10 + 5*5 = 35")
	var master := _sheet(0, 0, 0, 0, 0, 20)
	assert_almost_eq(master.pickpocket_catch_chance(0.35, 0.03), 0.0, 0.0001, "a master thief's catch chance clamps at 0 (never negative)")
	var oaf := _sheet(0, 0, 0, 0, 0, -3)
	assert_almost_eq(oaf.pickpocket_value_allowance(10.0, 5.0), 0.0, 0.0001, "a negative pickpocket floors the value allowance at 0")
	assert_gt(oaf.pickpocket_catch_chance(0.35, 0.03), 0.35, "a negative pickpocket RAISES the catch risk past the base")
	thief = null
	master = null
	oaf = null


func test_no_soft_cap_prices_and_sway() -> void:
	# The headline of the overhaul: each point keeps giving the same effect PAST where the old floors/caps plateaued.
	assert_almost_eq(_sheet(0, 0, 0, 20).buy_price_mult(), 0.2, 0.0001, "streetwise 20 -> buys at 20% (below the OLD 0.5 half-price floor)")
	assert_almost_eq(_sheet(0, 0, 0, 25).buy_price_mult(), 0.0, 0.0001, "streetwise 25 -> buys for FREE (linear all the way down)")
	assert_almost_eq(_sheet(0, 0, 0, 20).sell_price_mult(), 1.8, 0.0001, "streetwise 20 -> sells at 180% (past the OLD 1.5 cap — better forever)")
	assert_almost_eq(_sheet(0, 15).sway_mult(), 0.0, 0.0001, "gunplay 15 -> perfectly steady (0 sway; the OLD 0.2 floor is gone)")


func test_get_stat_by_name_for_dialogue_checks() -> void:
	var s := _sheet(7, 6, 5, 4, 3, 2)
	assert_eq(s.get_stat(&"strength"), 7, "get_stat resolves strength by name (dialogue checks)")
	s.endurance = 8
	assert_eq(s.get_stat(&"endurance"), 8, "get_stat resolves endurance by name")
	assert_eq(s.get_stat(&"streetwise"), 4, "get_stat resolves streetwise by name")
	assert_eq(s.get_stat(&"pickpocket"), 2, "get_stat resolves the new pickpocket stat by name")
	assert_eq(s.get_stat(&"no_such_stat"), CharacterStats.BASELINE,
		"an unknown stat name reads BASELINE — a typo'd dialogue check is neutral, not a crash or freebie")
	s = null


func test_stat_names_round_trip_through_get_stat() -> void:
	# CharacterStats.stat_names() is the single source for the required_stat dropdown + the stat-iterating UIs.
	# Round-trip every name through get_stat so a renamed/added stat that forgets to update the other fails HERE.
	var names := CharacterStats.stat_names()
	assert_eq(names.size(), 7, "seven authored attributes -> seven stat names")
	var v := 1
	for n in names:
		var s := CharacterStats.new()
		s.set(n, v)  # set the @export attribute by name
		assert_eq(s.get_stat(StringName(n)), v, "stat_names() entry '%s' must be a real attribute get_stat resolves" % n)
		s = null
		v += 1


func test_stat_name_mirrors_share_one_source() -> void:
	# CP1: the stat-name list lives ONCE on CharacterStats.STAT_NAMES; every other list is `= CharacterStats.STAT_NAMES`
	# (a compile-time fold), so a name added there reaches the save columns, the level-up sum AND the character builder
	# at once. A hand-mirrored copy that forgot a name used to drop that stat from every save — deriving makes it impossible.
	assert_eq(GameState.STAT_NAMES, CharacterStats.STAT_NAMES,
		"GameState's [stats] save columns must derive from the CharacterStats.STAT_NAMES master")
	assert_eq(LevelUp.STAT_NAMES, CharacterStats.STAT_NAMES,
		"LevelUp's total-level sum must derive from the CharacterStats.STAT_NAMES master")
	# character_creation.gd has no class_name — load the script to read its STATS const off the GDScript object.
	var creation: GDScript = load("res://scripts/ui/character_creation.gd")
	assert_eq(creation.STATS, CharacterStats.STAT_NAMES,
		"the character builder's STATS list must derive from the CharacterStats.STAT_NAMES master")


func test_restamp_derived_floors_heals_and_returns_applied_delta() -> void:
	# C61: restamp_derived is the ONE chokepoint LevelUp / PerkManager / PassiveItemBuffs share. A POSITIVE delta
	# raises the max, heals hp up by the same, and returns the applied delta unchanged (the stub has no stamina, so
	# old_stamina_max defaults to -1 = leave it alone).
	var host := _RestampHost.new()
	var applied := CharacterStats.restamp_derived(host, 3.0, 4.0)
	assert_almost_eq(host.max_hp, 13.0, 0.0001, "positive hp_delta raises max HP by the delta")
	assert_almost_eq(host.hp, 13.0, 0.0001, "...and heals current hp up by the same delta (Dark-Souls heal on gain)")
	assert_almost_eq(host.carry_capacity, 9.0, 0.0001, "positive carry_delta raises carry capacity by the delta")
	assert_almost_eq(applied.x, 3.0, 0.0001, "returns the applied hp delta")
	assert_almost_eq(applied.y, 4.0, 0.0001, "returns the applied carry delta")
	# A NEGATIVE delta that drives max HP below its 1.0 floor (and carry below 0) returns the REAL post-floor delta,
	# NOT the ideal -20 — so a running-total caller (PassiveItemBuffs) telescopes back EXACTLY on removal.
	var floored := CharacterStats.restamp_derived(host, -20.0, -20.0)
	assert_almost_eq(host.max_hp, 1.0, 0.0001, "max HP floors at 1, never below")
	assert_almost_eq(host.carry_capacity, 0.0, 0.0001, "carry capacity floors at 0")
	assert_almost_eq(floored.x, -12.0, 0.0001, "returns the REAL post-floor hp delta (13 -> 1 = -12), not the ideal -20")
	assert_almost_eq(floored.y, -9.0, 0.0001, "returns the REAL post-floor carry delta (9 -> 0 = -9), not the ideal -20")
	host.free()


func test_dialogue_choice_gains_an_optional_skill_check() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.required_stat, &"", "no check by default — existing dialogue is untouched")
	assert_eq(c.required_value, 0, "no threshold by default")
	c.required_stat = &"streetwise"
	c.required_value = 6
	assert_eq(c.required_stat, &"streetwise", "a choice can require a named stat")
	c = null


func test_apply_stats_stamps_hp_and_carry() -> void:
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.carry_capacity = 10.0
	p.stats = _sheet(3)  # strength 3 drives BOTH max HP and carry now
	p._apply_stats()
	assert_almost_eq(p.max_hp, 104.5, 0.0001, "strength 3 -> +4.5 max HP (1.5/pt), stamped before hp seeds")
	assert_almost_eq(p.carry_capacity, 16.0, 0.0001, "strength 3 -> +6 carry capacity (2.0/pt)")
	p.free()


func test_npc_applies_stats_too() -> void:
	# Stats live on Character, so an NPC stamps strength exactly like the player. _apply_stats is pure, safe off-tree.
	var n = load(NPC_PATH).new()
	n.max_hp = 100.0
	n.carry_capacity = 10.0
	n.stats = _sheet(3)  # strength 3
	n._apply_stats()
	assert_almost_eq(n.max_hp, 104.5, 0.0001, "an NPC's strength stamps its max_hp (shared Character path)")
	assert_almost_eq(n.carry_capacity, 16.0, 0.0001, "an NPC's strength stamps its carry_capacity")
	n.free()


func test_merchant_prices_respect_streetwise() -> void:
	var m = load(MERCHANT_PATH).new()
	m.buy_mult = 1.0
	m.sell_mult = 1.0
	var it := Item.new()
	it.value = 100
	assert_eq(m.buy_price(it), 100, "no buyer -> the bare markup price (NPCs / tests unchanged)")
	var p = load(PLAYER_PATH).new()
	p.stats = _sheet(0, 0, 0, 5)  # streetwise 5
	assert_eq(m.buy_price(it, p), 80, "streetwise 5 buys at 80%")
	assert_eq(m.sell_price(it, p), 120, "streetwise 5 sells at 120%")
	p.free()
	m.free()
	it = null


func test_status_bonus_folds_into_multiplier_stats() -> void:
	# StatusEffect.stat_modifiers fold via the optional `bonus` arg (fed at each seam by Character.status_stat_modifier).
	# A +2 bonus shifts the curve exactly as if the stat were raised, and 0.0 (the default) leaves every existing call
	# untouched. strength's carry/max_hp are spawn-stamped (no bonus arg) but its melee_damage_mult IS live.
	var base := CharacterStats.new()
	assert_almost_eq(base.melee_damage_mult(2.0), _sheet(2).melee_damage_mult(), 0.0001, "strength bonus folds into melee damage")
	assert_almost_eq(base.stamina_bonus(2.0), _sheet(0, 0, 0, 0, 0, 0, 2).stamina_bonus(), 0.0001, "endurance bonus folds into stamina capacity")
	assert_almost_eq(base.weapon_damage_mult(2.0), _sheet(0, 2).weapon_damage_mult(), 0.0001, "gunplay bonus folds into gun damage")
	assert_almost_eq(base.headshot_damage_bonus(2.0), _sheet(0, 2).headshot_damage_bonus(), 0.0001, "gunplay bonus folds into headshot punch")
	assert_almost_eq(base.sway_mult(2.0), _sheet(0, 2).sway_mult(), 0.0001, "gunplay bonus folds into aim sway")
	assert_almost_eq(base.move_speed_mult(2.0), _sheet(0, 0, 2).move_speed_mult(), 0.0001, "agility bonus folds into move speed")
	assert_almost_eq(base.jump_mult(2.0), _sheet(0, 0, 2).jump_mult(), 0.0001, "agility bonus folds into jump")
	assert_almost_eq(base.buy_price_mult(2.0), _sheet(0, 0, 0, 2).buy_price_mult(), 0.0001, "streetwise bonus folds into buy price")
	assert_almost_eq(base.sell_price_mult(2.0), _sheet(0, 0, 0, 2).sell_price_mult(), 0.0001, "streetwise bonus folds into sell price")
	assert_almost_eq(base.rep_gain_mult(2.0), _sheet(0, 0, 0, 2).rep_gain_mult(), 0.0001, "streetwise bonus folds into rep gain")
	assert_almost_eq(base.detection_rate_mult(2.0), _sheet(0, 0, 0, 0, 2).detection_rate_mult(), 0.0001, "stealth bonus folds into detection rate")
	assert_almost_eq(base.pickpocket_catch_chance(0.35, 0.03, 2.0), _sheet(0, 0, 0, 0, 0, 2).pickpocket_catch_chance(0.35, 0.03), 0.0001, "pickpocket bonus folds into catch chance")
	assert_almost_eq(base.move_speed_mult(), 1.0, 0.0001, "no bonus at baseline = 1.0 (existing no-arg calls unchanged)")
	base = null
