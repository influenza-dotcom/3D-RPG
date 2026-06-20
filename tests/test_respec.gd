extends GutTest

## Rank 29d: PerkManager.respec() reverses stat deltas + refunds points to EXACT baseline (no double-count), and
## Player.revoke_ability removes a granted ability + clears the hot-path ref. The delta round-trip is the safety
## net the spec demands — all off-tree on a stub host / a bare player.

const PERKMGR_PATH := "res://scripts/components/perk_manager.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"
const WALL_CLIMB_PATH := "res://scripts/components/abilities/wall_climb.gd"

class _StubPlayer extends Node:
	var stats: CharacterStats = CharacterStats.new()
	var max_hp: float = 100.0
	var hp: float = 100.0
	var carry_capacity: float = 10.0

func _perk(pid: StringName, bonuses := {}, reqs := []) -> Perk:
	var p := Perk.new()
	p.id = pid
	p.stat_bonuses = bonuses
	for r in reqs:
		p.requires_perks.append(r)
	return p

func test_respec_returns_stats_to_baseline() -> void:
	var m = load(PERKMGR_PATH).new()
	var stub := _StubPlayer.new()
	m.host = stub
	var base_max := stub.max_hp
	var base_hp := stub.hp
	var base_carry := stub.carry_capacity
	m.skill_points = 0
	m.unlock_perk(_perk(&"hardy", {"endurance": 4, "strength": 3}))
	m.unlock_perk(_perk(&"tough", {"endurance": 2}))
	assert_eq(stub.stats.endurance, 6, "endurance summed across perks")
	assert_gt(stub.max_hp, base_max, "endurance raised max hp")
	assert_gt(stub.carry_capacity, base_carry, "strength raised carry")
	var n: int = m.respec()
	assert_eq(n, 2, "two perks reversed")
	assert_eq(stub.stats.endurance, 0, "endurance back to baseline")
	assert_eq(stub.stats.strength, 0, "strength back to baseline")
	assert_almost_eq(stub.max_hp, base_max, 0.001, "max hp restored EXACTLY (no double-count)")
	assert_almost_eq(stub.hp, base_hp, 0.001, "hp restored exactly")
	assert_almost_eq(stub.carry_capacity, base_carry, 0.001, "carry restored exactly")
	assert_eq(m.skill_points, 2, "one point refunded per reversed perk")
	assert_true(m.unlocked_ids().is_empty(), "ledger cleared")
	stub.free()
	m.free()

func test_respec_empty_ledger_is_noop() -> void:
	var m = load(PERKMGR_PATH).new()
	assert_eq(m.respec(), 0, "nothing to respec")
	m.free()

func test_respec_refund_lets_repick() -> void:
	var m = load(PERKMGR_PATH).new()
	var stub := _StubPlayer.new()
	m.host = stub
	m.skill_points = 1
	m.unlock_perk(_perk(&"a", {"agility": 1}))
	m.skill_points -= 1  # mimic the picker (LevelUp.unlock_perk) spending the point
	assert_eq(m.skill_points, 0, "point spent on the unlock")
	m.respec()
	assert_eq(m.skill_points, 1, "the spent point came back")
	assert_true(m.can_unlock(_perk(&"a", {"agility": 1})), "a respecced perk is unlockable again")
	stub.free()
	m.free()

func test_revoke_ability_removes_and_nulls_hot_path_ref() -> void:
	var p = load(PLAYER_PATH).new()
	var wc = load(WALL_CLIMB_PATH).new()  # a real WallClimb (its ability_id() is a pure constant)
	p.add_child(wc)
	p._abilities.append(wc)
	p._wall_climb = wc  # wire the hot-path ref directly (no setup() needed — testing the nulling)
	assert_true(p.has_mechanic(&"wall_climb"), "granted")
	assert_eq(p._wall_climb, wc, "hot-path ref set")
	p.revoke_ability(&"wall_climb")
	assert_null(p._wall_climb, "hot-path ref nulled (no dangling pointer)")
	assert_false(p.has_mechanic(&"wall_climb"), "mechanic gone")
	assert_false(p.unlocked_list().has(&"wall_climb"), "excluded from the save list")
	p.free()
