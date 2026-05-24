class_name ScopeIn
extends Node3D

@export var scoped_fov: float = 40.0
@export var normal_fov: float = 75.0
@export var zoom_speed: float = 8.0
@export var camera: Camera3D

signal scoped_in(_tf: bool)

func _process(delta: float) -> void:
	var target_fov = scoped_fov if Input.is_action_pressed("Zoom") else normal_fov
	if Input.is_action_just_pressed("Zoom"): 
		scoped_in.emit(true) 
	if Input.is_action_just_released("Zoom"): 
		scoped_in.emit(false)
	camera.fov = lerp(camera.fov, target_fov, delta * zoom_speed)
