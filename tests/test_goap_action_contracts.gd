extends GutTest

## The combat actions' PLANNING CONTRACT, checked against the REAL library and the facts an NPC actually senses.
## Nothing here copies a name / cost / precondition / effect literal out of an action's super() call. Instead every
## test runs the shipped vocabulary (GoapLibrary.build_actions / build_goals) through the executor's own sensor
## snapshot (GoapExecutor._build_world_state, fed by a duck-typed host in every perception state x target x gun x
## fleeing combination) and the pure planner, and asserts the properties the brain depends on:
##   - every action is actually PLANNED in some state the NPC can sense (a renamed precondition fact, or an effect no
##     goal wants, leaves a behaviour that silently never runs);
##   - effects are SENTINEL facts the sensor snapshot never writes, so every library goal is reachable in one step
##     but never already satisfied (the self-satisfaction trap that makes plan() return [] and skips the goal);
##   - some goal is feasible in every sensed state (the Hold floor), so the executor can never stall on a null goal;
##   - the gun is the cheaper Engage route and fists the costlier fallback (costs only break ties between routes to
##     the SAME goal, and Engage is the one goal with two routes);
##   - an action's name is the key a designer's cost-override row reaches it by, one row -> exactly one action.
## Pure off-tree: actions/goals are plain RefCounteds and the host is a RefCounted stub (no NPC, no tree, no _ready).

const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")

## Stand-in for the NPC's Perception child: _build_world_state reads only `state`.
class _PerceptionStub:
	extends RefCounted
	var state: int = Perception.State.UNAWARE

## Exactly the host surface GoapExecutor._build_world_state reads (target / hp / temperament / perception / can-fight
## / fleeing). Duck-typed, like the executor's untyped `host` parameter.
class _SensedHostStub:
	extends RefCounted
	var _target: Object = null
	var hp: float = 10.0
	var max_hp: float = 10.0
	var temperament: float = 0.0
	var _perception = null
	var _can_fight: bool = false
	var _fleeing: bool = false
	func _can_fight_with_gun() -> bool:
		return _can_fight
	func is_fleeing() -> bool:
		return _fleeing

## One sensor snapshot. `perception_state` -1 = no Perception child (an unbuilt / tearing-down host).
func _sense(perception_state: int, has_target: bool, can_fight: bool, fleeing: bool) -> GoapWorldState:
	var host := _SensedHostStub.new()
	if perception_state >= 0:
		var p := _PerceptionStub.new()
		p.state = perception_state
		host._perception = p
	if has_target:
		host._target = RefCounted.new()
	host._can_fight = can_fight
	host._fleeing = fleeing
	var ex := GoapExecutor.new()
	var ws: GoapWorldState = ex._build_world_state(host)
	ex = null
	host = null
	return ws

## Every world-state the executor can sense: {no perception child, each Perception.State} x target x gun x fleeing.
## Each entry is {"label": String, "ws": GoapWorldState}.
func _sensed_states() -> Array:
	var perception_states: Array = [-1]
	perception_states.append_array(Perception.State.values())
	var out: Array = []
	for ps in perception_states:
		for has_target in [false, true]:
			for can_fight in [false, true]:
				for fleeing in [false, true]:
					var label := "perception=%s target=%s gun=%s fleeing=%s" % [
						"none" if ps < 0 else Perception.State.keys()[ps], has_target, can_fight, fleeing]
					out.append({"label": label, "ws": _sense(ps, has_target, can_fight, fleeing)})
	return out

## The union of every fact key any sensed world-state carries.
func _sensed_fact_keys(sensed: Array) -> Dictionary:
	var keys := {}
	for entry in sensed:
		var ws: GoapWorldState = entry["ws"]
		for k in ws.facts:
			keys[k] = true
	return keys

func _goal_named(goals: Array, goal_name: StringName) -> GoapGoal:
	for g in goals:
		if (g as GoapGoal).name == goal_name:
			return g
	return null

func _plan_cost(ws: GoapWorldState, plan: Array) -> float:
	var total := 0.0
	for a in plan:
		total += (a as GoapAction).cost(ws)
	return total

func test_every_action_is_planned_in_some_state_the_npc_can_sense() -> void:
	# An action whose precondition names a fact the sensors never write (a rename), or asks for a value they never
	# produce, or whose effect satisfies no library goal, is dead weight: the NPC never runs that behaviour and no
	# error says so. Each action must be the one-step plan for some library goal in some sensed state.
	var actions: Array = GoapLibrary.build_actions()
	var goals: Array = GoapLibrary.build_goals()
	var sensed: Array = _sensed_states()
	var sensed_keys := _sensed_fact_keys(sensed)
	assert_gt(sensed_keys.size(), 0, "the sensor snapshot must produce facts at all, or every check below is vacuous")
	for a in actions:
		var action: GoapAction = a
		for k in action.preconditions:
			assert_true(sensed_keys.has(k),
				"%s needs fact '%s', which _build_world_state never senses -> the NPC can never run %s" % [action.name, k, action.name])
		var planned_for := ""
		for entry in sensed:
			var ws: GoapWorldState = entry["ws"]
			for g in goals:
				var plan: Array = GoapPlanner.plan(ws, actions, g)
				if plan.size() == 1 and plan[0] == action:
					planned_for = "%s when %s" % [(g as GoapGoal).name, entry["label"]]
					break
			if planned_for != "":
				break
		assert_true(planned_for != "",
			"%s is never planned for any library goal in any sensed state -> that NPC behaviour silently never runs" % action.name)

