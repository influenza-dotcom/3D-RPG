extends Node3D

@export var jetpack_active: bool = false

@export var player: Character
@export var fly_rate: float 

@export var activate_flight: bool = false

func _process(_delta: float) -> void:
	if jetpack_active:
		if !player.is_on_floor():
			if Input.is_action_just_pressed("jump"):
				activate_flight = true
			if Input.is_action_just_released("jump"):
				activate_flight = false
		elif player.is_on_floor():
			activate_flight = false
		
		if activate_flight:
			player.velocity.y = fly_rate
	else:
		activate_flight = false
