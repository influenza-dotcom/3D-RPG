class_name GoapExecutor
extends RefCounted

## Drives an NPC's GOAP brain, replacing npc.gd's `match`: builds a world-state from the host's EXISTING
## sensors, selects a goal + plans, and steps the current action's act() into the host's components. Split so
## the decision logic is unit-testable:
##   PURE (no host / tree)  — setup / decide / current_action / advance: given facts + library, deterministic.
##   IN-TREE (host I/O)     — tick / _build_world_state: exercised only when use_goap (manual playtest).
## Held as a plain RefCounted on the NPC (no new Node); built in npc.gd:_build_components when use_goap, with
## the FSM as the fallback. The seam in npc.gd is wired in the next step; until then this is unreferenced scaffold.

var actions: Array = []        ## Array[GoapAction] — the library (filled per archetype as goals migrate, Phase 3+)
var goals: Array = []          ## Array[GoapGoal]
var plan: Array = []           ## current Array[GoapAction]
var index: int = 0
var current_goal: GoapGoal = null

func setup(p_actions: Array, p_goals: Array) -> void:
	actions = p_actions
	goals = p_goals

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

# --- In-tree execution (host I/O; exercised only when use_goap, manual-playtested) ---

## One AI frame: build the world-state, (re)plan when there's no valid current action, then step it. With an
## empty library (pre-migration) this no-ops — Phase 3 fills the goals/actions. (Replan-cadence throttling +
## stagger arrive with the migrated goals, alongside the GameSettings.npc_ai.goap_* dials.)
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
## rules. Minimal for now (the facts every goal needs); Phase 3 expands it per migrated goal using the proper
## host accessors so each new fact stays correct + off-tree-safe.
func _build_world_state(host) -> GoapWorldState:
	var ws := GoapWorldState.new()
	ws.set_fact(&"has_target", is_instance_valid(host._target))
	ws.set_fact(&"hp_frac", host.hp / maxf(host.max_hp, 1.0))
	return ws
