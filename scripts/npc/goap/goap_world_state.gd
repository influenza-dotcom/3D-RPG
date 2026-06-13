class_name GoapWorldState
extends RefCounted

## The AI blackboard the planner reasons over: a flat Dictionary of facts (StringName -> Variant, usually bool).
## At runtime the GoapExecutor fills one from the EXISTING sensors (Perception / NpcTargeting / morale / ammo);
## the planner only reads + copies it — no Node reference, so the whole search is side-effect-free and fully
## off-tree testable (the reason the AI brain is moving to GOAP).

var facts: Dictionary = {}

func _init(initial: Dictionary = {}) -> void:
	facts = initial.duplicate()

func get_fact(fact: StringName, default: Variant = null) -> Variant:
	return facts.get(fact, default)

func set_fact(fact: StringName, value: Variant) -> void:
	facts[fact] = value

## True when EVERY (fact -> required value) in `conditions` matches this state (an absent fact never matches).
func matches(conditions: Dictionary) -> bool:
	for k in conditions:
		if facts.get(k) != conditions[k]:
			return false
	return true

## A COPY of this state with `effects` merged in — never mutates self, so the planner can expand hypothetical
## states without corrupting the real one.
func apply(effects: Dictionary) -> GoapWorldState:
	var next := GoapWorldState.new(facts)
	for k in effects:
		next.facts[k] = effects[k]
	return next

## Canonical key (facts sorted by name) for the A* open/closed set. A Dictionary can't be a Dictionary key in
## GDScript, so revisited-state dedup keys on this string — without it the search can loop / blow the depth cap.
func key() -> String:
	var keys: Array = facts.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%s" % [k, facts[k]])
	return "|".join(parts)
