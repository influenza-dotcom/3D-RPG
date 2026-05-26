class_name Bunnyhop
extends Node

@export var character: CharacterBody3D

var chain: int = 0

var _land_window_timer: float = 0.0
var _was_on_floor: bool = true


func _physics_process(delta: float) -> void:
	if not character:
		return

	var on_floor := character.is_on_floor()

	# Detect landing and open hop window
	if on_floor and not _was_on_floor:
		_land_window_timer = GameTuning.BHOP_LAND_WINDOW
	else:
		_land_window_timer = max(
			_land_window_timer - delta,
			0.0
		)

	# Break chain if grounded too long
	if on_floor \
	and _was_on_floor \
	and _land_window_timer <= 0.0 \
	and chain > 0:
		break_chain()

	_was_on_floor = on_floor


func try_engage(has_movement_input: bool) -> bool:
	# Require any movement input
	if not has_movement_input:
		return false

	# Timed hop = extend chain
	if _land_window_timer > 0.0:
		chain += 1
	else:
		# Late jump starts a new chain
		chain = 1

	return true

func get_target_speed() -> float:
	if chain <= 0:
		return GameTuning.PLAYER_MAX_SPEED

	return min(
		GameTuning.PLAYER_MAX_SPEED
		+ chain * GameTuning.BHOP_BOOST_PER_HOP,
		GameTuning.BHOP_MAX_SPEED
	)


func break_chain() -> void:
	chain = 0
