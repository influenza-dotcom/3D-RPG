@tool
class_name CutsceneActor
extends Node

## Drop under an NPC (or point `npc_path` at one) to let a Cutscene STAGE it: WALK_TO a marker, FACE a target,
## PLAY_ANIM — with the NPC's AI brain suppressed so it won't fight the scripted blocking. A Cutscene's
## WALK_TO / FACE / PLAY_ANIM action addresses this actor (or the NPC directly) by node path; control is
## auto-released when the cutscene ends (CutscenePlayer._finish), so the NPC can never be left frozen.

## The NPC this actor drives. Empty = this node's parent.
@export var npc_path: NodePath
## OPTIONAL AnimationPlayer for PLAY_ANIM. Actors are procedural (BodyModelSwap) so this is usually empty and
## PLAY_ANIM is a no-op — wiring a real rig is a separate art task. Empty = PLAY_ANIM does nothing.
@export var animation_player_path: NodePath

## Begin cutscene control of the NPC (suppress its AI brain). Idempotent; safe to call before each verb.
func begin() -> void:
	var npc := _npc()
	if npc != null and npc.has_method(&"set_cutscene_control"):
		npc.set_cutscene_control(true)

## Walk the NPC to a world point (takes control first if needed).
func walk_to(point: Vector3) -> void:
	var npc := _npc()
	if npc == null:
		return
	if npc.has_method(&"set_cutscene_control"):
		npc.set_cutscene_control(true)
	if npc.has_method(&"walk_to"):
		npc.walk_to(point)

## Turn the NPC to face a world point (takes control first if needed).
func face(point: Vector3) -> void:
	var npc := _npc()
	if npc == null:
		return
	if npc.has_method(&"set_cutscene_control"):
		npc.set_cutscene_control(true)
	if npc.has_method(&"face"):
		npc.face(point)

## Play an animation on the assigned AnimationPlayer, if any (else a no-op — actors are procedural by default).
func play_anim(anim: StringName) -> void:
	var ap := get_node_or_null(animation_player_path) as AnimationPlayer
	if ap != null and anim != &"" and ap.has_animation(anim):
		ap.play(anim)

## Release cutscene control — the NPC's AI resumes. Always called when the cutscene ends.
func end() -> void:
	var npc := _npc()
	if npc != null and npc.has_method(&"set_cutscene_control"):
		npc.set_cutscene_control(false)

func _npc() -> Node:
	if not npc_path.is_empty():
		return get_node_or_null(npc_path)
	return get_parent()

func _get_configuration_warnings() -> PackedStringArray:
	var n := _npc()
	if n == null:
		return PackedStringArray(["CutsceneActor has no NPC — set npc_path or make it a child of an NPC."])
	if not n.has_method(&"set_cutscene_control"):
		return PackedStringArray(["CutsceneActor's NPC '%s' can't be cutscene-controlled (no set_cutscene_control)." % str(n.name)])
	return PackedStringArray()
