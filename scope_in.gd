class_name ScopeIn
extends Node3D

@export var scoped_fov: float = 40.0
@export var normal_fov: float = 75.0
@export var zoom_speed: float = 8.0
@export var camera: Camera3D

func _process(delta: float) -> void:
	var target_fov = scoped_fov if Input.is_action_pressed("Zoom") else normal_fov
	camera.fov = lerp(camera.fov, target_fov, delta * zoom_speed)
