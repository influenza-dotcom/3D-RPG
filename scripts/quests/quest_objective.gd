@tool
class_name QuestObjective
extends Resource

## One step of a Quest. `type` says what completes it and `target_id` what to match — an NPC display_name for
## KILL/TALK, an Item.id for PICKUP/USE_ITEM, an area/group name for ENTER_AREA, a GameState flag name for FLAG.
## GameState.advance_objective bumps progress toward `required_count`. An `optional` objective doesn't block the
## quest from completing (a bonus goal). The objective HOOKS that auto-fire these land in the next sub-slice.

enum Type { KILL, TALK, PICKUP, ENTER_AREA, USE_ITEM, FLAG }

## Stable id, unique within the quest — the key advance_objective / progress queries use.
@export var id: StringName = &""
@export_multiline var description: String = ""
## What completes this objective.
@export var type: Type = Type.FLAG
## What to match for `type`: an NPC display_name (KILL/TALK), an Item.id (PICKUP/USE_ITEM), an area/group name
## (ENTER_AREA), or a GameState flag name (FLAG).
@export var target_id: StringName = &""
## How many times it must fire to be done (e.g. "kill 5 raiders").
@export_range(1, 9999) var required_count: int = 1
## A bonus objective — it does NOT block the quest from completing when the required ones are done.
@export var optional: bool = false
