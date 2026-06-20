@tool
class_name CutsceneAction
extends Resource

## One step of a Cutscene, run in order by a CutscenePlayer. `type` selects which of the grouped fields apply.

enum Type { WAIT, SET_FLAG, CALL_METHOD, DIALOGUE, CAMERA_MOVE, FADE, TOAST, CAPTION }

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
## World position the cinematic camera eases to over `duration` — OR, when `camera_follow` is set, the OFFSET
## from the followed node (so the camera trails a moving subject at this relative position).
@export var camera_position: Vector3
## World rotation (degrees) the cinematic camera eases to. Ignored when `camera_look_at` is set.
@export var camera_rotation: Vector3
## OPTIONAL node to keep framed: the camera looks at it EVERY frame of the move (a moving subject stays centred),
## overriding `camera_rotation`. Empty = ease to camera_rotation.
@export var camera_look_at: NodePath
## OPTIONAL node to follow: the camera's target position becomes this node's position + `camera_position` (the
## offset), tracked live, so it trails a moving subject. Empty = move to the absolute `camera_position`.
@export var camera_follow: NodePath
## Target field of view (degrees) eased to over the move — a dolly zoom. 0 = leave the FOV unchanged.
@export var camera_fov: float = 0.0
## Snap-cut instantly to the framing instead of easing (a hard cut). Off = ease over `duration`.
@export var camera_snap: bool = false
## Easing curve for the move (when not snapping).
@export var camera_ease: Tween.EaseType = Tween.EASE_IN_OUT
## Transition type for the move (when not snapping).
@export var camera_trans: Tween.TransitionType = Tween.TRANS_SINE

@export_group("Fade")
## Colour the screen eases TO over `duration` (alpha matters: black a=1 fades out, a=0 fades back in).
@export var fade_color: Color = Color(0, 0, 0, 1)

@export_group("Toast")
## On-screen toast text shown when a Type.TOAST step runs (UI.toast via the player's HUD).
@export var toast_text: String = ""
@export var toast_color: Color = Color(1, 1, 1, 1)

@export_group("Caption")
## A centred cinematic caption ("Three days later…") shown for `duration` seconds when a Type.CAPTION step runs,
## then cleared. Leave `duration` at 0 to hold it until the cutscene ends. Empty = nothing shown.
@export var caption_text: String = ""
## Colour of the caption text (outlined in black so it reads over any backdrop).
@export var caption_color: Color = Color(1, 1, 1, 1)
