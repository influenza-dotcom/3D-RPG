extends GutTest

## The LevelUp component: the flat Dark-Souls cost curve (the SAME price for every stat at a given level) + the
## stat-raise (charge + DELTA re-apply of strength's HP/carry). The modal + dialogue flow are in-tree (playtested);
## the LevelUp methods touch no transforms, so they run off-tree on a bare player (stats_or_default lazily makes a
## private baseline sheet).

const PLAYER_PATH := "res://scripts/player/player.gd"


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
