class_name Character
extends CharacterBody3D

signal damaged(current_hp: float, max_hp: float)
signal died()

@export var blast_damp_divisor: float = 1.12

@export var max_hp: int = 10
var hp: int
@export var mesh: Node3D
const BLOOD_SPLAT_DECAL = preload("uid://dg5ui5is8sakg")
const CHARACTER_DUST = preload("uid://um6f8g8g6l7v")
const FLASH_OVERLAY_SHADER = preload("res://resources/shaders/flash_overlay.gdshader")
const OUTLINE_SHADER = preload("res://resources/shaders/outline.gdshader")
const FLASH_PEAK_STRENGTH: float = 2.0
const FLASH_UP_TIME: float = 0.08
const FLASH_DOWN_TIME: float = 0.18
const OUTLINE_THICKNESS: float = 0.015
const OUTLINE_COLOR: Color = Color.BLACK

@export var has_outline: bool = true

var explosion_velocity: Vector3

var _blast_timer: float = 0.0
var _flash_material: ShaderMaterial
var _outline_material: ShaderMaterial
var _flash_tween: Tween

func _ready():
	hp = max_hp
	_setup_overlay_chain()

func _setup_overlay_chain() -> void:
	if not mesh:
		return
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_OVERLAY_SHADER
	_flash_material.set_shader_parameter("flash_strength", 0.0)
	var overlay: Material = _flash_material
	if has_outline:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.set_shader_parameter("outline_color", OUTLINE_COLOR)
		_outline_material.set_shader_parameter("outline_thickness", OUTLINE_THICKNESS)
		_outline_material.next_pass = _flash_material
		overlay = _outline_material
	var targets: Array[MeshInstance3D] = []
	_collect_mesh_instances(mesh, targets)
	for m in targets:
		m.material_overlay = overlay

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

func flash_red() -> void:
	if not _flash_material:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(
		_flash_material, "shader_parameter/flash_strength", FLASH_PEAK_STRENGTH*4, FLASH_UP_TIME
	)
	_flash_tween.tween_property(
		_flash_material, "shader_parameter/flash_strength", 0.0, FLASH_DOWN_TIME
	)

func take_damage(_amount: int):
	flash_red()
	hp -= _amount
	damaged.emit(hp, max_hp)
	if hp <= 0:
		gore()
		die()

func die():
	died.emit()
	queue_free()

func heal(_amount: int):
	hp = min(hp + _amount, max_hp)
	damaged.emit(hp, max_hp)

func gravity(delta: float):
	if !is_on_floor():
		velocity += get_gravity() * delta

func apply_velocity():
	velocity += explosion_velocity
	move_and_slide()
	velocity -= explosion_velocity / blast_damp_divisor

func apply_velocity_launch_forward():
	move_and_slide()
	velocity -= explosion_velocity / blast_damp_divisor

func apply_blast():
	if explosion_velocity.length() > GameTuning.BLAST_MIN_MAGNITUDE:
		_blast_timer = GameTuning.BLAST_GRACE_TIMER

	if is_on_floor() and _blast_timer <= 0.0:
		explosion_velocity = Vector3.ZERO
		return

	var dt := get_physics_process_delta_time()
	_blast_timer -= dt
	var blast_t := 1.0 - pow(1.0 - GameTuning.BLAST_DECAY_RATE, dt * GameTuning.SMOOTHING_REFERENCE_FPS)
	explosion_velocity = explosion_velocity.lerp(Vector3.ZERO, blast_t)
	if explosion_velocity.length() < GameTuning.BLAST_MIN_MAGNITUDE:
		explosion_velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	gravity(delta)
	apply_blast()
	apply_velocity()

func spawn_blood_decal() -> void:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 2.0
	)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	if result:
		var decal = BLOOD_SPLAT_DECAL.instantiate()
		get_tree().root.add_child(decal)

		decal.global_position = result.position + result.normal * 0.02

		decal.cull_mask = 2

		var up: Vector3 = result.normal
		var z: Vector3
		if absf(up.dot(Vector3.UP)) > 0.99:
			z = Vector3.FORWARD.slide(up).normalized()
		else:
			z = Vector3.UP.slide(up).normalized()
		var x := up.cross(z).normalized()
		decal.global_transform.basis = Basis(x, up, z)

@export var bloody_mess: Node3D

func gore() -> void:
	spawn_blood_decal()
	if bloody_mess:
		bloody_mess.particles(Vector3.ZERO)
	_notify_nearby_players_of_death()

func _notify_nearby_players_of_death() -> void:
	var range_max := maxf(GameTuning.BLOOD_SPLATTER_RANGE, GameTuning.DEATH_SHAKE_RANGE)
	var players := get_tree().get_nodes_in_group("Player")
	for p in players:
		if p == self:
			continue
		if not p is Node3D:
			continue
		var d := global_position.distance_to(p.global_position)
		if d > range_max:
			continue
		if p.has_method("on_nearby_death"):
			p.on_nearby_death(d)

func spawn_dust(intensity: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * GameTuning.DUST_GROUND_PROBE_DISTANCE
	)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	var pos: Vector3 = result.position if result else global_position
	var dust: GPUParticles3D = CHARACTER_DUST.instantiate()
	get_tree().root.add_child(dust)
	dust.global_position = pos + Vector3.UP * GameTuning.DUST_GROUND_OFFSET
	var safe_intensity = max(intensity, 0.05)
	dust.scale = Vector3.ONE * safe_intensity
	dust.amount_ratio = clampf(safe_intensity, GameTuning.DUST_AMOUNT_RATIO_MIN, 1.0)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
