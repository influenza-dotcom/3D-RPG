extends GutTest

## GoapExecutor — the NPC's GOAP brain. Tests cover the PURE decision/plan-stepping core (setup / decide /
## current_action / advance) with hand-made goals/actions, AND _build_world_state via a duck-typed recording
## host stub (it only reads host fields — no get_tree, off-tree-safe). The in-tree tick() stepping (which drives
## the real component children) stays manual-playtest.

class _PerceptionStub:
	extends RefCounted
	var state: int = Perception.State.UNAWARE
	var last_known_position: Vector3 = Vector3.ZERO

## Minimal host for _build_world_state: the fields/method it reads. Duck-typed (executor takes an untyped host).
class _CombatHostStub:
	extends RefCounted
	var _target: Object = RefCounted.new()  # is_instance_valid -> true by default
	var hp: float = 10.0
	var max_hp: float = 10.0
	var _perception = _PerceptionStub.new()
	var _can_fight: bool = true
	var _fleeing: bool = false
	func _can_fight_with_gun() -> bool:
		return _can_fight
	func is_fleeing() -> bool:
		return _fleeing

func _ex(actions: Array, goals: Array) -> GoapExecutor:
	var ex := GoapExecutor.new()
	ex.setup(actions, goals)
	return ex

func test_decide_selects_goal_and_plans() -> void:
	var shoot := GoapAction.new(&"shoot", 1.0, {&"has_target": true}, {&"target_dead": true})
	var hold := GoapAction.new(&"hold", 0.1, {}, {&"idle_done": true})  # the always-feasible floor
	var engage := GoapGoal.new(&"engage", 2.0, {&"target_dead": true})
	var idle := GoapGoal.new(&"idle", 0.1, {&"idle_done": true})
	var ex := _ex([shoot, hold], [idle, engage])
	ex.decide(GoapWorldState.new({&"has_target": true}))
	assert_eq(ex.current_goal.name, &"engage", "highest-priority feasible goal chosen")
	assert_eq(ex.current_action().name, &"shoot", "and its first action is current")
	ex = null

func test_advance_steps_through_plan_then_completes() -> void:
	var reload := GoapAction.new(&"reload", 1.0, {&"has_ammo": false}, {&"has_ammo": true})
	var shoot := GoapAction.new(&"shoot", 1.0, {&"has_ammo": true}, {&"target_dead": true})
	var ex := _ex([reload, shoot], [GoapGoal.new(&"kill", 1.0, {&"target_dead": true})])
	ex.decide(GoapWorldState.new({&"has_ammo": false}))
	assert_eq(ex.current_action().name, &"reload", "first step")
	assert_true(ex.advance(GoapAction.Status.SUCCEEDED), "still in progress after step 1")
	assert_eq(ex.current_action().name, &"shoot", "advanced to step 2")
	assert_false(ex.advance(GoapAction.Status.SUCCEEDED), "plan complete after the last step")
	assert_null(ex.current_action(), "no current action once the plan is exhausted")
	ex = null

func test_failed_action_drops_plan_to_force_replan() -> void:
	var shoot := GoapAction.new(&"shoot", 1.0, {&"has_target": true}, {&"target_dead": true})
	var ex := _ex([shoot], [GoapGoal.new(&"kill", 1.0, {&"target_dead": true})])
	ex.decide(GoapWorldState.new({&"has_target": true}))
	assert_false(ex.advance(GoapAction.Status.FAILED), "FAILED ends the current plan")
	assert_null(ex.current_action(), "no current action after a failure -> tick() replans next frame")
	ex = null

func test_idle_floor_selects_hold_when_nothing_else_feasible() -> void:
	# Phase-3 step 1: the migrated Idle goal + GoapActionHold are the always-feasible floor. With no target the
	# executor selects Idle and steps Hold, which stays RUNNING (holding is a steady state, never SUCCEEDED).
	var ex := _ex([GoapActionHold.new()], [GoapGoal.new(&"Idle", 0.1, {&"idle_done": true})])
	ex.decide(GoapWorldState.new({&"has_target": false}))
	assert_eq(ex.current_goal.name, &"Idle", "Idle is the feasible floor when there's nothing to fight")
	assert_eq(ex.current_action().name, &"Hold", "and Hold is its single satisfying action")
	ex = null

func test_build_world_state_senses_perception_and_combat_facts() -> void:
	# Phase-3 (Engage substep 0): the combat selection facts, sensed off _perception + _can_fight_with_gun.
	var host := _CombatHostStub.new()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = true
	var ex := GoapExecutor.new()
	var ws := ex._build_world_state(host)
	assert_true(ws.get_fact(&"has_target"), "valid _target -> has_target")
	assert_true(ws.get_fact(&"state_alerted"), "ALERTED -> state_alerted")
	assert_false(ws.get_fact(&"state_detecting"), "and not the other states")
	assert_false(ws.get_fact(&"state_investigating"))
	assert_true(ws.get_fact(&"can_fight_with_gun"), "armed + ammo -> can_fight_with_gun")
	assert_true(ws.get_fact(&"threat_noticed"), "ALERTED is a noticed state")
	assert_false(ws.get_fact(&"is_fleeing"), "not fleeing by default")
	assert_almost_eq(float(ws.get_fact(&"hp_frac")), 1.0, 0.001, "full hp -> hp_frac 1.0")
	ex = null
	host = null

