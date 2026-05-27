class_name Head
extends Node3D

@export var pickup_ray: PickupRay

func _on_mouse_input_rotate(_amt: Vector2) -> void:
	var max_up_deg: float = GameTuning.CAMERA_PITCH_LIMIT_DEG
	var max_down_deg: float = GameTuning.CAMERA_PITCH_LIMIT_DEG
	if pickup_ray and pickup_ray.held_object:
		max_up_deg = GameTuning.CAMERA_PITCH_LIMIT_HOLDING_DEG
		max_down_deg = GameTuning.CAMERA_PITCH_LIMIT_HOLDING_DEG
	var max_up := deg_to_rad(max_up_deg)
	var max_down := deg_to_rad(max_down_deg)
	var ramp := deg_to_rad(GameTuning.CAMERA_PITCH_SOFT_RAMP_DEG)

	var delta_x := _amt.x
	if delta_x > 0.0:
		var zone := minf(ramp, max_up * 0.5)
		if zone > 0.0001:
			var headroom := max_up - rotation.x
			delta_x *= clampf(headroom / zone, 0.0, 1.0)
	elif delta_x < 0.0:
		var zone := minf(ramp, max_down * 0.5)
		if zone > 0.0001:
			var headroom := rotation.x + max_down
			delta_x *= clampf(headroom / zone, 0.0, 1.0)

	rotate_x(delta_x)
	rotation.x = clamp(rotation.x, -max_down, max_up)
