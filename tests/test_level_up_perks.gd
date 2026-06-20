extends GutTest

## Rank 29c: LevelUp.unlock_perk spends a skill point and routes to PerkManager (points-gating, prereqs, no
## double-spend). The picker UI itself is in-tree (playtested); this pins the station's spend logic off-tree.

const PLAYER_PATH := "res://scripts/player/player.gd"

func _perk(pid: StringName, bonuses := {}, reqs := []) -> Perk:
	var p := Perk.new()
	p.id = pid
	p.stat_bonuses = bonuses
	for r in reqs:
		p.requires_perks.append(r)
	return p

func test_unlock_perk_requires_a_point() -> void:
	var lv := LevelUp.new()
	var p = load(PLAYER_PATH).new()
	var pm := PerkManager.new()
	pm.name = &"Perks"
	p.add_child(pm)
	pm.skill_points = 0
	assert_false(lv.unlock_perk(p, _perk(&"tough")), "no points -> refused")
	assert_false(pm.has_perk(&"tough"), "nothing unlocked")
	pm.skill_points = 1
	assert_true(lv.unlock_perk(p, _perk(&"tough")), "a point + unlockable perk -> unlocked")
	assert_eq(pm.skill_points, 0, "the point was spent")
	assert_true(pm.has_perk(&"tough"), "recorded")
	lv.free()
	p.free()

func test_unlock_perk_blocked_by_prereq_does_not_spend() -> void:
	var lv := LevelUp.new()
	var p = load(PLAYER_PATH).new()
	var pm := PerkManager.new()
	pm.name = &"Perks"
	p.add_child(pm)
	pm.skill_points = 1
	assert_false(lv.unlock_perk(p, _perk(&"adv", {}, [&"base"])), "prereq unmet -> refused")
	assert_eq(pm.skill_points, 1, "no point spent on a refused unlock")
	lv.free()
	p.free()

func test_unlock_perk_null_perk_is_safe() -> void:
	var lv := LevelUp.new()
	var p = load(PLAYER_PATH).new()
	assert_false(lv.unlock_perk(p, null), "a null perk is refused, not a crash")
	lv.free()
	p.free()
