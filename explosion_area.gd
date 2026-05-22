class_name Explosion
extends Area3D

@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0

func _on_body_entered(body: Node3D) -> void:
	print(body)
	if body is Character:
		var distance_to_blast = body.global_position.distance_to(global_position)
		
		if distance_to_blast > explosion_radius:
			return
		
		var force_multiplier = 1.0 - (distance_to_blast / explosion_radius)
		
		var applied_force = max_explosion_force * force_multiplier
		
		var push_direction = global_position.direction_to(body.global_position)
		
		push_direction = push_direction.normalized()
		
		if body.has_method("take_damage"):
			body.take_damage(1)
		
		body.explosion_velocity += push_direction.normalized() * applied_force
	else:
		return


func _on_timer_timeout() -> void:
	queue_free()
