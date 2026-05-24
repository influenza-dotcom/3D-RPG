extends Projectile

const DUST_LARGE = preload("uid://ckxkt0g5gq8bb")

func _spawn_decal(last_velocity: Vector3) -> void:
	if last_velocity.is_zero_approx():
		return
	var dir = last_velocity.normalized()
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position - dir * 0.8,
		global_position + dir * 0.8
	)
	var result = space_state.intersect_ray(query)

	var decal = BULLET_HOLE_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.size = Vector3(0.3, 1.0, 0.3) * 10.0
	decal.cull_mask = 2

	if result:
		decal.global_position = result.position + result.normal * 0.05
		_orient_decal_to_normal(decal, result.normal)
	else:
		decal.global_position = global_position

func particles(_body, _last_velocity) -> void:
	var _particles = DUST_LARGE.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position - _last_velocity.normalized() * .1
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)
