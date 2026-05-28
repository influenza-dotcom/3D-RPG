class_name ScopeIn
extends Node3D

@export var camera: Camera3D
@export var attack: Attack

signal scoped_in(_tf: bool)

var is_scoped: bool = false

func _process(delta: float) -> void:
	# Scope rules:
	#   - Can only ENTER scope when allowed to fire (no reload/swap/cooldown).
	#   - Reload or swap forcibly BREAKS scope (gun goes "down" for the anim).
	#   - Per-shot attack cooldown does NOT break scope (so rapid-fire stays smooth).
	#   - Re-enter is automatic if Zoom is still held after the interruption.
	var wants := Input.is_action_pressed("Zoom")
	var can_scope := attack == null or attack.can_fire()
	var must_break := attack != null and attack.is_reload_or_swap_active()

	if is_scoped:
		if not wants or must_break:
			is_scoped = false
			scoped_in.emit(false)
	else:
		if wants and can_scope:
			is_scoped = true
			scoped_in.emit(true)

	var target_fov: float = GameSettings.camera.scoped_fov if is_scoped else GameSettings.camera.default_fov
	var t := 1.0 - exp(-GameSettings.camera.scope_zoom_speed * delta)
	camera.fov = lerpf(camera.fov, target_fov, t)
