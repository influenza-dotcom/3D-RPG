extends GutTest

## Rank 29a: XpSettings curve math + Player.add_xp point grants. All off-tree (add_xp's autosave is a no-op
## off-tree per GameState.autosave's is_inside_tree guard); pure logic.

const PLAYER_PATH := "res://scripts/player/player.gd"

func test_xp_to_reach_monotonic_default_ramp() -> void:
	var s := XpSettings.new()
	s.base_xp = 100.0
	s.per_level_growth = 50.0
	assert_eq(s.xp_to_reach(0), 0.0, "level 0 needs 0 xp")
	assert_almost_eq(s.xp_to_reach(1), 100.0, 0.001, "level 1 = base_xp")
	assert_almost_eq(s.xp_to_reach(2), 250.0, 0.001, "level 2 = 100*2 + 50*2*1/2")
	assert_true(s.xp_to_reach(3) > s.xp_to_reach(2), "monotonic rising")
	s = null

func test_level_for_xp_thresholds() -> void:
	var s := XpSettings.new()
	s.base_xp = 100.0
	s.per_level_growth = 50.0
	assert_eq(s.level_for_xp(0.0), 0, "no xp -> level 0")
	assert_eq(s.level_for_xp(99.0), 0, "just under threshold stays level 0")
	assert_eq(s.level_for_xp(100.0), 1, "exactly the threshold levels up")
	assert_eq(s.level_for_xp(249.0), 1, "between 1 and 2")
	assert_eq(s.level_for_xp(250.0), 2, "reaches level 2")
	s = null

func test_level_for_xp_degenerate_ramp_terminates() -> void:
	# A zero ramp (base_xp 0, no growth) must not infinite-loop: the `> previous` guard stops it at 0.
	var s := XpSettings.new()
	s.base_xp = 0.0
	s.per_level_growth = 0.0
	assert_eq(s.level_for_xp(500.0), 0, "a flat-zero ramp grants no levels and returns immediately")
	s = null

func test_add_xp_grants_points_and_levels() -> void:
	var prev: XpSettings = GameSettings.xp
	var s := XpSettings.new()
	s.base_xp = 100.0
	s.per_level_growth = 0.0  # flat 100/level for a clean threshold
	s.points_per_level = 1
	GameSettings.xp = s
	var p = load(PLAYER_PATH).new()
	assert_eq(p.add_xp(250.0), 2, "250 xp with 100/level -> 2 levels")
	assert_eq(p.level, 2, "level cached")
	var pm = p._perk_manager()
	assert_eq(pm.skill_points, 2, "two levels -> two skill points")
	assert_eq(pm.points_earned, 2, "earned points track cumulatively (for the respec refund)")
	assert_eq(p.add_xp(0.0), 0, "zero xp is a no-op")
	assert_eq(p.add_xp(-5.0), 0, "negative xp is a no-op")
	GameSettings.xp = prev  # restore the shared autoload for later tests
	p.free()
	s = null

## Rank 29b: the pure seams of the kill/quest XP hooks (the in-tree wiring through _on_died /
## _grant_quest_rewards is playtest-verified per the repo convention).
func test_quest_reward_xp_default() -> void:
	var q := Quest.new()
	assert_eq(q.reward_xp, 0.0, "reward_xp defaults to 0 (no XP reward)")
	q = null

func test_xp_settings_per_kill_default_nonneg() -> void:
	var s := XpSettings.new()
	assert_true(s.xp_per_kill >= 0.0, "xp_per_kill is non-negative")
	s = null
