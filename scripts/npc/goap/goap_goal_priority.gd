@tool
class_name GoapGoalPriority
extends Resource

## One per-archetype GOAP GOAL-priority override, authored as a dropdown ROW -- the replacement for a free-text
## Dictionary key (which also deletes the String-vs-StringName key-hash footgun the old _goap_override worked
## around). Pick the goal from the list; `priority` REPLACES that goal's authored base_priority for this archetype
## (raise Survive -> a coward, lower it -> a fearless fighter). Lives in GoapProfile.goal_priorities. The dropdown
## self-populates from GoapLibrary (the single source npc.gd's goals are drift-tested against), so it can't go
## stale when a goal is added/renamed.
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")

@export var goal: String = "Survive"
@export var priority: float = 1.0

## Self-populate the `goal` dropdown from the registered goal names (PROPERTY_HINT_ENUM), not a hand-typed list.
func _validate_property(property: Dictionary) -> void:
	if property.name == "goal":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = GoapLibrary.goal_names_csv()
