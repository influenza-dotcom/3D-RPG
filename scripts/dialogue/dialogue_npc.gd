class_name DialogueNPC
extends Node3D

## A talkable NPC. While the player is inside its range Area3D and presses PickUp (the E / pickup
## key — reused so there's no separate "talk" binding), it starts its conversation through DialogueManager.
##
## SETUP: give it an Area3D child (with a CollisionShape3D, collision_mask set to the player's layer)
## assigned to `range_area`, a visible mesh, and a DialogueResource in `dialogue`.

const OUTLINE_SHADER := preload("res://resources/shaders/outline.gdshader")
const HIGHLIGHT_COLOR := Color(1.0, 1.0, 1.0, 1.0)  # white outline shown while the NPC is talkable
const HIGHLIGHT_WIDTH := 1.0                        # matches the pickup-highlight outline width

@export var dialogue: DialogueResource
@export var range_area: Area3D

var _player_in_range: bool = false
var _outline_mat: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	if range_area:
		range_area.body_entered.connect(_on_body_entered)
		range_area.body_exited.connect(_on_body_exited)
	_setup_highlight()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"Player"):
		_player_in_range = true
		_set_highlight(dialogue != null)  # only flag it talkable if there's actually something to say

func _on_body_exited(body: Node) -> void:
	if body.is_in_group(&"Player"):
		_player_in_range = false
		_set_highlight(false)

func _process(_delta: float) -> void:
	if not _player_in_range or dialogue == null:
		return
	# Manager's _unhandled_input runs before this _process, so it won't double-fire the same press.
	if DialogueManager.is_active():
		return
	if InputMap.has_action(&"PickUp") and Input.is_action_just_pressed(&"PickUp"):
		DialogueManager.start(dialogue)

## Build the white-outline overlay (same cull_front shader the pickup highlight uses) and gather
## this NPC's meshes. The overlay is added/removed in _set_highlight rather than left on, so there's
## no extra render pass while the player is out of range.
func _setup_highlight() -> void:
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("outline_color", HIGHLIGHT_COLOR)
	_outline_mat.set_shader_parameter("outline_width", HIGHLIGHT_WIDTH)
	_collect_meshes(self)

func _collect_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			_meshes.append(child)
		_collect_meshes(child)

## Toggle the white outline on every mesh under this NPC.
func _set_highlight(on: bool) -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.material_overlay = _outline_mat if on else null
