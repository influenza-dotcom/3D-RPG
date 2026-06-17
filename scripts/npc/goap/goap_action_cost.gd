@tool
class_name GoapActionCost
extends Resource

## One per-archetype GOAP ACTION-cost override, authored as a dropdown ROW -- the replacement for a free-text
## Dictionary key. Pick the action from the list; `cost` REPLACES that action's planner base_cost for this
## archetype (the consumer clamps it >= 0). Lives in GoapProfile.action_cost_overrides. The dropdown self-populates
## from GoapLibrary (the single source npc.gd's actions are drift-tested against), so it can't go stale when an
## action is added/renamed.
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")

@export var action: String = "Hold"
@export var cost: float = 1.0

## Self-populate the `action` dropdown from the registered action names (PROPERTY_HINT_ENUM), not a hand-typed list.
func _validate_property(property: Dictionary) -> void:
	if property.name == "action":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = GoapLibrary.action_names_csv()
