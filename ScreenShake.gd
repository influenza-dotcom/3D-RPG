class_name ScreenShake
extends Node3D

@export var camera: Camera3D
@export var decay: float = 5.0
var trauma: float = 0.0

var _base_rotation: Vector3
var _last_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	_base_rotation = camera.rotation

func _process(delta: float) -> void:
	# Remove last frame's shake before reading current rotation,
	# so other systems can write to camera.rotation without us stomping them.
	camera.rotation -= _last_offset
	_base_rotation = camera.rotation

	trauma = max(trauma - decay * delta, 0.0)
	var amount = trauma * trauma
	_last_offset = Vector3(
		randf_range(-1, 1) * amount,
		randf_range(-1, 1) * amount,
		0.0
	) * 0.1
	camera.rotation = _base_rotation + _last_offset

func shake(amount: float = 1.0) -> void:
	trauma = min(trauma + amount, 1.0)
