@tool
extends EditorInspectorPlugin

## NpcData inspector add-on: injects a resolved-archetype summary card (faction, hp, sight/alert ranges) and
## surfaces conflicts inline -- chiefly the faction_id + faction both-set ambiguity -- so an authored NPC profile
## reads at a glance and dual-source mistakes are caught in the inspector.
##
## STUB: handles nothing yet. The summary card + conflict checks land in the inspector build step.


func _can_handle(_object: Object) -> bool:
	return false  # stub: real check is `object is NpcData`
