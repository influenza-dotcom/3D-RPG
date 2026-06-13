extends GutTest

## GoapExecutor — the NPC's GOAP brain. Tests cover only the PURE decision/plan-stepping core (setup / decide /
## current_action / advance), built with hand-made goals/actions — no host, no tree. The in-tree tick() /
## _build_world_state() (host I/O) are manual-playtested once the npc.gd seam is wired and goals are migrated.

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

func test_empty_library_yields_no_goal() -> void:
	# The inert Phase-2 scaffold state: no migrated goals/actions -> no goal, no action (the seam is in place
	# but does nothing until Phase 3 fills the library).
	var ex := _ex([], [])
	ex.decide(GoapWorldState.new({}))
	assert_null(ex.current_goal, "empty library -> no goal selected")
	assert_null(ex.current_action())
	ex = null
