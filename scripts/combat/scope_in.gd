class_name ScopeIn
extends Node3D

@export var camera: Camera3D

signal scoped_in(_tf: bool)

func _process(delta: float) -> void:
	var target_fov: float = GameTuning.CAMERA_SCOPED_FOV if Input.is_action_pressed("Zoom") else GameTuning.CAMERA_DEFAULT_FOV
	if Input.is_action_just_pressed("Zoom"):
		scoped_in.emit(true)
	if Input.is_action_just_released("Zoom"):
		scoped_in.emit(false)
	camera.fov = lerp(camera.fov, target_fov, delta * GameTuning.CAMERA_SCOPE_ZOOM_SPEED)
