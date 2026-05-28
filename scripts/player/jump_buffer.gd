class_name JumpBuffer
extends Node

## Jump buffering — input forgiveness, complementary to CoyoteTime. Remembers a
## jump press for a short window so a jump pressed just BEFORE landing fires the
## instant the player touches down, instead of being dropped. Coyote time covers
## the trailing edge of ground contact; this covers the leading edge.
##
## Self-contained input capture via _unhandled_input. player.gd polls wants_jump()
## each frame and calls consume() when the buffered jump is spent.

## Remaining buffer window in seconds. >0 ⇒ a recent jump press is still queued.
var _timer: float = 0.0

func _unhandled_input(event: InputEvent) -> void:
	# Input-map action is the literal lowercase "jump". A press (re)arms the
	# buffer; the intent is remembered for jump_buffer_time seconds.
	if event.is_action_pressed("jump"):
		_timer = GameSettings.player_movement.jump_buffer_time

func _physics_process(delta: float) -> void:
	_timer = max(_timer - delta, 0.0)

func wants_jump() -> bool:
	return _timer > 0.0

## Clear the buffer once the queued jump fires so it can't trigger twice.
func consume() -> void:
	_timer = 0.0
