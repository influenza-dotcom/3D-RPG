class_name ScreenShake
extends Node3D

@export var camera: Camera3D
@export var decay: float = 5.0
var trauma: float = 0.0
var _origin: Vector3

func _ready() -> void:
	_origin = position

func _process(delta: float) -> void:
	trauma = max(trauma - decay * delta, 0.0)
	var amount = trauma * trauma
	camera.rotation = _origin + Vector3(
		randf_range(-1, 1) * amount,
		randf_range(-1, 1) * amount,
		0.0
	) * 0.1

func shake(amount: float = 1.0) -> void:
	trauma = min(trauma + amount, 1.0)
