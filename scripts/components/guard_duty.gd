@tool
class_name GuardDuty
extends Node

## Drop under an NPC to put it on BODYGUARD duty: it defends `protectee` (engages anyone hostile to them), the
## same way a recruited companion defends the player — but for ANY character, need not be player-aligned. Calls
## the parent NPC's guard() on _ready. Drop it into a wave via EncounterSpawner.attach_scenes so a spawned squad
## arrives already guarding a VIP (the VIP just needs to be in `protectee_group`).

## The character to protect. Empty = auto-resolve from `protectee_group`.
@export var protectee_path: NodePath
## When protectee_path is empty, guard the first node in this group (drop the VIP into it). Empty = no auto-resolve.
@export var protectee_group: StringName = Groups.VIP

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor; guarding is runtime-only
	var npc := get_parent()
	if npc == null or not npc.has_method(&"guard"):
		return
	var who := _protectee()
	if who != null:
		npc.guard(who)

func _protectee() -> Node3D:
	if not protectee_path.is_empty():
		return get_node_or_null(protectee_path) as Node3D
	if protectee_group != &"" and is_inside_tree():
		return get_tree().get_first_node_in_group(protectee_group) as Node3D
	return null

func _get_configuration_warnings() -> PackedStringArray:
	var p := get_parent()
	if p == null or not p.has_method(&"guard"):
		return PackedStringArray(["GuardDuty must be a child of an NPC (a node with guard()) — it puts that NPC on bodyguard duty."])
	if protectee_path.is_empty() and protectee_group == &"":
		return PackedStringArray(["GuardDuty has no protectee — set protectee_path or protectee_group (the VIP to defend)."])
	return PackedStringArray()
