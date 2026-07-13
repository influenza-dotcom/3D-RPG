@tool
class_name QuestStarter
extends LookAtInteractable


## A drop-in quest-giver / board: aim + Interact to START the assigned Quest (GameState.start_quest) — the
## inspector counterpart to starting a quest from a TriggerVolume or (later) a dialogue choice. The twin of
## PerkStation.
##
## SETUP: drop it under the giver / board prop (or assign highlight_target), size its CollisionShape3D, and
## assign `quest`. It's only interactable while the quest isn't already active or completed.

@export var quest: Quest
@export var prompt_label: String = ""      ## hover label; blank -> "Accept: <title>"
@export var consume_on_use: bool = true    ## free the node after starting (a one-time board)

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()
		return
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()

func start_talk(player: Node) -> void:
	if quest == null:
		return
	GameState.start_quest(quest)
	if player != null and player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.quest_started(_quest_title()), Color(0.7, 0.85, 1.0))
	if consume_on_use:
		queue_free()

## Offerable only while the quest isn't already running or finished (so a one-time board doesn't re-offer).
func can_be_talked_to() -> bool:
	return quest != null and quest.id != &"" and not GameState.is_quest_active(quest.id) and not GameState.is_quest_completed(quest.id)

func look_name() -> String:
	return prompt_label if not prompt_label.is_empty() else PlayerText.accept(_quest_title())

func _quest_title() -> String:
	if quest != null and quest.title != "":
		return quest.title
	return "Quest"

func _get_configuration_warnings() -> PackedStringArray:
	if quest == null:
		return PackedStringArray(["QuestStarter has no `quest` assigned — it will start nothing."])
	return PackedStringArray()
