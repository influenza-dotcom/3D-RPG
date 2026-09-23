extends GutTest

## Rank 29a: XpSettings curve math + Player.add_xp point grants. All off-tree (add_xp's autosave is a no-op
## off-tree per GameState.autosave's is_inside_tree guard); pure logic.

const PLAYER_PATH := "res://scripts/player/player.gd"
const QUESTTRACKER_PATH := "res://managers/QuestTracker.gd"

## The reward hooks look the HUMAN player up through GameState.live_player / NPC._real_player; these stand in for
## those two lookups so the REAL QuestTracker / NpcMortality code runs against a real (off-tree) Player.
class StubGameState extends Node:
	var player: Node = null
	func live_player() -> Node:
		return player
	func autosave_world_state() -> void:
		pass
	func get_flag(_flag: StringName, fallback: Variant = false) -> Variant:
		return fallback
	func set_flag(_flag: StringName, _value: Variant = true) -> void:
		pass

class StubKillerHost extends Node:
	var player: Node = null
	func _real_player() -> Node:
		return player

var _prev_xp: XpSettings
var _prev_xp_gain_mult: float

func before_each() -> void:
	_prev_xp = GameSettings.xp
	_prev_xp_gain_mult = GameSettings.difficulty.xp_gain_mult

func after_each() -> void:
	# Restore the shared autoloads even if a test bailed mid-way (a leaked swap pollutes every later file).
	GameSettings.xp = _prev_xp
	GameSettings.difficulty.xp_gain_mult = _prev_xp_gain_mult

## A flat 100-xp-per-level ramp at Normal difficulty, so XP totals and levels are hand-checkable.
func _flat_xp(per_kill: float = 0.0) -> XpSettings:
	var s := XpSettings.new()
	s.base_xp = 100.0
	s.per_level_growth = 0.0
	s.points_per_level = 1
	s.xp_per_kill = per_kill
	GameSettings.xp = s
	GameSettings.difficulty.xp_gain_mult = 1.0
	return s

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
	_flat_xp()  # flat 100/level, 1 point/level, xp_gain_mult 1.0 (after_each restores the autoloads)
	var p = load(PLAYER_PATH).new()
	assert_eq(p.add_xp(250.0), 2, "250 xp with 100/level -> 2 levels")
	assert_eq(p.level, 2, "level cached")
	var pm = p._perk_manager()
	assert_eq(pm.skill_points, 2, "two levels -> two skill points")
	assert_eq(pm.points_earned, 2, "earned points track cumulatively (for the respec refund)")
	watch_signals(p)
	assert_eq(p.add_xp(0.0), 0, "a zero grant gains no level")
	assert_signal_not_emitted(p, "xp_changed",
		"a zero grant is a no-op: add_xp returns before touching xp, so no xp_changed refresh fires")
	# -60 is big enough that, if it were applied, 250 -> 190 would drop back below the level-2 threshold (200).
	assert_eq(p.add_xp(-60.0), 0, "a negative grant is refused, so it reports no level change (not a level LOST)")
	assert_almost_eq(p.xp, 250.0, 0.001, "a negative grant never drains the player's XP (it stays at 250, not 190)")
	assert_signal_not_emitted(p, "xp_changed", "a refused negative grant fires no xp_changed refresh either")
	# Control: in the same setup the smallest POSITIVE grant does get past the guard.
	assert_eq(p.add_xp(0.5), 0, "half a point on 250 xp crosses no level")
	assert_almost_eq(p.xp, 250.5, 0.001, "control: a positive grant, however small, is added to xp")
	assert_signal_emit_count(p, "xp_changed", 1, "control: the positive grant fires exactly one xp_changed")
	p.free()

## ML-5: the difficulty xp_gain_mult scales XP GRANTS. A save-load restore assigns Player.xp directly (not via
## add_xp), so only earned XP scales. Inert at the 1.0 default; restore the shared autoloads after.
func test_add_xp_scales_with_difficulty() -> void:
	var prev: XpSettings = GameSettings.xp
	var s := XpSettings.new()
	s.base_xp = 1000.0  # high threshold so a 100-xp grant never crosses a level (keeps this about the raw xp)
	s.per_level_growth = 0.0
	GameSettings.xp = s
	var saved_mult: float = GameSettings.difficulty.xp_gain_mult
	GameSettings.difficulty.xp_gain_mult = 2.0
	var p = load(PLAYER_PATH).new()
	p.add_xp(100.0)
	assert_almost_eq(p.xp, 200.0, 0.001, "xp_gain_mult 2.0 doubles a 100-xp grant to 200")
	GameSettings.difficulty.xp_gain_mult = saved_mult  # restore the shared autoload
	GameSettings.xp = prev
	p.free()
	s = null

