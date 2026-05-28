class_name CoyoteTime
extends Node

## Coyote time — input forgiveness. Keeps "can jump" true for a brief window after
## the player walks off a ledge, so a slightly-late jump still fires. Grants no
## true air jump; it only widens the trailing edge of ground contact.
##
## player.gd calls tick(delta) once per physics frame BEFORE its jump check, gates
## the jump on can_jump(), and calls consume() when a jump is spent.
@export var character: CharacterBody3D

## Remaining coyote window in seconds. >0 ⇒ a ledge jump is still allowed.
var _timer: float = 0.0

func tick(delta: float) -> void:
	# Re-arm to the full window every grounded frame; only count down once
	# airborne, so the timer measures time-since-leaving-ground.
	if character.is_on_floor():
		_timer = GameSettings.player_movement.coyote_time
	else:
		_timer = max(_timer - delta, 0.0)

func can_jump() -> bool:
	return _timer > 0.0

## Zero the window so one ledge-leave can't yield two jumps.
func consume() -> void:
	_timer = 0.0
