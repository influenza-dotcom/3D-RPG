class_name ScopeIn
extends Node3D

@export var camera: Camera3D

signal scoped_in(_tf: bool)

var is_scoped: bool = false

func _process(delta: float) -> void:
	var target_fov: float = GameTuning.CAMERA_SCOPED_FOV if Input.is_action_pressed("Zoom") else GameTuning.CAMERA_DEFAULT_FOV
	if Input.is_action_just_pressed("Zoom"):
		is_scoped = true
		scoped_in.emit(true)
	if Input.is_action_just_released("Zoom"):
		is_scoped = false
		scoped_in.emit(false)
	var t := 1.0 - exp(-GameTuning.CAMERA_SCOPE_ZOOM_SPEED * delta)
	camera.fov = lerpf(camera.fov, target_fov, t)
