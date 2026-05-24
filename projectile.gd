class_name Projectile
extends RigidBody3D

var direction: Vector3 = Vector3.FORWARD
var speed: float = 8.00
var damage: float = 2.50
var life_time: float = 10.0

var visual_only: bool = false

signal queued_for_deletion(_last_pos: Vector3)

func _ready() -> void:
	linear_velocity = direction * speed
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)
	await get_tree().create_timer(life_time).timeout
	if is_inside_tree():
		queue_free()

func _on_body_entered(body):
	linear_velocity = Vector3.ZERO 
	if visual_only:
		queue_free()
		return
	
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queued_for_deletion.emit(global_position)
	queue_free()

func _on_queued_for_deletion(_last_pos: Vector3) -> void:
	on_deletion()

func on_deletion() -> void:
	pass
