extends Node3D

const BLOODY_MESS = preload("uid://yeq88l33gvle")
const BLOOD_DROP = preload("res://scenes/effects/blood_drop.tscn")

const DROP_COUNT: int = 24
const DROP_SCATTER: float = 0.5
const DROP_VEL_MIN: float = 2.0
const DROP_VEL_MAX: float = 5.5

func particles(_offset: Vector3) -> void:
	var _particles = BLOODY_MESS.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position + _offset
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)

	_rain_drops(_particles.global_position)

func _rain_drops(origin: Vector3) -> void:
	for i in DROP_COUNT:
		var drop := BLOOD_DROP.instantiate()
		get_tree().root.add_child(drop)
		drop.global_position = origin + Vector3(
			randf_range(-DROP_SCATTER, DROP_SCATTER),
			randf_range(0.0, DROP_SCATTER),
			randf_range(-DROP_SCATTER, DROP_SCATTER)
		)
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.6, 1.5),
			randf_range(-1.0, 1.0)
		).normalized()
		drop.linear_velocity = dir * randf_range(DROP_VEL_MIN, DROP_VEL_MAX)
