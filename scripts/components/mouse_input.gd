class_name MouseInput
extends Node3D

## Mouse-look + fire input source. Captures the cursor and turns motion into a
## `rotate` signal; emits `attack` continuously while the fire button is held.
##
## UNITS: mouse look is radians per SCREEN pixel — the motion read is InputEventMouseMotion.screen_relative
## (raw OS pixels), NEVER `relative`. Under the project's `viewport` stretch mode the engine pre-scales
## `relative` by canvas/window width (792/1920 = 0.41 in 1080p fullscreen, 792/1600 = 0.50 in the 1600x900
## window, 792/1280 = 0.62 at 720p, 792/3840 = 0.21 at 4K), so the same hand motion used to turn the view
## 1.2-1.5x further the moment the game went windowed and half as far on a 4K screen. screen_relative is
## window/resolution independent; GameSettings.camera.mouse_sensitivity (+ Settings.SENS_MIN/MAX and the
## Options slider) are tuned in that unit — 0.002 canvas-px x 792/1920 = 0.000825, so 1080p fullscreen
## feels exactly as it did. tests/test_camera_input_ui.gd pins the read; a legacy settings.cfg value is
## rescaled once by Settings.read_mouse_sensitivity.

## Look delta, ALREADY scaled by sensitivity. NOTE the axis mapping: .x = PITCH delta
## (from vertical mouse motion), .y = YAW delta (from horizontal) — swapped vs the
## usual (x,y). Consumed by Head (pitch), the Player body (yaw), and GunMesh (sway).
signal rotate(_amt: Vector2)
## Emitted EVERY frame the "Attack" action is held (the full-auto driver). Per-click /
## semi-auto behaviour is enforced downstream in attack.gd via WeaponData.auto_fire.
## Carries the active viewport camera so the hitscan/aim origin is correct.
signal attack(_camera: Camera3D)
## Emitted EVERY frame the ALT fire action is held — the second attack button. Only weapons that opt in react
## (Attack gates it on WeaponData.view_model_punch): unarmed throws the RIGHT fist with it, while for a gun the
## same button is ADS and this is ignored. Same cadence rules as `attack`; carries the same camera.
signal alt_attack(_camera: Camera3D)

## The player body this look-input drives — its horizontal speed scales look sensitivity down at bhop
## speeds (see speed_sensitivity_multiplier). Wire to the Player; null = no speed-based falloff.
@export var player: CharacterBody3D
## The SECOND attack button, for weapons that punch with either hand. Defaults to the ADS button, which is free
## exactly when it matters: a punching weapon sets no_ads, so ScopeIn already refuses to scope with it out.
@export var alt_attack_action: StringName = &"Zoom"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sensitivity := GameSettings.camera.mouse_sensitivity * speed_sensitivity_multiplier()
		# screen_relative (unscaled OS pixels), not `relative` — see the header: `relative` rides the window size.
		var pitch := -mm.screen_relative.y * sensitivity
		if Settings.invert_look_y:
			pitch = -pitch
		rotate.emit(Vector2(pitch, -mm.screen_relative.x * sensitivity))

func _process(delta: float) -> void:
	if not InputManager.gameplay_suppressed():
		var _camera: Camera3D = get_viewport().get_camera_3d()
		if Input.is_action_pressed("Attack"):
			attack.emit(_camera)
		if Input.is_action_pressed(alt_attack_action):
			alt_attack.emit(_camera)
	_controller_look(delta)

## Right-stick look: read the look_* action set (bound to the right stick by InputManager) and feed the
## same `rotate` signal as the mouse. Scaled by delta (per-frame, unlike mouse relative motion) and the
## same speed-sensitivity falloff. Honors the invert-Y option. Only while the cursor is captured.
func _controller_look(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look.length_squared() < 0.0001:
		return
	var sens := Settings.controller_look_sensitivity * speed_sensitivity_multiplier() * delta
	var pitch := -look.y * sens
	if Settings.invert_look_y:
		pitch = -pitch
	rotate.emit(Vector2(pitch, -look.x * sens))

## Scale look sensitivity DOWN as horizontal speed rises (toward sens_min_multiplier
## at bhop max_speed) so high-speed bunnyhop runs don't feel twitchy. Reuses the
## bunnyhop speed thresholds; returns 1.0 (no change) below the threshold.
func speed_sensitivity_multiplier() -> float:
	if not player:
		return 1.0
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	var thr := GameSettings.bunnyhop.sens_reduction_threshold
	var cap := GameSettings.bunnyhop.max_speed
	if hspeed <= thr or cap <= thr:
		return 1.0
	var t := clampf((hspeed - thr) / (cap - thr), 0.0, 1.0)
	return lerpf(1.0, GameSettings.bunnyhop.sens_min_multiplier, t)
