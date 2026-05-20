extends Node3D

signal rotate(_amt: Vector2)
signal attack(_camera: Camera3D)

var mouse_sensitivity = 0.002

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var _rotation_amount: Vector2 = Vector2(-event.relative.y * mouse_sensitivity, -event.relative.x * mouse_sensitivity)
		rotate.emit(_rotation_amount)
	
	if event.is_action_pressed("Attack"):
		var _camera: Camera3D = get_viewport().get_camera_3d()
		attack.emit(_camera)
