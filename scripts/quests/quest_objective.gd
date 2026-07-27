@tool
class_name QuestObjective
extends Resource

## One step of a Quest. `type` says what completes it and `target_id` what to match — an NPC identity key for
## KILL/TALK (NpcData.id, or the display_name where no id is authored — see target_id), an Item.id for
## PICKUP/USE_ITEM, an area/group name for ENTER_AREA, a GameState flag name for FLAG.
## GameState.advance_objective bumps progress toward `required_count`. An `optional` objective doesn't block the
## quest from completing (a bonus goal). These auto-fire from gameplay: KILL/TALK/PICKUP/ENTER_AREA/USE_ITEM advance
## via GameState.notify_* (from npc.gd / dialogue_manager.gd / can_pick_up.gd / trigger_volume.gd / player.gd) and
## FLAG advances from GameState.set_flag.

enum Type { KILL, TALK, PICKUP, ENTER_AREA, USE_ITEM, FLAG }

## Drives the target_id dropdown (item ids on disk) for PICKUP/USE_ITEM objectives — const-preloaded, see item_ids.gd.
const ItemIds = preload("res://scripts/items/item_ids.gd")

## Stable id, unique within the quest — the key advance_objective / progress queries use.
@export var id: StringName = &""
@export_multiline var description: String = ""
## What completes this objective.
@export var type: Type = Type.FLAG:
	set(value):
		type = value
		notify_property_list_changed()  # refresh target_id's hint — the item-id dropdown only applies to PICKUP/USE_ITEM
## What to match for `type`: an NPC identity key (KILL/TALK — prefer the NpcData.id so the objective survives a
## display_name edit/localization; the NPC's display_name ALSO matches, as the legacy fallback, so pre-identity
## quests authored against a display string keep working unedited), an Item.id (PICKUP/USE_ITEM), an area/group
## name (ENTER_AREA), or a GameState flag name (FLAG).
@export var target_id: StringName = &""
## How many times it must fire to be done (e.g. "kill 5 raiders").
@export_range(1, 9999) var required_count: int = 1
## A bonus objective — it does NOT block the quest from completing when the required ones are done.
@export var optional: bool = false

@export_group("Marker")
## Show a Compass chevron + Minimap dot at `marker_position` while this objective is active (a QuestMarkerSync
## spawns the WorldMarker, removes it when the objective is done). Off = no marker.
@export var show_marker: bool = false
## World position the marker sits at (the objective's destination — a turn-in NPC, an area, a pickup).
@export var marker_position: Vector3 = Vector3.ZERO

## For PICKUP / USE_ITEM objectives, target_id IS an Item.id — self-populate it from the item ids on disk (a
## SUGGESTION, still typable). For KILL/TALK (an NPC identity key / display name), ENTER_AREA (an area name), or
## FLAG (a flag name) there's no on-disk registry, so the field stays free text.
func _validate_property(property: Dictionary) -> void:
	if property.name == "target_id" and (type == Type.PICKUP or type == Type.USE_ITEM):
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ItemIds.ids_csv()
