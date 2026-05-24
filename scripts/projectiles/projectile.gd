class_name Projectile
extends RigidBody3D

var direction: Vector3 = Vector3.FORWARD
var speed: float = 8.00
var damage: float = 2.50
var life_time: float = 10.0
var knockback: float = 0.0
var knockback_direction: Vector3 

var visual_only: bool = false

const DUST = preload("uid://um6f8g8g6l7v")
const BLOOD = preload("uid://c7v6vgs74fhn4")

const BULLET_HOLE_DECAL = preload("uid://dh1ydtvwvgiqg")
const BLOOD_HOLE_DECAL = preload("uid://bkio8urva8hes")
@onready var impact_enemy_hit: AudioStreamPlayer3D = $ImpactEnemyHit
@onready var impact_generic: AudioStreamPlayer3D = $ImpactGeneric

signal queued_for_deletion(_last_pos: Vector3)

func _ready() -> void:
	linear_velocity = direction * speed
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)
	await get_tree().create_timer(life_time).timeout
	if is_inside_tree():
		queue_free()

func particles(_body, _last_velocity) -> void:
	var _particles = BLOOD.instantiate() if _body.has_method("take_damage") else DUST.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position - _last_velocity.normalized() * .1
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)

func _on_body_entered(body):
	if body == get_parent():
		return
	var last_velocity = linear_velocity
	linear_velocity = Vector3.ZERO 
	
	particles(body, last_velocity)
	
	if body.has_method("take_damage"):
		if !visual_only:
			body.take_damage(damage)
			impact_enemy_hit.reparent(get_tree().root)
			impact_enemy_hit.play()
			impact_enemy_hit.finished.connect(impact_enemy_hit.queue_free)
	else:
		_spawn_decal(last_velocity)
		if !visual_only:
			impact_generic.reparent(get_tree().root)
			impact_generic.play()
			impact_generic.finished.connect(impact_generic.queue_free)
	

	
	queued_for_deletion.emit(global_position)
	queue_free()

func _spawn_decal(last_velocity: Vector3) -> void:
	if last_velocity.is_zero_approx():
		return
	var dir = last_velocity.normalized()
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position - dir * 0.5,
		global_position + dir * 0.5
	)
	var result = space_state.intersect_ray(query)

	var decal = BULLET_HOLE_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.size = Vector3(0.3, 1.0, 0.3)
	decal.cull_mask = 2

	if result:
		decal.global_position = result.position + result.normal * 0.02
		_orient_decal_to_normal(decal, result.normal)
	else:
		decal.global_position = global_position - dir * 0.05


func _on_queued_for_deletion(_last_pos: Vector3) -> void:
	on_deletion()

# Decals project along their -Y axis, so align +Y with the surface normal.
func _orient_decal_to_normal(decal: Decal, normal: Vector3) -> void:
	var up = normal
	var ref = Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var right = ref.cross(up).normalized()
	var forward = up.cross(right).normalized()
	decal.global_transform.basis = Basis(right, up, forward)

func on_deletion() -> void:
	pass
