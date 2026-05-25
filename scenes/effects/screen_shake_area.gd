extends Area3D

@export var collision_shape_3d: CollisionShape3D
@export var explosion_area: Explosion

func _on_body_entered(body: Node3D) -> void:
	if body is Player and explosion_area.allowed_shake_screen:
		var distance_to_blast := body.global_position.distance_to(global_position)
		var force_multiplier := (distance_to_blast / (collision_shape_3d.shape as SphereShape3D).radius)
		var shake_amount := force_multiplier

		var screen_shake = body.screen_shake
		if screen_shake:
			screen_shake.shake(shake_amount)
