class_name Head
extends Node3D

## Vertical look (pitch). Mouse yaw rotates the Player body; this node owns pitch
## (rotate_x) so camera/gun tilt up & down independently. Connected to MouseInput.rotate.

@export var pickup_ray: PickupRay

## Apply a mouse pitch delta with two feel tweaks:
##  1. Soft ramp: within `pitch_soft_ramp_deg` of a limit the delta is scaled toward
##     zero, so the view DECELERATES into the clamp instead of slamming a hard stop.
##  2. Holding an object tightens the up/down limit (pitch_max_holding_deg) so you
##     can't crane far enough to clip the carried crate into the camera.
func _on_mouse_input_rotate(_amt: Vector2) -> void:
	var max_up_deg: float = GameSettings.camera.pitch_max_deg
	var max_down_deg: float = GameSettings.camera.pitch_max_deg
	if pickup_ray and pickup_ray.held_object:
		max_up_deg = GameSettings.camera.pitch_max_holding_deg
		max_down_deg = GameSettings.camera.pitch_max_holding_deg
	var max_up := deg_to_rad(max_up_deg)
	var max_down := deg_to_rad(max_down_deg)
	var ramp := deg_to_rad(GameSettings.camera.pitch_soft_ramp_deg)

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
