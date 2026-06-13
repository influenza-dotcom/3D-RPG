class_name GoapPlanner
extends RefCounted

## Pure A* GOAP planner over a GoapWorldState: given the current state, the available actions, and a goal,
## returns the cheapest ordered list of actions whose effects reach the goal — or an empty Array if the goal is
## already satisfied OR unreachable. No Node, no tree, no side effects → fully off-tree unit-testable (the whole
## reason the AI brain is moving off the manual-playtest-only FSM).
##
## DIRECTION NOTE: this is FORWARD chaining (expand applicable actions from the current state toward the goal),
## with the unmet-goal-fact heuristic, canonical-key dedup (GoapWorldState.key()), and a depth/iteration cap.
## The migration plan sketched backward chaining; forward is functionally equivalent at this action count
## (returns the optimal plan, dedups revisited states, is bounded) and is swappable later behind this same
## plan() / select_goal() API if backward's action-pruning is ever needed at a much larger library.

const MAX_ITERATIONS := 2000  ## backstop so an unsatisfiable goal / huge action set can't hang a frame

## Plan a sequence of actions from `ws` that satisfies `goal`. Returns Array[GoapAction] — empty when the goal
## is ALREADY satisfied OR no plan was found (callers distinguish via goal.satisfied_by(ws)).
static func plan(ws: GoapWorldState, actions: Array, goal: GoapGoal) -> Array:
	if goal.satisfied_by(ws):
		return []
	# Frontier of search nodes {ws, plan, g, f}, kept sorted ascending on f so pop_front() is the best node.
	var frontier: Array = []
	_insert_sorted(frontier, {"ws": ws, "plan": [], "g": 0.0}, float(goal.unmet_count(ws)))
	var best_g: Dictionary = {}  # state-key -> cheapest g reached, to skip worse revisits (needs key())
	var iterations := 0
	while not frontier.is_empty() and iterations < MAX_ITERATIONS:
		iterations += 1
		var node: Dictionary = frontier.pop_front()
		var state: GoapWorldState = node["ws"]
		if goal.satisfied_by(state):
			return node["plan"]
		var k := state.key()
		if best_g.has(k) and float(best_g[k]) <= float(node["g"]):
			continue
		best_g[k] = node["g"]
		for a in actions:
			var action: GoapAction = a
			if not action.available_in(state):
				continue
			var next_state := action.apply_to(state)
			var next_plan: Array = (node["plan"] as Array).duplicate()
			next_plan.append(action)
			var g: float = float(node["g"]) + action.cost(state)
			_insert_sorted(frontier, {"ws": next_state, "plan": next_plan, "g": g}, g + float(goal.unmet_count(next_state)))
	return []  # no plan within the iteration cap

## Pick the goal to pursue: the highest-priority goal (by GoapGoal.priority(ws)) that has a non-empty plan.
## SHORT-CIRCUITS — sorts by priority descending and returns the FIRST feasible goal, so we don't plan all
## goals every replan. Returns null only if NO goal is feasible; callers give an Idle goal an empty-precondition
## action so a plan always exists and the executor can never deadlock.
static func select_goal(ws: GoapWorldState, goals: Array, actions: Array) -> GoapGoal:
	var sorted: Array = goals.duplicate()
	sorted.sort_custom(func(a, b): return (a as GoapGoal).priority(ws) > (b as GoapGoal).priority(ws))
	for g in sorted:
		if not plan(ws, actions, g as GoapGoal).is_empty():
			return g
	return null

## Insert a node keeping the frontier sorted ascending by f (so pop_front() yields the lowest-f node).
static func _insert_sorted(frontier: Array, node: Dictionary, f: float) -> void:
	node["f"] = f
	var i := 0
	while i < frontier.size() and float(frontier[i]["f"]) <= f:
		i += 1
	frontier.insert(i, node)
