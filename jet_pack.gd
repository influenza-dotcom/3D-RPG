extends Node3D

@export var player: Character
@export var fly_rate: float = 10.0

@export var activate_flight: bool = false

func _process(delta: float) -> void:
	if !player.is_on_floor():
		if Input.is_action_just_pressed("jump"):
			activate_flight = true
		if Input.is_action_just_released("jump"):
			activate_flight = false
	elif player.is_on_floor():
		activate_flight = false
	
	if activate_flight:
		player.velocity.y += fly_rate*delta
