extends RigidBody3D

@export var impact_sfx: AudioStreamPlayer3D

const PITCH_MIN: float = 0.7
const PITCH_MAX: float = 1.4

var _consumed: bool = false

func _on_body_entered(_body) -> void:
	if _consumed:
		return
	_consumed = true
	impact_sfx.reparent(get_tree().root)
	impact_sfx.global_position = global_position
	impact_sfx.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	impact_sfx.play()
	impact_sfx.finished.connect(impact_sfx.queue_free)
	queue_free()
