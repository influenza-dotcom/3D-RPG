class_name Projectile
extends RigidBody3D

var direction: Vector3 = Vector3.FORWARD
var speed: float = 8.00
var damage: float = 2.50
var life_time: float = 10.0

var visual_only: bool = false

const DUST = preload("uid://um6f8g8g6l7v")
const BLOOD = preload("uid://c7v6vgs74fhn4")

const BULLET_HOLE_DECAL = preload("uid://dh1ydtvwvgiqg")
@onready var impact: AudioStreamPlayer3D = $Impact
const BLOOD_HOLE_DECAL = preload("uid://bkio8urva8hes")

signal queued_for_deletion(_last_pos: Vector3)

func _ready() -> void:
	linear_velocity = direction * speed
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)
	await get_tree().create_timer(life_time).timeout
	if is_inside_tree():
		queue_free()

func _on_body_entered(body):
	if body == get_parent():
		return
	var last_velocity = linear_velocity
	linear_velocity = Vector3.ZERO 
	
	var particles = BLOOD.instantiate() if body.has_method("take_damage") else DUST.instantiate()
	get_tree().root.add_child(particles)
	particles.global_position = global_position - last_velocity.normalized() * .1
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	
	if body.has_method("take_damage"):
		if !visual_only:
			body.take_damage(damage)
	else:
		_spawn_decal(last_velocity)
	
	if !visual_only:
		impact.reparent(get_tree().root)
		impact.play()
		impact.finished.connect(impact.queue_free)
	
	queued_for_deletion.emit(global_position)
	queue_free()

func _spawn_decal(last_velocity: Vector3) -> void:
	if last_velocity.is_zero_approx():
		return
	var decal = BULLET_HOLE_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.global_position = global_position
	decal.size = Vector3(0.3, 1.0, 0.3)

func _on_queued_for_deletion(_last_pos: Vector3) -> void:
	on_deletion()

func on_deletion() -> void:
	pass
