extends Projectile

const DUST_LARGE = preload("uid://ckxkt0g5gq8bb")

const ROCK_DECAL_SCALE: float = 10.0
const ROCK_DECAL_PROBE_DISTANCE: float = 0.8
const ROCK_DECAL_NORMAL_OFFSET: float = 0.05

func _spawn_decal(last_velocity: Vector3) -> void:
	if last_velocity.is_zero_approx():
		return
	var dir := last_velocity.normalized()
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position - dir * ROCK_DECAL_PROBE_DISTANCE,
		global_position + dir * ROCK_DECAL_PROBE_DISTANCE
	)
	var result := space_state.intersect_ray(query)

	var decal := BULLET_HOLE_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.size = DECAL_SIZE * ROCK_DECAL_SCALE
	decal.cull_mask = DECAL_CULL_MASK

	if result:
		decal.global_position = result.position + result.normal * ROCK_DECAL_NORMAL_OFFSET
		_orient_decal_to_normal(decal, result.normal)
	else:
		decal.global_position = global_position

func particles(_body, _last_velocity) -> void:
	var _particles = DUST_LARGE.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position - _last_velocity.normalized() * PARTICLE_BACKOFF
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)
