class_name Bunnyhop
extends Node

## Bunnyhop (bhop) chain system — the movement skill-expression mechanic. Rewards
## jumping again within a tight window right after landing: each well-timed
## consecutive hop ("chain") ADDS boost_per_hop to the speed you carried INTO the
## hop, up to a hard cap. A mistimed / standing jump resets the chain.
##
## ⭐⭐THE CHIP IS THE ONLY WAY TO *GAIN* MOMENTUM — that is the whole product, and it is
## why this builds on the carried speed rather than stamping an absolute ladder. Without
## the implant a jump gets PlayerMovementSettings.jump_momentum_boost: a one-shot +15% of
## the speed you ran in with, which cannot accumulate (AirMovement.takeoff_speed withholds
## it above the ground target) and decays straight back to run speed. With the implant every
## timed hop compounds on the last one: 6.95, 7.89, 8.70 ... up to BunnyhopSettings.max_speed.
## Simple boost vs. real acceleration.
##
## It used to stamp `max_speed + chain * boost_per_hop` outright, which IGNORED your momentum
## entirely: a chip holder jogging at 1 m/s was stamped straight to 6.2, and a 12 m/s grapple
## fling was stamped DOWN to 6.2 by its own first hop. Building on the carry fixes both — a
## slow start now has to be ramped in, and the chain can never claw back speed you arrived with
## (`maxf` below), so the ceiling only ever stops it ADDING.
##
## State only — never touches velocity. player.gd calls try_engage() on each jump
## and, if it returns true, overrides horizontal velocity with get_target_speed().
##
## The STANCE gates live on the host, not here: an over-encumbered or CROUCHED jump goes
## straight to break_chain() and never reaches try_engage(), so a sneaking player can't hop
## their way past the crouch speed penalty. This node only knows timing + movement input.
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


## Called by player.gd at the instant of a jump — only for jumps that PASSED the host's
## stance gates (see the header: crouched / over-encumbered never get here).
## `has_movement_input` = the player is holding a move direction. Returns true if the bhop
## system engaged (player then applies get_target_speed()); false for a standing jump that
## shouldn't carry chain speed.
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

## Target horizontal speed for THIS hop: the speed carried into it PLUS one boost_per_hop,
## clamped to the global bhop ceiling so a long chain can't grow unbounded. `carried_speed` is
## the player's horizontal speed at the instant of the jump (player.gd measures it right before
## the stamp, so it already includes the free take-off boost — the implant builds on top of it).
##
## Accumulation lives in the VELOCITY, not in the `chain` counter: the counter is the timing
## state (are we still chaining?), and the speed compounds because each hop's carry is the last
## hop's result. That is what makes this a momentum GAIN rather than a lookup table.
##
## ⭐The maxf floor means this can only ever ADD. Above the ceiling it returns the carry
## untouched instead of dragging a grapple fling / air dash / blast down to the chain value.
func get_target_speed(carried_speed: float) -> float:
	if chain <= 0:
		# Defensive: player.gd only stamps when try_engage() returned true, which always leaves
		# chain >= 1. Degrade to plain run speed without ever reducing what we were handed.
		return maxf(carried_speed, GameSettings.player_movement.max_speed)

	return maxf(carried_speed, minf(
		carried_speed + GameSettings.bunnyhop.boost_per_hop,
		GameSettings.bunnyhop.max_speed
	))


func break_chain() -> void:
	chain = 0