func test_build_world_state_neutral_without_perception() -> void:
	# Unbuilt / teardown host: the null guard keeps every combat state false so only the Idle floor is feasible.
	var host := _CombatHostStub.new()
	host._perception = null
	host._target = null
	host._can_fight = false
	var ex := GoapExecutor.new()
	var ws := ex._build_world_state(host)
	assert_false(ws.get_fact(&"has_target"), "no target")
	assert_false(ws.get_fact(&"state_detecting"), "no perception -> all combat states false")
	assert_false(ws.get_fact(&"state_alerted"))
	assert_false(ws.get_fact(&"state_investigating"))
	assert_false(ws.get_fact(&"can_fight_with_gun"))
	assert_false(ws.get_fact(&"threat_noticed"), "no perception -> nothing noticed (fleeing would fall to idle)")
	assert_false(ws.get_fact(&"is_fleeing"))
	ex = null
	host = null

func test_build_world_state_threat_noticed_across_states() -> void:
	# threat_noticed = any non-UNAWARE state (the Flee precondition). The other tests cover only ALERTED and the
	# null-perception case; pin DETECTING/INVESTIGATING true and UNAWARE-with-a-valid-perception-child false (so a
	# fleer that loses the threat falls to the Idle floor, not Flee).
	var host := _CombatHostStub.new()
	var ex := GoapExecutor.new()
	host._perception.state = Perception.State.DETECTING
	assert_true(ex._build_world_state(host).get_fact(&"threat_noticed"), "DETECTING is noticed")
	host._perception.state = Perception.State.INVESTIGATING
	assert_true(ex._build_world_state(host).get_fact(&"threat_noticed"), "INVESTIGATING is noticed")
	host._perception.state = Perception.State.UNAWARE
	assert_false(ex._build_world_state(host).get_fact(&"threat_noticed"), "UNAWARE (with a valid perception child) is NOT noticed")
	ex = null
	host = null

func test_detect_goal_selected_in_detecting_state() -> void:
	# Proves the sentinel pairing: Detect goal {threat_faced} is ACHIEVED by GoapActionDetect (effect
	# {threat_faced}, pre {state_detecting}). threat_faced is never sensed -> the goal never self-satisfies (so
	# plan() is non-empty, not the [] trap), and forward A* reaches it via Detect. Out of DETECTING, Detect is
	# infeasible (precondition) and the Idle floor wins -- exactly the FSM DETECTING-vs-UNAWARE dispatch.
	var ex := _ex([GoapActionDetect.new(), GoapActionHold.new()],
		[GoapGoal.new(&"Idle", 0.1, {&"idle_done": true}), GoapGoal.new(&"Detect", 0.3, {&"threat_faced": true})])
	ex.decide(GoapWorldState.new({&"state_detecting": true}))
	assert_eq(ex.current_goal.name, &"Detect", "DETECTING -> Detect feasible + outranks Idle")
	assert_eq(ex.current_action().name, &"Detect", "and Detect is its achieving action")
	ex.decide(GoapWorldState.new({&"state_detecting": false}))
	assert_eq(ex.current_goal.name, &"Idle", "not detecting -> Detect infeasible, Idle floor wins")
	assert_eq(ex.current_action().name, &"Hold")
	ex = null

func test_investigate_selected_in_investigating_state_without_a_target() -> void:
	# Phase 5b: the existing Investigate action also covers the NO-TARGET stealth investigation — its act walks
	# Perception.last_known_position (never derefs _target), so a stimulus that sets INVESTIGATING (a noise/body,
	# via npc._react_unaware) routes to Investigate with no target present. state_investigating alone drives it.
	var ex := _ex([GoapActionSearch.new(), GoapActionHold.new()],
		[GoapGoal.new(&"Idle", 0.1, {&"idle_done": true}), GoapGoal.new(&"Investigate", 0.4, {&"spot_searched": true})])
	ex.decide(GoapWorldState.new({&"state_investigating": true, &"has_target": false}))
	assert_eq(ex.current_goal.name, &"Investigate", "INVESTIGATING (even with no target) -> Investigate outranks Idle")
	assert_eq(ex.current_action().name, &"Investigate", "and Investigate is its achieving action")
	ex.decide(GoapWorldState.new({&"state_investigating": false, &"has_target": false}))
	assert_eq(ex.current_goal.name, &"Idle", "investigation over -> Idle floor")
	ex = null

func test_empty_library_yields_no_goal() -> void:
	# The inert Phase-2 scaffold state: no migrated goals/actions -> no goal, no action (the seam is in place
	# but does nothing until Phase 3 fills the library).
	var ex := _ex([], [])
	ex.decide(GoapWorldState.new({}))
	assert_null(ex.current_goal, "empty library -> no goal selected")
	assert_null(ex.current_action())
	ex = null
