@tool
class_name LevelDoor
extends LookAtInteractable

## A drop-in PORTAL: aim + Interact to travel to another LEVEL (GameRoot.load_level) and arrive at the matching
## PlayerSpawn. Assign `target_level` (a LevelData) and `entry_id` (the PlayerSpawn.entry_id to arrive at). The
## twin of QuestStarter / PerkStation, for level flow.
##
## REQUIRES a GameRoot on the scene root (group "game_root") — attach game_root.gd to game.tscn's root. Until
## then the door is inert (it toasts a hint). SETUP: drop it under the doorway prop, size its CollisionShape3D,
## and assign target_level (+ entry_id).

@export var target_level: LevelData
## The PlayerSpawn.entry_id to arrive at in the target level. Blank = that level's default spawn.
@export var entry_id: StringName = &""
@export var prompt_label: String = ""      ## hover label; blank -> "Enter <level display_name>"

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
	if target_level == null:
		return
	var gr := get_tree().get_first_node_in_group(&"game_root")
	if gr != null and gr.has_method(&"load_level"):
		gr.call(&"load_level", target_level, entry_id)
	elif player != null and player.has_method(&"notify_toast"):
		player.notify_toast("No GameRoot — attach game_root.gd to the scene root", Color(1.0, 0.55, 0.4))

func can_be_talked_to() -> bool:
	return target_level != null

func look_name() -> String:
	if not prompt_label.is_empty():
		return prompt_label
	if target_level != null and target_level.display_name != "":
		return "Enter %s" % target_level.display_name
	return "Enter"

func _get_configuration_warnings() -> PackedStringArray:
	if target_level == null:
		return PackedStringArray(["LevelDoor has no `target_level` — assign a LevelData. (It also needs a GameRoot on the scene root.)"])
	return PackedStringArray()
