class_name Talkable
extends Area3D

## A reusable "this thing can be spoken to" component. Drop talkable.tscn (an Area3D + a
## CollisionShape3D sized to the thing's body) under ANY node that has a mesh -- a friendly
## villager, an enemy you can parley with, or an inanimate object you "interface" with (a
## car, a terminal, a vending machine).
##
## It works as a LOOK-AT target, not a proximity trigger: the component sits on the dedicated
## talk physics layer, and the player's interaction ray (ray_cast.gd) detects it when aimed at.
## The ray highlights the host while you look, and pressing the interact key (E / PickUp) turns
## the host to face you (if turn_to_face) and starts `dialogue` through DialogueManager. Looking
## decides WHICH target you talk to, so two NPCs in the same spot are no longer ambiguous.
##
## SETUP: instance talkable.tscn as a child of the NPC, assign a DialogueResource to `dialogue`,
## and size the CollisionShape3D to roughly cover the body you aim at. The outline + turn apply
## to `highlight_target` (defaults to this component's parent).

@export var dialogue: DialogueResource
@export var voice: VoiceData  ## how the OS text-to-speech reads this NPC's lines (optional)
## Node whose MeshInstance3D descendants get the white outline + the turn. Null -> our parent.
@export var highlight_target: Node3D
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var highlight_width: float = 1.0
## Characters should rotate to face the player on talk; leave off for inanimate objects.
@export var turn_to_face: bool = true

var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	# Become a look-at hitbox: sit on the talk layer so the interaction ray can hit us, and
	# detect nothing ourselves (mask 0 -- we're aimed at, we don't sense bodies).
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_outline_mat = TalkHelpers.make_outline_material(highlight_color, highlight_width)
	var host := _host()
	if host != null:
		_meshes = TalkHelpers.collect_meshes(host, self)

## The node this component represents (highlight + turn target): the configured target, else
## our parent (the node we sit under).
func _host() -> Node3D:
	if highlight_target != null:
		return highlight_target
	return get_parent() as Node3D

## Toggled by the interaction ray as the player's aim enters/leaves this target.
func set_look_highlight(on: bool) -> void:
	TalkHelpers.set_overlay(_meshes, _outline_mat if on else null)

## Called by the interaction ray when the player presses interact while aimed at us.
func start_talk(player: Node3D) -> void:
	if dialogue == null:
		return
	var host := _host()
	if turn_to_face and player != null and host != null:
		TalkHelpers.face_player(host, player, TalkHelpers.TURN_DURATION)
	if player != null and player.has_method(&"focus_camera_on"):
		player.focus_camera_on(global_position)  # swing the player's camera onto this target
	# Pass the host as the speaker so DialogueManager freezes it (no move / attack) while talking.
	DialogueManager.start(dialogue, host, voice)
