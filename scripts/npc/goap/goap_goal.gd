class_name GoapGoal
extends RefCounted

## A GOAP goal: a desired world-state + an AUTHORED priority. Priority is DATA, not a code override — a base
## plus coefficients the executor reads against world-state facts, so a designer makes a coward by raising
## base_priority / temperament_scale in the inspector (via GoapProfile) with no programmer. Pure / off-tree.

var name: StringName = &""
var desired_state: Dictionary = {}
var base_priority: float = 1.0
var hp_scale: float = 0.0           ## priority += hp_scale * (1 - hp_frac) — rises as the NPC is hurt (e.g. Survive)
var temperament_scale: float = 0.0  ## priority += temperament_scale * temperament — a coward weights Survive up

func _init(p_name: StringName = &"", p_priority: float = 1.0, p_desired: Dictionary = {}) -> void:
	name = p_name
	base_priority = p_priority
	desired_state = p_desired.duplicate()

## True when the world-state already satisfies this goal (the planner returns an empty plan in that case, so
## select_goal skips it — there's nothing to pursue).
func satisfied_by(ws: GoapWorldState) -> bool:
	return ws.matches(desired_state)

## Count of desired facts not yet satisfied — the planner's heuristic (admissible while min action cost >= 1).
func unmet_count(ws: GoapWorldState) -> int:
	var n := 0
	for k in desired_state:
		if ws.get_fact(k) != desired_state[k]:
			n += 1
	return n

## Selection priority given the world-state: authored base + authored hp/temperament coefficients against the
## facts (hp_frac in [0,1], temperament in [0,1]). The executor picks the highest-priority FEASIBLE goal.
func priority(ws: GoapWorldState) -> float:
	var hp_frac: float = float(ws.get_fact(&"hp_frac", 1.0))
	var temperament: float = float(ws.get_fact(&"temperament", 0.0))
	return base_priority + hp_scale * (1.0 - hp_frac) + temperament_scale * temperament