func test_no_action_effect_is_a_fact_the_npc_senses() -> void:
	# The sentinel seam (goap_executor.gd @seam): effects are set ONLY by an action and wanted ONLY by its goal. If the
	# sensor snapshot ever wrote one, that goal could start out satisfied and its behaviour would be skipped.
	var sensed_keys := _sensed_fact_keys(_sensed_states())
	assert_gt(sensed_keys.size(), 0, "control: the sensor snapshot really produced facts to compare against")
	for a in GoapLibrary.build_actions():
		var action: GoapAction = a
		assert_gt(action.effects.size(), 0, "%s has no effect, so no goal can ever be reached through it" % action.name)
		for k in action.effects:
			assert_false(sensed_keys.has(k),
				"%s's effect '%s' is also sensed by _build_world_state -> its goal can be pre-satisfied and skipped" % [action.name, k])

func test_every_library_goal_is_reachable_in_one_step_but_never_already_satisfied() -> void:
	# The shipped goals (not the local copies the selection tests use) against the shipped actions: in NO sensed state
	# may a goal already hold (plan() would return [] and select_goal would skip it), and in SOME sensed state it must
	# plan. Every plan is a single step, which GoapGoal.unmet_count's heuristic relies on while costs sit below 1.
	var actions: Array = GoapLibrary.build_actions()
	var goals: Array = GoapLibrary.build_goals()
	var sensed: Array = _sensed_states()
	for g in goals:
		var goal: GoapGoal = g
		var pre_satisfied: Array = []
		var multi_step: Array = []
		var reachable := false
		for entry in sensed:
			var ws: GoapWorldState = entry["ws"]
			if goal.satisfied_by(ws):
				pre_satisfied.append(entry["label"])
				continue
			var plan: Array = GoapPlanner.plan(ws, actions, goal)
			if plan.is_empty():
				continue
			reachable = true
			if plan.size() != 1:
				multi_step.append("%s (%d steps)" % [entry["label"], plan.size()])
		assert_eq(pre_satisfied, [],
			"goal %s is already satisfied by the sensed facts in these states, so the NPC never pursues it" % goal.name)
		assert_true(reachable, "goal %s is never reachable from any sensed state: no action's effect satisfies it" % goal.name)
		assert_eq(multi_step, [], "goal %s needs a multi-step plan, breaking the single-step heuristic assumption" % goal.name)

func test_some_goal_is_feasible_in_every_sensed_state() -> void:
	# The Hold floor has no preconditions, so the Idle goal always plans and select_goal can never hand the executor a
	# null goal (a null goal idles the whole brain: no wander, no scavenge, no reaction). Holds for every sensed state,
	# including a host with no Perception child and a fleeing NPC that has noticed nothing.
	var actions: Array = GoapLibrary.build_actions()
	var goals: Array = GoapLibrary.build_goals()
	var stalled: Array = []
	for entry in _sensed_states():
		var ws: GoapWorldState = entry["ws"]
		if GoapPlanner.select_goal(ws, goals, actions) == null:
			stalled.append(entry["label"])
	assert_eq(stalled, [], "no goal is feasible in these sensed states, so the NPC's brain stalls there")

func test_engaging_with_a_gun_is_priced_below_engaging_with_fists() -> void:
	# Costs only break ties between routes to the same goal, and Engage is the one goal with two routes. The design
	# makes the gun the preferred route and fists the costlier fallback, so if the armed/unarmed gate ever let both
	# run, the planner would still pick the gun.
	var actions: Array = GoapLibrary.build_actions()
	var engage: GoapGoal = _goal_named(GoapLibrary.build_goals(), &"Engage")
	assert_true(engage != null, "the library must build an Engage goal")
	if engage == null:
		return
	var armed_ws := _sense(Perception.State.ALERTED, true, true, false)
	var unarmed_ws := _sense(Perception.State.ALERTED, true, false, false)
	var armed_plan: Array = GoapPlanner.plan(armed_ws, actions, engage)
	var unarmed_plan: Array = GoapPlanner.plan(unarmed_ws, actions, engage)
	assert_false(armed_plan.is_empty(), "an ALERTED NPC that can fight with a gun must have an Engage plan")
	assert_false(unarmed_plan.is_empty(), "an ALERTED NPC that cannot fight with a gun must still have an Engage plan")
	if armed_plan.is_empty() or unarmed_plan.is_empty():
		return
	assert_ne((armed_plan[0] as GoapAction).name, (unarmed_plan[0] as GoapAction).name,
		"armed and unarmed NPCs must engage through different actions")
	assert_lt(_plan_cost(armed_ws, armed_plan), _plan_cost(unarmed_ws, unarmed_plan),
		"engaging with a gun must cost less than falling back to fists, or the planner would prefer punching")

func test_a_cost_row_for_each_registered_action_name_retunes_exactly_that_action() -> void:
	# The action name is the key a designer's GoapProfile cost row (picked from GoapLibrary.action_names()) reaches the
	# action by. Each registered name must retune exactly one built action, the one carrying that name: a duplicated
	# name would retune two behaviours at once, and a renamed action would silently ignore the designer's row.
	var defaults: Array = GoapLibrary.build_actions()
	for action_name in GoapLibrary.action_names():
		var row := GoapActionCost.new()
		row.action = action_name
		row.cost = 7.5
		var prof := GoapProfile.new()
		prof.action_cost_overrides.assign([row])
		var built: Array = GoapLibrary.build_actions(prof)
		var retuned: Array = []
		for i in built.size():
			var b: GoapAction = built[i]
			var d: GoapAction = defaults[i]
			if not is_equal_approx(b.base_cost, d.base_cost):
				retuned.append(String(b.name))
		assert_eq(retuned, [action_name],
			"a cost row for '%s' must retune exactly that one action (retuned: %s)" % [action_name, retuned])
		prof = null
		row = null