## Rank 29b: the kill / quest XP hooks, driven through the REAL QuestTracker and NpcMortality code into a real
## Player.add_xp (only the two live-player lookups are stubbed).
func test_completing_a_quest_pays_its_reward_xp_and_a_quest_without_one_pays_none() -> void:
	_flat_xp()
	var gs := StubGameState.new()
	add_child_autofree(gs)
	var p = load(PLAYER_PATH).new()
	gs.player = p
	var qt = load(QUESTTRACKER_PATH).new()
	qt.game_state = gs
	var paid := Quest.new()
	paid.id = &"xp_curve_paid_quest"
	paid.auto_complete = false
	paid.reward_xp = 150.0
	qt.start_quest(paid)
	assert_almost_eq(p.xp, 0.0, 0.001, "starting a quest pays nothing up front")
	qt.complete_quest(paid.id)
	assert_almost_eq(p.xp, 150.0, 0.001, "turning in a quest pays exactly its reward_xp to the player")
	assert_eq(p.level, 1, "...and that XP counts toward levelling (150 xp at 100/level = level 1)")
	qt.complete_quest(paid.id)
	assert_almost_eq(p.xp, 150.0, 0.001, "a quest already turned in can't be cashed in a second time")
	var unrewarded := Quest.new()  # reward_xp left at whatever an author who never touched it gets
	unrewarded.id = &"xp_curve_unrewarded_quest"
	unrewarded.auto_complete = false
	qt.start_quest(unrewarded)
	qt.complete_quest(unrewarded.id)
	assert_almost_eq(p.xp, 150.0, 0.001,
		"a quest authored without an XP reward pays NO xp — a fresh Quest must not grant a hidden default")
	qt.free()
	p.free()


func test_a_failed_quest_pays_no_reward_xp() -> void:
	_flat_xp()
	var gs := StubGameState.new()
	add_child_autofree(gs)
	var p = load(PLAYER_PATH).new()
	gs.player = p
	var qt = load(QUESTTRACKER_PATH).new()
	qt.game_state = gs
	var q := Quest.new()
	q.id = &"xp_curve_failed_quest"
	q.auto_complete = false
	q.reward_xp = 150.0
	qt.start_quest(q)
	qt.fail_quest(q.id)
	assert_almost_eq(p.xp, 0.0, 0.001, "failing a quest pays none of its reward_xp")
	qt.complete_quest(q.id)
	assert_almost_eq(p.xp, 0.0, 0.001, "...and a failed quest can't be turned in afterwards for the XP")
	qt.free()
	p.free()


func test_a_kill_pays_xp_per_kill_and_zero_or_negative_pays_nothing() -> void:
	var s := _flat_xp(40.0)
	var host := StubKillerHost.new()
	add_child_autofree(host)
	var p = load(PLAYER_PATH).new()
	host.player = p
	var mortality := NpcMortality.new()
	mortality.host = host
	mortality.award_kill_xp()
	assert_almost_eq(p.xp, 40.0, 0.001, "a kill pays the player exactly xp_per_kill")
	s.xp_per_kill = 0.0
	mortality.award_kill_xp()
	assert_almost_eq(p.xp, 40.0, 0.001, "xp_per_kill 0 is the off-switch: kills pay no XP")
	s.xp_per_kill = -25.0
	mortality.award_kill_xp()
	assert_almost_eq(p.xp, 40.0, 0.001, "a mis-authored NEGATIVE xp_per_kill never drains the player's XP")
	# Guard control: the same kill from a victim that is NOT in the tree (a bare test NPC) pays nothing.
	s.xp_per_kill = 40.0
	var off_tree_host := StubKillerHost.new()
	off_tree_host.player = p
	mortality.host = off_tree_host
	mortality.award_kill_xp()
	assert_almost_eq(p.xp, 40.0, 0.001, "an off-tree victim pays no kill XP (no live world to credit)")
	mortality.host = host
	mortality.award_kill_xp()
	assert_almost_eq(p.xp, 80.0, 0.001, "...while the in-tree victim with the same knob pays again")
	off_tree_host.free()
	mortality.free()
	p.free()
