class_name ScreenShake
extends Node3D

const MAX_TRAUMA: float = 1.0

@export var camera: Camera3D

var trauma: float = 0.0
var _base_rotation: Vector3
var _last_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	_base_rotation = camera.rotation

func _process(delta: float) -> void:
	camera.rotation -= _last_offset
	_base_rotation = camera.rotation

	trauma = max(trauma - GameTuning.SCREEN_SHAKE_DECAY * delta, 0.0)
	var amount := trauma * trauma
	_last_offset = Vector3(
		randf_range(-1, 1) * amount,
		randf_range(-1, 1) * amount,
		0.0
	) * GameTuning.SCREEN_SHAKE_AMOUNT_MULT
	camera.rotation = _base_rotation + _last_offset

func shake(amount: float = 1.0) -> void:
	trauma = min(trauma + amount, MAX_TRAUMA)
