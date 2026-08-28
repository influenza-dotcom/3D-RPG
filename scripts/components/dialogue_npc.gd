@tool
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
## pressing interact (F / PickUp) turns it to face you (if turn_to_face) and starts `dialogue`.
##
## SETUP: give it an Area3D child (with a CollisionShape3D covering the body) assigned to
## `range_area`, a visible mesh, and a DialogueResource in `dialogue`.

@export_group("Dialogue")
## The DialogueResource (conversation tree) opened when the player interacts. Required — with none assigned the node does nothing on interact.
@export var dialogue: DialogueResource:
	set(value):
		dialogue = value
		update_configuration_warnings()
## OPTIONAL: pick the conversation by world state (flags / quests) instead of the single `dialogue` — the first
## matching DialogueSelector row wins, else its default. When set, it OVERRIDES `dialogue`.
@export var dialogue_selector: DialogueSelector:
	set(value):
		dialogue_selector = value
		update_configuration_warnings()
@export var voice: VoiceData  ## how the OS text-to-speech reads this NPC's lines (optional)
## Speaker name shown in the dialogue box (DialogueNPC IS the speaker — a car, terminal, sign, etc.).
@export var display_name: String = ""
@export_group("Look-At Hitbox")
## the look-at hitbox the player aims at (name kept for scene compat)
@export var range_area: Area3D:
	set(value):
		range_area = value
		update_configuration_warnings()
@export_group("Highlight")
## Colour of the look-at outline drawn while the player aims at this node.
## ⭐ The COLOUR is no longer painted from here. Since 2026-08-27 the look-at highlight is InkOutline's
## screen-space ring (id InkOutline.TINT_ID_HOVER), and a ring resolves one id to one GLOBAL LUT slot — so the
## hue lives on InkOutline.highlight_hover and the thickness on InkOutline.highlight_width_px. These two exports
## survive as the VISIBILITY SWITCH they already doubled as: alpha 0 or width 0 still means "this one gets no
## hover outline" (the shipping ATM relies on it), and set_look_highlight then never touches the host at all.
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Thickness of the look-at outline. See the note above: only "> 0 or not" is read now.
@export var highlight_width: float = 1.0
@export_group("Behavior")
## Inanimate objects (a car) stay put; set true for a character that should turn to face you.
@export var turn_to_face: bool = false

var _highlight_on: bool = false  ## does this instance highlight at all? (see highlight_color)
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: in the editor we only evaluate _get_configuration_warnings, never the runtime hitbox setup
	if range_area:
		# Repurpose the Area3D as a look-at hitbox: put it on the talk layer so the interaction
		# ray detects it, and clear its mask (we're aimed at, we don't sense bodies).
		range_area.collision_layer = TalkHelpers.TALK_LAYER
		range_area.collision_mask = 0
	# An INVISIBLE highlight (alpha 0 / zero width) never borrows, and set_look_highlight then no-ops — a mesh
	# carries ONE outline id, shared with whatever else dresses these meshes, so a transparent highlight would
	# still evict it for as long as you look. Same invariant as LookAtInteractable._build_outline.
	_highlight_on = highlight_color.a > 0.0 and highlight_width > 0.0
	_meshes = TalkHelpers.collect_meshes(self, range_area)

## Editor warnings: a DialogueNPC's whole job is to be interfaced with, so it needs both a conversation
## (`dialogue`) and a look-at hitbox (`range_area`) — without either it silently does nothing on interact.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if dialogue == null and dialogue_selector == null:
		warnings.append("No `dialogue` or `dialogue_selector` assigned — interacting with this node does nothing. Assign one.")
	if range_area == null:
		warnings.append("No `range_area` assigned — without a look-at hitbox the interaction ray can't target this node. Assign its Area3D child.")
	return warnings

## The player may only talk to a non-hostile thing — mirrors Talkable so the ray stays handler-agnostic
## (TalkHelpers.is_talkable_now reads this). A DialogueNPC is its own (inanimate) speaker, not an NPC,
## so this is effectively always true; kept for symmetry and to gate should a future host ever be one.
func can_be_talked_to() -> bool:
	# `self` is a DialogueNPC (a Node3D), structurally never an NPC, so a direct `self as NPC` is a
	# compile error in Godot 4 (incompatible branches). Route through a Node3D-typed local — exactly
	# as Talkable does via `_host() as NPC` — so the defensive, null-safe check still COMPILES; it
	# resolves to null here, i.e. a DialogueNPC is always talkable.
	var as_node: Node3D = self
	var npc := as_node as NPC
	return npc == null or not npc.is_hostile()

## Whether this node has ANY conversation to offer — a direct `dialogue` or a `dialogue_selector`.
func _has_dialogue() -> bool:
	return dialogue != null or dialogue_selector != null

## The conversation to actually open right now: the selector's pick (by world state) if assigned, else `dialogue`.
func _dialogue() -> DialogueResource:
	return dialogue_selector.pick() if dialogue_selector != null else dialogue

## Toggled by the interaction ray as the player's aim enters/leaves this node.
func set_look_highlight(on: bool) -> void:
	if not _highlight_on:
		return  # invisible highlight — never borrow this node's outline id (see _ready)
	InkOutline.set_tint_highlight(_meshes, on)

## The name to show on the look-at hover readout (this node IS the speaker — a car / terminal / sign).
func look_name() -> String:
	return TalkHelpers.speaker_name(display_name, self)

## A DialogueNPC is an inanimate speaker, never an NPC, so there's no NPC to greet on hover.
func host_npc() -> NPC:
	return null

## Called by the interaction ray when the player presses interact while aimed at us. Talking is a
## PROMPT, not a force: we turn (if turn_to_face), swing the camera, then open dialogue after a short
## buffer beat. A DialogueNPC is its own (inanimate) speaker so there's no walk-up; the busy-fighting
## guard is defensive (mirrors can_be_talked_to's `self as NPC`) — `self` is never an NPC here, so it
## only ever bites should a future host be one. Talkable is the path used on an actual combat NPC.
func start_talk(player: Node3D) -> void:
	if not _has_dialogue():
		return
	var as_node: Node3D = self
	var npc := as_node as NPC
	if npc != null and npc.is_in_combat():
		return  # fighting NPC only fights, never talks — drop the request
	if turn_to_face and player != null:
		TalkHelpers.face_player(self, player, GameSettings.dialogue.npc_turn_to_face_duration)
	if player != null and player.has_method(&"focus_camera_on"):
		var focus_point: Vector3 = range_area.global_position if range_area else global_position
		player.focus_camera_on(focus_point)
	# Prompt rather than force: hold the buffer beat so the turn + camera swing read, then open dialogue.
	await get_tree().create_timer(GameSettings.dialogue.talk_prompt_buffer_duration).timeout
	_begin_dialogue()

## Open the actual conversation after the prompt buffer. Guards against being freed mid-buffer (scene
## reload / death) and a dialogue cleared since the press. Passes ourselves as speaker so
## DialogueManager freezes us, plus our display_name for the speaker label.
func _begin_dialogue() -> void:
	var convo := _dialogue()
	if not is_instance_valid(self) or convo == null:
		return
	DialogueManager.start(convo, self, voice, TalkHelpers.speaker_name(display_name, self))
