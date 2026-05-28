class_name JumpBuffer
extends Node

var _timer: float = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		_timer = GameSettings.player_movement.jump_buffer_time

func _physics_process(delta: float) -> void:
	_timer = max(_timer - delta, 0.0)

func wants_jump() -> bool:
	return _timer > 0.0

func consume() -> void:
	_timer = 0.0
