class_name GoapAction
extends RefCounted

## One GOAP action, split into two halves:
##   PLANNING (pure)    — name / preconditions / effects / cost(ws); the planner only ever calls these, so the
##                        whole search stays Node-free and off-tree testable.
##   EXECUTION (host)   — is_runtime_valid / enter / act / exit; overridden by concrete subclasses (under
##                        scripts/npc/goap/actions/) that DELEGATE to the existing npc_*.gd components. The
##                        planner never calls these; the executor does, in-tree.
##
## A "fact" is a StringName key in a GoapWorldState mapping to a value (usually bool, but any Variant).

enum Status { RUNNING, SUCCEEDED, FAILED }

var name: StringName = &""
var preconditions: Dictionary = {}   ## facts that must hold to run (matched against the world-state)
var effects: Dictionary = {}         ## facts the planner assumes set once this action succeeds
## Planner cost. NOT a hardcoded const: a subclass sets its default here, a designer overrides per-archetype via
## GoapProfile.action_cost_overrides, and the default is pinned in test_goap_action_contracts.gd against drift.
var base_cost: float = 1.0

func _init(p_name: StringName = &"", p_cost: float = 1.0, p_pre: Dictionary = {}, p_eff: Dictionary = {}) -> void:
	name = p_name
	base_cost = maxf(p_cost, 0.0)
	preconditions = p_pre.duplicate()
	effects = p_eff.duplicate()

# --- Planning half (pure; the planner calls only these) ---

## Planning cost in the current world-state. Subclasses override to scale (e.g. Pursue by distance); base
## returns the flat cost.
func cost(_ws: GoapWorldState) -> float:
	return base_cost

## True when this action's preconditions hold in `ws`.
func available_in(ws: GoapWorldState) -> bool:
	return ws.matches(preconditions)

## The world-state the planner assumes AFTER this action (a copy with effects merged; `ws` is not mutated).
func apply_to(ws: GoapWorldState) -> GoapWorldState:
	return ws.apply(effects)

# --- Execution half (overridden by concrete subclasses at integration; the planner never calls these) ---

## A runtime feasibility gate beyond the planning preconditions (e.g. a still-valid weapon ref). The one place
## an action may touch the host; default true.
func is_runtime_valid(_host) -> bool:
	return true

## RESERVED — NOT currently invoked. The executor contract deliberately never calls enter/exit (the planner
## doesn't run the execution half, and tick() steps act() directly). Per-frame side-effects (incl. barks /
## telegraphs like "reloading!") go in act(), gated against repetition there. Kept as a forward seam only.
func enter(_host) -> void:
	pass

## RESERVED — NOT currently invoked (same as enter): the executor never calls exit on a plan swap. Any
## cleanup / exit bark ("lost 'em") must live in act(), not here. Kept as a forward seam only.
func exit(_host) -> void:
	pass

## Step the behaviour one frame, delegating to a component; returns a Status. Base no-ops to SUCCEEDED so a
## planning-only action (used in the planner tests) is inert in-tree.
func act(_host, _delta: float) -> int:
	return Status.SUCCEEDED
