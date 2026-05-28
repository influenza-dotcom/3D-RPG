class_name MouseInput
extends Node3D

## Mouse-look + fire input source. Captures the cursor and turns motion into a
## `rotate` signal; emits `attack` continuously while the fire button is held.

## Look delta, ALREADY scaled by sensitivity. NOTE the axis mapping: .x = PITCH delta
## (from vertical mouse motion), .y = YAW delta (from horizontal) — swapped vs the
## usual (x,y). Consumed by Head (pitch), the Player body (yaw), and GunMesh (sway).
signal rotate(_amt: Vector2)
## Emitted EVERY frame the "Attack" action is held (the full-auto driver). Per-click /
## semi-auto behaviour is enforced downstream in attack.gd via WeaponData.auto_fire.
## Carries the active viewport camera so the hitscan/aim origin is correct.
signal attack(_camera: Camera3D)

@export var player: CharacterBody3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := GameSettings.camera.mouse_sensitivity * speed_sensitivity_multiplier()
		var _rotation_amount := Vector2(-event.relative.y * sensitivity, -event.relative.x * sensitivity)
		rotate.emit(_rotation_amount)

func _process(_delta: float) -> void:
	if Input.is_action_pressed("Attack"):
		var _camera: Camera3D = get_viewport().get_camera_3d()
		attack.emit(_camera)

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
