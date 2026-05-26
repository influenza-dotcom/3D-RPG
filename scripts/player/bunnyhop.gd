class_name Bunnyhop
extends Node

@export var character: CharacterBody3D

var chain: int = 0

var _land_window_timer: float = 0.0
var _crouch_press_timer: float = 0.0
var _was_on_floor: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Crouch"):
		_crouch_press_timer = GameTuning.BHOP_INPUT_WINDOW

func _physics_process(delta: float) -> void:
	if not character:
		return
	var on_floor := character.is_on_floor()
	if on_floor and not _was_on_floor:
		_land_window_timer = GameTuning.BHOP_LAND_WINDOW
	else:
		_land_window_timer = max(_land_window_timer - delta, 0.0)
	_was_on_floor = on_floor
	_crouch_press_timer = max(_crouch_press_timer - delta, 0.0)

func try_engage(forward_held: bool) -> bool:
	if not forward_held or _crouch_press_timer <= 0.0:
		chain = 0
		return false
	if _land_window_timer > 0.0:
		chain += 1
	else:
		chain = 1
	return true

func get_target_speed() -> float:
	if chain <= 0:
		return GameTuning.PLAYER_MAX_SPEED
	return min(GameTuning.PLAYER_MAX_SPEED + chain * GameTuning.BHOP_BOOST_PER_HOP, GameTuning.BHOP_MAX_SPEED)

func break_chain() -> void:
	chain = 0
