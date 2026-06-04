class_name DialogueNPC
extends Node3D

## A talkable thing built as a single node (script attached directly to the node, with a child
## Area3D for the look-at hitbox). Use it when you want a whole node -- including an INANIMATE
## object like a car, terminal, or sign -- to be "interfaced with". For dropping talk onto an
## existing scene without overriding its root script, prefer the Talkable component instead;
## both behave identically to the player's interaction ray.
##
## It's a LOOK-AT target: the `range_area` Area3D is repurposed as a hitbox on the talk physics
## layer, so the player's interaction ray detects it when aimed. Looking highlights the node;
## pressing interact (E / PickUp) turns it to face you (if turn_to_face) and starts `dialogue`.
##
## SETUP: give it an Area3D child (with a CollisionShape3D covering the body) assigned to
## `range_area`, a visible mesh, and a DialogueResource in `dialogue`.

@export var dialogue: DialogueResource
@export var voice: VoiceData  ## how the OS text-to-speech reads this NPC's lines (optional)
## Speaker name shown in the dialogue box (DialogueNPC IS the speaker — a car, terminal, sign, etc.).
@export var display_name: String = ""
@export var range_area: Area3D  ## the look-at hitbox the player aims at (name kept for scene compat)
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var highlight_width: float = 1.0
## Inanimate objects (a car) stay put; set true for a character that should turn to face you.
@export var turn_to_face: bool = false

var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	if range_area:
		# Repurpose the Area3D as a look-at hitbox: put it on the talk layer so the interaction
		# ray detects it, and clear its mask (we're aimed at, we don't sense bodies).
		range_area.collision_layer = TalkHelpers.TALK_LAYER
		range_area.collision_mask = 0
	_outline_mat = TalkHelpers.make_outline_material(highlight_color, highlight_width)
	_meshes = TalkHelpers.collect_meshes(self, range_area)

## The player may only talk to a non-hostile thing — mirrors Talkable so the ray stays handler-agnostic
## (TalkHelpers.is_talkable_now reads this). A DialogueNPC is its own (inanimate) speaker, not an NPC,
## so this is effectively always true; kept for symmetry and to gate should a future host ever be one.
func can_be_talked_to() -> bool:
	var npc := self as NPC
	return npc == null or not npc.is_hostile()

## Toggled by the interaction ray as the player's aim enters/leaves this node.
func set_look_highlight(on: bool) -> void:
	TalkHelpers.set_overlay(_meshes, _outline_mat if on else null)

## Called by the interaction ray when the player presses interact while aimed at us. Talking is a
## PROMPT, not a force: we turn (if turn_to_face), swing the camera, then open dialogue after a short
## buffer beat. A DialogueNPC is its own (inanimate) speaker so there's no walk-up; the busy-fighting
## guard is defensive (mirrors can_be_talked_to's `self as NPC`) — `self` is never an NPC here, so it
## only ever bites should a future host be one. Talkable is the path used on an actual combat NPC.
func start_talk(player: Node3D) -> void:
	if dialogue == null:
		return
	var npc := self as NPC
	if npc != null and npc.is_in_combat():
		return  # fighting NPC only fights, never talks — drop the request
	if turn_to_face and player != null:
		TalkHelpers.face_player(self, player, TalkHelpers.TURN_DURATION)
	if player != null and player.has_method(&"focus_camera_on"):
		var focus_point: Vector3 = range_area.global_position if range_area else global_position
		player.focus_camera_on(focus_point)
	# Prompt rather than force: hold the buffer beat so the turn + camera swing read, then open dialogue.
	await get_tree().create_timer(TalkHelpers.TALK_BUFFER).timeout
	_begin_dialogue()

## Open the actual conversation after the prompt buffer. Guards against being freed mid-buffer (scene
## reload / death) and a dialogue cleared since the press. Passes ourselves as speaker so
## DialogueManager freezes us, plus our display_name for the speaker label.
func _begin_dialogue() -> void:
	if not is_instance_valid(self) or dialogue == null:
		return
	DialogueManager.start(dialogue, self, voice, TalkHelpers.speaker_name(display_name, self))
