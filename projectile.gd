class_name Projectile
extends RigidBody3D

var direction: Vector3 = Vector3.FORWARD
var speed: float = 8.00
var damage: float = 2.50
var life_time: float = 10.0

var visual_only: bool = false

func _ready() -> void:
	linear_velocity = direction * speed
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)
	await get_tree().create_timer(life_time).timeout
	if is_inside_tree():
		queue_free()

func _on_body_entered(body):
	if visual_only:
		queue_free()
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
