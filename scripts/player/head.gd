extends Node3D

func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_x(_amt.x)
	var limit := deg_to_rad(GameTuning.CAMERA_PITCH_LIMIT_DEG)
	rotation.x = clamp(rotation.x, -limit, limit)
