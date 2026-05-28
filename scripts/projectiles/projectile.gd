class_name Projectile
extends RigidBody3D

var direction: Vector3 = Vector3.FORWARD
var speed: float = 8.00
var damage: int = 2
var life_time: float = 10.0
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

var visual_only: bool = false
var _consumed: bool = false

const DUST = preload("uid://um6f8g8g6l7v")
const BLOOD = preload("uid://c7v6vgs74fhn4")

const BULLET_HOLE_DECAL = preload("uid://dh1ydtvwvgiqg")

const DECAL_SIZE: Vector3 = Vector3(0.3, 0.1, 0.3)
const DECAL_CULL_MASK: int = 2
const PARTICLE_BACKOFF: float = 0.1
const DECAL_FALLBACK_BACKOFF: float = 0.05
const IMPACT_BACKOFF: float = 0.4
const NORMAL_PARALLEL_THRESHOLD: float = 0.99
@export var impact_enemy_hit: AudioStreamPlayer3D
@export var impact_generic: AudioStreamPlayer3D

signal queued_for_deletion(_last_pos: Vector3)

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 1
	linear_velocity = direction * speed
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)
	await get_tree().create_timer(life_time).timeout
	if is_inside_tree():
		queue_free()

func particles(_body, _last_velocity) -> void:
	var is_character: bool = _body is Character
	var _particles = BLOOD.instantiate() if is_character else DUST.instantiate()
	get_tree().root.add_child(_particles)
	var backoff := IMPACT_BACKOFF if is_character else PARTICLE_BACKOFF
	_particles.global_position = global_position - _last_velocity.normalized() * backoff
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)
	if is_character and _body.get("bloody_mess"):
		_body.bloody_mess.splatter_at(global_position, _last_velocity)

func _on_body_entered(body):
	if _consumed:
		return
	_consumed = true
	var last_velocity := linear_velocity
	linear_velocity = Vector3.ZERO

	particles(body, last_velocity)

	if body.has_method("take_damage"):
		if !visual_only:
			body.take_damage(damage)
			if body is Character:
				impact_enemy_hit.reparent(get_tree().root)
				impact_enemy_hit.play()
				impact_enemy_hit.finished.connect(impact_enemy_hit.queue_free)
			else:
				impact_generic.reparent(get_tree().root)
				impact_generic.play()
				impact_generic.finished.connect(impact_generic.queue_free)
	else:
		_spawn_decal(last_velocity)
		if !visual_only:
			impact_generic.reparent(get_tree().root)
			impact_generic.play()
			impact_generic.finished.connect(impact_generic.queue_free)

	if not visual_only and body is RigidBody3D and not (body is Projectile):
		var rb := body as RigidBody3D
		var impulse := last_velocity.normalized() * GameSettings.physics_damage.bullet_interactable_knockback
		rb.apply_impulse(impulse, global_position - rb.global_position)
		if rb is Interactable:
			(rb as Interactable).on_impact(GameSettings.physics_damage.interactable_impact_max_velocity)

	if not visual_only:
		var hit_dir := last_velocity.normalized()
		queued_for_deletion.emit(global_position - hit_dir * IMPACT_BACKOFF)
	queue_free()

func _spawn_decal(last_velocity: Vector3) -> void:
	if last_velocity.is_zero_approx():
		return
	var dir := last_velocity.normalized()
	var space_state := get_world_3d().direct_space_state
	var probe_dist := GameSettings.effects.decal_probe_distance
	var query := PhysicsRayQueryParameters3D.create(
		global_position - dir * probe_dist,
		global_position + dir * probe_dist
	)
	var result := space_state.intersect_ray(query)

	var decal = BULLET_HOLE_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.size = DECAL_SIZE
	decal.cull_mask = DECAL_CULL_MASK

	if result:
		decal.global_position = result.position + result.normal * GameSettings.effects.decal_normal_offset
		_orient_decal_to_normal(decal, result.normal)
	else:
		decal.global_position = global_position - dir * DECAL_FALLBACK_BACKOFF


func _on_queued_for_deletion(_last_pos: Vector3) -> void:
	on_deletion()

func _orient_decal_to_normal(decal: Decal, normal: Vector3) -> void:
	var up := normal
	var z: Vector3
	if absf(up.dot(Vector3.UP)) > NORMAL_PARALLEL_THRESHOLD:
		z = Vector3.FORWARD.slide(up).normalized()
	else:
		z = Vector3.UP.slide(up).normalized()
	var x := up.cross(z).normalized()
	decal.global_transform.basis = Basis(x, up, z)

func on_deletion() -> void:
	pass
