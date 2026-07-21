class_name GoapExecutor
extends RefCounted

## @system NPC Brain
## @seam tick() replans only when the current action is null/invalid, else steps act(); FAILED drops the plan; _build_world_state never senses sentinel facts.
## @risk If _build_world_state senses a sentinel fact, its goal self-satisfies -> plan()=[] -> select_goal skips it, so that behaviour silently never runs.
## @risk decide() resets index=0, so if tick() replanned every frame a multi-step plan (reload->shoot) would never advance past step 0 - silent, no error.
## @risk advance() must drop the plan on FAILED (goap_executor.gd:42-45), else a still-valid failing action is re-stepped every tick - the NPC sticks, no error.
## @test res://tests/test_goap_executor.gd
## @test res://tests/test_goap_combat_brain.gd
## @test res://tests/test_goap_combat_selection.gd
## Drives an NPC's GOAP brain: builds a world-state from the host's EXISTING sensors, selects a goal + plans,
## and steps the current action's act() into the host's components. Split so
## the decision logic is unit-testable:
##   PURE (no host / tree)  — setup / decide / current_action / advance: given facts + library, deterministic.
##   IN-TREE (host I/O)     — tick / _build_world_state: exercised in-tree on every NPC (manual playtest).
## Held as a plain RefCounted on the NPC (no new Node); built in npc.gd:_build_components for every NPC. The
## seam in npc.gd:_physics_process ticks it as the sole AI decision layer.

var actions: Array = []        ## Array[GoapAction] — the runtime action library for this NPC archetype.
var goals: Array = []          ## Array[GoapGoal]
var plan: Array = []           ## current Array[GoapAction]
var index: int = 0
var current_goal: GoapGoal = null

func setup(p_actions: Array, p_goals: Array) -> void:
	actions = p_actions
	goals = p_goals

## NPC-pooling reuse reset (NpcPool): drop the previous life's plan so the very first post-reuse tick() sees
## current_action()==null and replans from freshly-built world facts. Do NOT rely on tick()'s self-heal — it only
## replans when the current action is null/invalid, so a stale-but-still-valid mid-plan action would step for a
## frame or more on the reused host. Leaves `actions`/`goals` (the archetype library, set once in setup()) intact.
func reset_for_reuse() -> void:
	plan = []
	index = 0
	current_goal = null

# --- Pure decision + plan-stepping (no host / tree — unit-tested) ---

## (Re)select the highest-priority feasible goal and compute its plan for `ws`, resetting the step index.
## Deterministic: same facts + library -> same goal + plan.
func decide(ws: GoapWorldState) -> void:
	current_goal = GoapPlanner.select_goal(ws, goals, actions)
	plan = GoapPlanner.plan(ws, actions, current_goal) if current_goal != null else []
	index = 0

## The action being stepped right now, or null when the plan is empty / exhausted.
func current_action() -> GoapAction:
	if index >= 0 and index < plan.size():
		return plan[index] as GoapAction
	return null

## Advance after the current action reports a Status: SUCCEEDED -> next step; FAILED -> drop the plan (forces a
## replan next tick). Returns true while a plan is still in progress.
func advance(status: int) -> bool:
	if status == GoapAction.Status.SUCCEEDED:
		index += 1
	elif status == GoapAction.Status.FAILED:
		plan = []
		index = 0
		return false
	return index < plan.size()

# --- In-tree execution (host I/O; exercised in-tree on every NPC, manual-playtested) ---

## One AI frame: build the world-state, (re)plan when there's no valid current action, then step it. With an
## empty library this no-ops; npc.gd currently supplies the shipped goals/actions during setup.
func tick(host, delta: float) -> void:
	var action := current_action()
	if action == null or not action.is_runtime_valid(host):
		decide(_build_world_state(host))
		action = current_action()
	if action == null:
		return
	advance(action.act(host, delta))

## Snapshot the host's sensors into a GoapWorldState. Reads are explicit-typed / plain `=` (never `:=` off a
## host chain) and deep cross-component reads stay cached/guarded — per the project's host-Variant + duck-typed
## rules. Senses the facts the goals select on: has_target / hp_frac, the three COMBAT perception
## states (a plain field read off the always-present _perception child — no get_tree, off-tree-safe — null-
## guarded so an unbuilt/teardown host stays neutral, i.e. only the Idle floor feasible), and can_fight_with_gun
## (the armed/unarmed gate: ammo OR a spare clip, NOT just is_armed).
##
## SENTINEL FACTS (idle_done / threat_faced / target_engaged / spot_searched) are deliberately NEVER sensed
## here. Each is set ONLY as an action's effect and wanted ONLY as its goal's desired_state, so the goal is
## never pre-satisfied (which would make plan() return [] and select_goal skip it — the trap that sank the
## naive has_target-keyed designs) yet is reachable the moment its action's perception precondition holds.
func _build_world_state(host) -> GoapWorldState:
	var ws := GoapWorldState.new()
	ws.set_fact(&"has_target", is_instance_valid(host._target))
	ws.set_fact(&"hp_frac", host.hp / maxf(host.max_hp, 1.0))
	# temperament [0..1] (npc.gd:253) -> the dynamic-priority knob: a goal's temperament_scale weights it by this
	# (a coward weights Survive up). Always present on the host; default 0.0 = fearless leaves priority unchanged.
	ws.set_fact(&"temperament", host.temperament)
	# Perception state -> the combat goals' selection key. Plain field read off the _perception child; the null
	# guard keeps an unbuilt host neutral (all three false -> only the Idle floor is feasible).
	var pstate: int = -1
	if host._perception != null:
		pstate = host._perception.state
	ws.set_fact(&"state_detecting", pstate == Perception.State.DETECTING)
	ws.set_fact(&"state_alerted", pstate == Perception.State.ALERTED)
	ws.set_fact(&"state_investigating", pstate == Perception.State.INVESTIGATING)
	ws.set_fact(&"can_fight_with_gun", host._can_fight_with_gun())
	# Flee facts. is_fleeing covers the FLEE archetype AND the temperament runtime-flip (host.is_fleeing reads
	# threat_response). threat_noticed = any non-UNAWARE state: a fleer bolts only while it still has something
	# to run from; fleeing + UNAWARE falls back to the Idle floor.
	var noticed: bool = pstate == Perception.State.DETECTING or pstate == Perception.State.ALERTED or pstate == Perception.State.INVESTIGATING
	ws.set_fact(&"threat_noticed", noticed)
	ws.set_fact(&"is_fleeing", host.is_fleeing())
	return ws
