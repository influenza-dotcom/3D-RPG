class_name Head
extends Node3D

## Vertical look (pitch) AND the camera-rig root. Mouse yaw rotates the Player body;
## this node owns pitch (rotate_x) so camera/gun tilt up & down independently (connected
## to MouseInput.rotate). As the rig root it also exposes the camera + screen-shake to the
## host and injects the wielder into the rig parts that point back out of it (setup()).

@export var pickup_ray: PickupRay

## Ease speed for CONTRACTING the pitch clamp toward a smaller limit (climb ends, or you pick an object
## up): the view reels into range smoothly instead of snapping. Expansion is instant (see _process).
const PITCH_RECENTER_SPEED: float = 8.0

## The wielder, cached in setup() — read to widen the look-pitch clamp while wall-climbing.
var _player: Character
## The currently-APPLIED pitch limit (radians). Eased toward _target_max_pitch() each frame: expands
## instantly (look up the moment you start climbing) but contracts gently (no snap when the limit shrinks).
var _max_pitch: float = deg_to_rad(89.0)

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
	_player = player
	_max_pitch = _target_max_pitch()
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

## The pitch limit the look SHOULD currently obey, in RADIANS: tightened while carrying an object (so you
## can't crane the crate into the camera), widened while wall-climbing (look up + over the wall), else the
## normal limit. The APPLIED limit (_max_pitch) eases toward this in _process.
func _target_max_pitch() -> float:
	if pickup_ray and pickup_ray.held_object:
		return deg_to_rad(GameSettings.camera.pitch_max_holding_deg)
	if _is_climbing():
		# Past 90° the camera tips backward over the lip — "walking onto a new plane".
		return deg_to_rad(GameSettings.camera.pitch_max_climbing_deg)
	return deg_to_rad(GameSettings.camera.pitch_max_deg)

## Apply a mouse pitch delta with two feel tweaks:
##  1. Soft ramp: within `pitch_soft_ramp_deg` of the limit the delta is scaled toward zero, so the view
##     DECELERATES into the clamp instead of slamming a hard stop.
##  2. The limit itself flexes (_max_pitch) — tighter while carrying, wider while climbing. It's widened
##     INSTANTLY here so the very first look already has the new range; shrinking is eased in _process,
##     so a clamp-down (e.g. a climb ending) never snaps the view.
func _on_mouse_input_rotate(_amt: Vector2) -> void:
	var target := _target_max_pitch()
	if target > _max_pitch:
		_max_pitch = target
	var ramp := deg_to_rad(GameSettings.camera.pitch_soft_ramp_deg)

	var delta_x := _amt.x
	if delta_x > 0.0:
		var zone := minf(ramp, _max_pitch * 0.5)
		if zone > 0.0001:
			delta_x *= clampf((_max_pitch - rotation.x) / zone, 0.0, 1.0)
	elif delta_x < 0.0:
		var zone := minf(ramp, _max_pitch * 0.5)
		if zone > 0.0001:
			delta_x *= clampf((rotation.x + _max_pitch) / zone, 0.0, 1.0)

	rotate_x(delta_x)
	rotation.x = clamp(rotation.x, -_max_pitch, _max_pitch)

## True while the wielder is scaling a wall — widens the pitch clamp (climbing on a new plane).
func _is_climbing() -> bool:
	var p := _player as Player
	return p != null and p.is_climbing()

## Ease the applied pitch clamp toward its target every frame: EXPAND instantly (look up the moment you
## climb / drop a carried object), but CONTRACT gently — when the limit shrinks below the current look
## angle (climb ended, or you picked something up) the view reels back into range smoothly instead of
## snapping on the next mouse move. Re-clamping each frame is what moves the camera during a contraction;
## while the look already sits within the limit it's a harmless no-op.
func _process(delta: float) -> void:
	var target := _target_max_pitch()
	if target > _max_pitch:
		_max_pitch = target
	else:
		_max_pitch = lerpf(_max_pitch, target, 1.0 - exp(-PITCH_RECENTER_SPEED * delta))
	rotation.x = clamp(rotation.x, -_max_pitch, _max_pitch)
