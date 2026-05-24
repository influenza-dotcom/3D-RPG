extends Projectile

const DUST_LARGE = preload("uid://ckxkt0g5gq8bb")

func _spawn_decal(last_velocity: Vector3) -> void:
	if last_velocity.is_zero_approx():
		return
	var decal = BULLET_HOLE_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.global_position = global_position
	decal.size = Vector3(0.3, 1.0, 0.3) * 10.0
	decal.cull_mask = 2 

func particles(_body, _last_velocity) -> void:
	var _particles = DUST_LARGE.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position - _last_velocity.normalized() * .1
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)
