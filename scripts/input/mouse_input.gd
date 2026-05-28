class_name MouseInput
extends Node3D

signal rotate(_amt: Vector2)
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
