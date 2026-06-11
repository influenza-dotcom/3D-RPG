extends GutTest

## The LevelUp component: the rising cost curve + the stat-raise (charge + DELTA re-apply of endurance/strength).
## The modal + dialogue flow are in-tree (playtested); the LevelUp methods touch no transforms, so they run
## off-tree on a bare player (stats_or_default lazily makes a private baseline sheet).

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


func test_level_up_raises_stat_charges_and_applies_endurance() -> void:
	var lv := LevelUp.new()
	lv.base_cost = 10
	lv.cost_per_level = 10
	var p = load(PLAYER_PATH).new()
	p.money = 100
	p.max_hp = 100.0
	p.hp = 100.0
	assert_true(lv.level_up_stat(p, &"endurance"), "an affordable endurance raise succeeds")
	assert_eq(p.money, 90, "charged base_cost (10)")
	assert_eq(p.stats_or_default().get_stat(&"endurance"), 1, "endurance raised to 1")
	assert_almost_eq(p.max_hp, 105.0, 0.0001, "endurance +1 -> +5 max HP (the DELTA, not the whole bonus)")
	assert_almost_eq(p.hp, 105.0, 0.0001, "healed by the gained max")
	assert_eq(lv.level_up_cost(p), 20, "the next level costs more (total level is now 1)")
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
