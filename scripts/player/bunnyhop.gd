class_name Bunnyhop
extends Node

## Bunnyhop (bhop) chain system — the movement skill-expression mechanic. Rewards
## jumping again within a tight window right after landing: each well-timed
## consecutive hop ("chain") raises the target ground speed by a fixed increment,
## up to a hard cap. A mistimed / standing jump resets the chain.
##
## State only — never touches velocity. player.gd calls try_engage() on each jump
## and, if it returns true, overrides horizontal velocity with get_target_speed().
@export var character: CharacterBody3D

## Consecutive well-timed hop count. 0 = not bhopping (plain max_speed).
var chain: int = 0

## Seconds left in the post-landing window during which the next jump still
## extends the chain. Its size (GameSettings.bunnyhop.land_window) is the skill
## timing gate — smaller = harder to keep a chain alive.
var _land_window_timer: float = 0.0
## Previous-frame floor state, for edge-detecting the landing instant.
var _was_on_floor: bool = true


func _physics_process(delta: float) -> void:
	if not character:
		return

	var on_floor := character.is_on_floor()

	# Landing edge (air -> ground): open the hop window so an immediate re-jump
	# extends the chain. Otherwise bleed the window down toward zero.
	if on_floor and not _was_on_floor:
		_land_window_timer = GameSettings.bunnyhop.land_window
	else:
		_land_window_timer = max(
			_land_window_timer - delta,
			0.0
		)

	# Standing on the ground past the window kills the chain — you must keep
	# hopping to keep your speed. Guarded on _was_on_floor so the landing frame
	# itself can't break the chain before try_engage() reads the still-open window.
	if on_floor \
	and _was_on_floor \
	and _land_window_timer <= 0.0 \
	and chain > 0:
		break_chain()

	_was_on_floor = on_floor


## Called by player.gd at the instant of a jump. `has_movement_input` = the player
## is holding a move direction. Returns true if the bhop system engaged (player
## then applies get_target_speed()); false for a standing jump that shouldn't
## carry chain speed.
func try_engage(has_movement_input: bool) -> bool:
	# A bhop is a moving maneuver — a stationary jump never chains.
	if not has_movement_input:
		return false

	# Inside the window = a timed hop, extend the chain. Outside = a late/fresh
	# jump, restart at 1 (still a valid hop, just no accumulated boost yet).
	if _land_window_timer > 0.0:
		chain += 1
	else:
		chain = 1

	return true

## Target horizontal speed for the current chain length, clamped to the global
## bhop ceiling so a long chain can't grow speed unbounded.
func get_target_speed() -> float:
	if chain <= 0:
		return GameSettings.player_movement.max_speed

	return min(
		GameSettings.player_movement.max_speed
		+ chain * GameSettings.bunnyhop.boost_per_hop,
		GameSettings.bunnyhop.max_speed
	)


func break_chain() -> void:
	chain = 0
