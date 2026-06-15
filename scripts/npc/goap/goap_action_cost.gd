class_name GoapActionCost
extends Resource

## One per-archetype GOAP ACTION-cost override, authored as a dropdown ROW -- the replacement for a free-text
## Dictionary key. Pick the action from the list; `cost` REPLACES that action's planner base_cost for this
## archetype (the consumer clamps it >= 0). Lives in GoapProfile.action_cost_overrides. Keep the dropdown values
## in sync with the actions npc.gd _build_goap_actions registers.
@export_enum("Hold", "Detect", "Investigate", "FireArmed", "FireUnarmed", "Flee") var action: String = "Hold"
@export var cost: float = 1.0
