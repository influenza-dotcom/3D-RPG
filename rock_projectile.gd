extends Projectile

func _spawn_decal(last_velocity: Vector3) -> void:
	if last_velocity.is_zero_approx():
		return
	var decal = BULLET_HOLE_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.global_position = global_position
	decal.size = Vector3(0.3, 1.0, 0.3) * 10.0
