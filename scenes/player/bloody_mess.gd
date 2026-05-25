extends Node3D

const BLOODY_MESS = preload("uid://yeq88l33gvle")

func particles(_last_velocity) -> void:
	var _particles = BLOODY_MESS.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position - _last_velocity.normalized() * 3.0
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)
