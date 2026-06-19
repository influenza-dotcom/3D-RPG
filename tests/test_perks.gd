extends GutTest

## Slice 8 (perks): PerkManager unlock logic — prerequisites, no double-unlock, and permanent stat-bonus
## application (endurance -> max_hp, strength -> carry, mirroring LevelUp) against a stub player. The PerkStation
## interaction + ability granting are playtest-verified per the in-tree convention.

const PERKMGR_PATH := "res://scripts/components/perk_manager.gd"  # load by path (cache-independent) so the test
                                                                # doesn't depend on the global-class-cache state

class _StubPlayer extends Node:
	var stats: CharacterStats = CharacterStats.new()
	var max_hp: float = 4.0
	var hp: float = 4.0
	var carry_capacity: float = 10.0

func _perk(pid: StringName, bonuses := {}, reqs := []) -> Perk:
	var p := Perk.new()
	p.id = pid
	p.stat_bonuses = bonuses
	for r in reqs:
		p.requires_perks.append(r)
	return p

func test_perk_defaults() -> void:
	var p := Perk.new()
	assert_eq(p.id, &"", "no id by default")
	assert_true(p.stat_bonuses.is_empty(), "no bonuses by default")
	assert_true(p.requires_perks.is_empty(), "no prerequisites by default")
	p = null

func test_unlock_records_and_blocks_duplicate() -> void:
	var m = load(PERKMGR_PATH).new()
	var p := _perk(&"tough")
	assert_true(m.can_unlock(p), "a fresh perk can unlock")
	assert_true(m.unlock_perk(p), "unlock succeeds")
	assert_true(m.has_perk(&"tough"), "recorded as unlocked")
	assert_false(m.can_unlock(p), "already owned -> can't re-unlock")
	assert_false(m.unlock_perk(p), "re-unlock is a no-op")
	m.free()

func test_prerequisites_gate_unlock() -> void:
	var m = load(PERKMGR_PATH).new()
	var advanced := _perk(&"advanced", {}, [&"base"])
	assert_false(m.can_unlock(advanced), "blocked until the prerequisite is unlocked")
	assert_false(m.unlock_perk(advanced), "...unlock refused")
	m.unlock_perk(_perk(&"base"))
	assert_true(m.can_unlock(advanced), "prerequisite met -> now unlockable")
	assert_true(m.unlock_perk(advanced), "...and it unlocks")
	m.free()

func test_stat_bonuses_apply_with_deltas() -> void:
	var m = load(PERKMGR_PATH).new()
	var stub := _StubPlayer.new()
	m.host = stub
	# +2 endurance -> +3.0 max HP (1.5 per point), healed by the same; +2 strength -> +4.0 carry (2.0 per point)
	m.unlock_perk(_perk(&"hardy", {"endurance": 2, "strength": 2}))
	assert_eq(stub.stats.endurance, 2, "endurance bonus lands on the sheet")
	assert_eq(stub.stats.strength, 2, "strength bonus lands")
	assert_almost_eq(stub.max_hp, 7.0, 0.001, "endurance raised max HP by its delta")
	assert_almost_eq(stub.hp, 7.0, 0.001, "...and healed by it")
	assert_almost_eq(stub.carry_capacity, 14.0, 0.001, "strength raised carry capacity")
	stub.free()
	m.free()

func test_unknown_stat_key_is_ignored() -> void:
	var m = load(PERKMGR_PATH).new()
	var stub := _StubPlayer.new()
	m.host = stub
	m.unlock_perk(_perk(&"weird", {"luck": 5}))  # not a real CharacterStats attribute
	assert_almost_eq(stub.max_hp, 4.0, 0.001, "an unknown stat key changes nothing")
	stub.free()
	m.free()
