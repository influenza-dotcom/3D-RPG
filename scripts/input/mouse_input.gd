extends Node3D

signal rotate(_amt: Vector2)
signal attack(_camera: Camera3D)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := GameTuning.MOUSE_SENSITIVITY
		var _rotation_amount := Vector2(-event.relative.y * sensitivity, -event.relative.x * sensitivity)
		rotate.emit(_rotation_amount)

func _process(_delta: float) -> void:
	if Input.is_action_pressed("Attack"):
		var _camera: Camera3D = get_viewport().get_camera_3d()
		attack.emit(_camera)
