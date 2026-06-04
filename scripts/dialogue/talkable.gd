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
## Speaker name for the dialogue box. Leave blank to use the host's NPC display_name (so a talkable
## NPC is named once, on the NPC); set it to name an inanimate host (a car, terminal, sign).
@export var display_name: String = ""
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

## The player may only talk to a non-hostile host that ISN'T mid-fight — a hostile NPC won't parley,
## and a busy-fighting one only fights (it doesn't talk). The ray reads this via TalkHelpers.is_talkable_now
## to drop the look-at highlight AND refuse the interact, so a fighting/hostile enemy shows no talk cue.
## An inanimate host (no NPC) is always talkable, so a car / terminal under a Talkable is unaffected.
func can_be_talked_to() -> bool:
	var npc := _host() as NPC
	return npc == null or (not npc.is_hostile() and not npc.is_in_combat())

## Toggled by the interaction ray as the player's aim enters/leaves this target.
func set_look_highlight(on: bool) -> void:
	TalkHelpers.set_overlay(_meshes, _outline_mat if on else null)

## Called by the interaction ray when the player presses interact while aimed at us. Talking is a
## PROMPT, not a force: an NPC host acknowledges, walks into framing range, then speaks after a short
## buffer (prompt_talk -> _begin_dialogue); a busy-fighting NPC ignores the request entirely; an
## inanimate host (a car, terminal) keeps the old immediate behaviour via the fallback path.
func start_talk(player: Node3D) -> void:
	if dialogue == null:
		return
	var host := _host()
	var npc := host as NPC
	if npc != null and npc.is_in_combat():
		return  # fighting NPC: it only fights, it doesn't talk — drop the request, no dialogue
	if npc != null and npc.has_method(&"prompt_talk") and not npc.is_hostile():
		# Hand the NPC the cue and let IT decide when to speak: it turns + walks into frame itself
		# (so we must NOT also face_player here — that would fight the approach), then opens dialogue.
		# The camera focus + zoom now fire in _begin_dialogue (with the letterbox bars), NOT here, so the
		# cinematic only begins once the NPC has actually walked into frame and starts speaking.
		npc.prompt_talk(player, _begin_dialogue.bind(host, player))
	else:
		# Inanimate / non-NPC host (or a hostile one slipping past the ray): turn in place, then begin
		# after the same buffer beat so the camera swing / turn read before the box opens.
		if turn_to_face and player != null and host != null:
			TalkHelpers.face_player(host, player, TalkHelpers.TURN_DURATION)
		await get_tree().create_timer(TalkHelpers.TALK_BUFFER).timeout
		_begin_dialogue(host, player)

## Open the actual conversation. Deferred until the NPC has acknowledged + walked into frame (or the
## fallback buffer elapsed). Guards against the component being freed mid-buffer (scene reload / death)
## and a dialogue cleared since the prompt. Passes the host as speaker so DialogueManager freezes it,
## plus the resolved speaker name (this component's display_name, else the host NPC's).
func _begin_dialogue(host: Node3D, player: Node3D) -> void:
	if not is_instance_valid(self) or dialogue == null:
		return
	# Swing + zoom the player's camera onto the speaker AS the box opens, so the focus/zoom land
	# together with the letterbox bars (DialogueManager.start) — not back when the player interacted.
	if player != null and player.has_method(&"focus_camera_on"):
		player.focus_camera_on(global_position)
	DialogueManager.start(dialogue, host, voice, TalkHelpers.speaker_name(display_name, host))
