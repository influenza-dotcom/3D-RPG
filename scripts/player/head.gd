class_name Head
extends Node3D

## Vertical look (pitch) AND the camera-rig root. Mouse yaw rotates the Player body;
## this node owns pitch (rotate_x) so camera/gun tilt up & down independently (connected
## to MouseInput.rotate). As the rig root it also exposes the camera + screen-shake to the
## host and injects the wielder into the rig parts that point back out of it (setup()).

@export var pickup_ray: PickupRay

## The first-person camera (FOV/bob/tilt), exposed so the host reads it off this rig
## interface instead of reaching down a deep NodePath into the camera nesting.
var camera: CameraEffects:
	get:
		return get_node_or_null("ScreenShake/Camera3D") as CameraEffects

## The shake pivot (the camera is its child), likewise exposed off the rig root.
var screen_shake: ScreenShake:
	get:
		return get_node_or_null("ScreenShake") as ScreenShake

## Inject the wielder into the rig parts that reference back out of it — the camera
## (CameraEffects.player) and the pickup raycast (PickupRay.player) — and re-wire the
## pitch-look signal into this Head. Extracting the rig drops the MouseInput.rotate ->
## Head scene connection, so the host hands its MouseInput here to reconnect it. Also
## builds the FPS view-model camera (the gun's own render pass; see ViewModelCamera) as a
## child of the main camera, handing it the HUD layer for its composite. Called once by
## the host from _enter_tree.
func setup(player: Character, mouse_input: MouseInput, ui: CanvasLayer = null) -> void:
	var cam := camera
	if cam:
		cam.player = player
		_setup_view_model_camera(cam, ui)
	var rc := get_node_or_null("ScreenShake/Camera3D/RayCast") as PickupRay
	if rc:
		rc.player = player
	mouse_input.rotate.connect(_on_mouse_input_rotate)

## Create the dedicated view-model camera in code (house pref: code over a new .tscn) as a child
## of the main camera, so it inherits the live camera's world transform and we can mirror its FOV.
## A no-op render-wise until ViewModelCamera.enabled is turned on (off by default → the gun keeps
## rendering on the main camera, game unchanged). Guarded so a second setup() call (it shouldn't
## happen, but the host is defensive) doesn't stack a second pass.
func _setup_view_model_camera(cam: CameraEffects, ui: CanvasLayer) -> void:
	if cam.get_node_or_null("ViewModelCamera") != null:
		return
	var vm := ViewModelCamera.new()
	vm.name = "ViewModelCamera"
	vm.enabled = true  # the player's view model renders via its OWN camera (the requested FPS pass)
	cam.add_child(vm)
	vm.setup(cam, ui)

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
