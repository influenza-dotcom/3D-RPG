extends Node3D

func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_x(_amt.x)
	rotation.x = clamp(rotation.x, deg_to_rad(-89), deg_to_rad(89))
