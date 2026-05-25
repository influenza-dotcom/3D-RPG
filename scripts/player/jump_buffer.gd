class_name JumpBuffer
extends Node

var _timer: float = 0.0

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_timer = GameTuning.JUMP_BUFFER_TIME
	else:
		_timer = max(_timer - delta, 0.0)

func wants_jump() -> bool:
	return _timer > 0.0

func consume() -> void:
	_timer = 0.0
