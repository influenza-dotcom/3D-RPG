class_name CoyoteTime
extends Node

@export var character: CharacterBody3D

var _timer: float = 0.0

func tick(delta: float) -> void:
	if character.is_on_floor():
		_timer = GameSettings.player_movement.coyote_time
	else:
		_timer = max(_timer - delta, 0.0)

func can_jump() -> bool:
	return _timer > 0.0

func consume() -> void:
	_timer = 0.0
