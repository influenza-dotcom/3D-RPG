@tool
class_name CutsceneAction
extends Resource

## One step of a Cutscene, run in order by a CutscenePlayer. `type` selects which of the grouped fields apply.

enum Type { WAIT, SET_FLAG, CALL_METHOD, DIALOGUE, CAMERA_MOVE, FADE, TOAST }

@export var type: Type = Type.WAIT
## Seconds this step takes (WAIT / CAMERA_MOVE / FADE).
@export var duration: float = 1.0

@export_group("Set Flag")
@export var flag_name: StringName = &""
@export var flag_value: bool = true

@export_group("Call Method")
## A node to call a method on (e.g. an EncounterSpawner's "trigger_spawn", a Door's "open").
@export var event_node_path: NodePath
@export var event_method: StringName = &""

@export_group("Dialogue")
## A conversation to play (the cutscene waits for it to finish).
@export var dialogue: DialogueResource

@export_group("Camera Move")
## World position the cinematic camera eases to over `duration`.
@export var camera_position: Vector3
## World rotation (degrees) the cinematic camera eases to.
@export var camera_rotation: Vector3

@export_group("Fade")
## Colour the screen eases TO over `duration` (alpha matters: black a=1 fades out, a=0 fades back in).
@export var fade_color: Color = Color(0, 0, 0, 1)

@export_group("Toast")
## On-screen toast text shown when a Type.TOAST step runs (UI.toast via the player's HUD).
@export var toast_text: String = ""
@export var toast_color: Color = Color(1, 1, 1, 1)
