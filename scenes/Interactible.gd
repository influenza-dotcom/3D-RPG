class_name Interactable
extends RigidBody3D

const OUTLINE_SHADER = preload("res://resources/shaders/outline.gdshader")
const OUTLINE_THICKNESS: float = 0.015
const OUTLINE_HIDDEN_COLOR: Color = Color(1.0, 1.0, 1.0, 0.0)
const OUTLINE_VISIBLE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

@export var impact_sfx: AudioStreamPlayer3D

var _impact_cooldown: float = 0.0
var _damage_cooldown: float = 0.0
var _outline_material: ShaderMaterial
var _pre_step_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_setup_outline()

func _setup_outline() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("outline_color", OUTLINE_HIDDEN_COLOR)
	_outline_material.set_shader_parameter("outline_thickness", OUTLINE_THICKNESS)
	var targets: Array[MeshInstance3D] = []
	_collect_mesh_instances(self, targets)
	for m in targets:
		m.material_overlay = _outline_material

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

func set_outline_visible(visible: bool) -> void:
	if not _outline_material:
		return
	_outline_material.set_shader_parameter(
		"outline_color",
		OUTLINE_VISIBLE_COLOR if visible else OUTLINE_HIDDEN_COLOR
	)

func _physics_process(delta: float) -> void:
	if _impact_cooldown > 0.0:
		_impact_cooldown -= delta
	if _damage_cooldown > 0.0:
		_damage_cooldown -= delta
	_pre_step_velocity = linear_velocity

func _on_body_entered(body: Node) -> void:
	var my_speed := _pre_step_velocity.length()
	var their_speed := 0.0
	if body is RigidBody3D:
		their_speed = (body as RigidBody3D).linear_velocity.length()
	elif body is CharacterBody3D:
		their_speed = (body as CharacterBody3D).velocity.length()
	on_impact(maxf(my_speed, their_speed))
	_try_damage_character(body, my_speed)

func _try_damage_character(body: Node, my_speed: float) -> void:
	if not body is Character:
		return
	if _damage_cooldown > 0.0:
		return
	if my_speed < GameTuning.INTERACTABLE_DAMAGE_MIN_VELOCITY:
		return
	var damage := int(roundf((my_speed - GameTuning.INTERACTABLE_DAMAGE_MIN_VELOCITY) * GameTuning.INTERACTABLE_DAMAGE_PER_M_PER_S))
	if damage <= 0:
		return
	var character := body as Character
	character.take_damage(damage)
	character.explosion_velocity += _pre_step_velocity.normalized() * my_speed * GameTuning.INTERACTABLE_DAMAGE_KNOCKBACK_SCALE
	_damage_cooldown = GameTuning.INTERACTABLE_DAMAGE_COOLDOWN

func on_impact(speed: float) -> void:
	if not impact_sfx:
		return
	if _impact_cooldown > 0.0:
		return
	if speed < GameTuning.INTERACTABLE_IMPACT_MIN_VELOCITY:
		return
	var span := GameTuning.INTERACTABLE_IMPACT_MAX_VELOCITY - GameTuning.INTERACTABLE_IMPACT_MIN_VELOCITY
	var t := clampf((speed - GameTuning.INTERACTABLE_IMPACT_MIN_VELOCITY) / span, 0.0, 1.0)
	impact_sfx.volume_db = lerpf(GameTuning.INTERACTABLE_IMPACT_MIN_DB, GameTuning.INTERACTABLE_IMPACT_MAX_DB, t)
	impact_sfx.pitch_scale = 1.0 + randf_range(-GameTuning.INTERACTABLE_IMPACT_PITCH_SPREAD, GameTuning.INTERACTABLE_IMPACT_PITCH_SPREAD)
	impact_sfx.play()
	_impact_cooldown = GameTuning.INTERACTABLE_IMPACT_COOLDOWN

func on_picked_up(_picker: Node) -> void:
	pass

func on_dropped() -> void:
	pass
