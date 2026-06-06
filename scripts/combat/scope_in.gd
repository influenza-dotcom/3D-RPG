class_name ScopeIn
extends Node3D

@export var camera: Camera3D
@export var attack: Attack

signal scoped_in(_tf: bool)

var is_scoped: bool = false

func _process(delta: float) -> void:
	# No camera (e.g. an AI wielder) means no ADS at all — skip the whole thing.
	if not camera:
		return
	# Scope rules:
	#   - Can only ENTER scope when allowed to fire (no reload/swap/cooldown).
	#   - Reload or swap forcibly BREAKS scope (gun goes "down" for the anim).
	#   - Per-shot attack cooldown does NOT break scope (so rapid-fire stays smooth).
	#   - Re-enter is automatic if Zoom is still held after the interruption.
	# The spray can has no ADS — right-click opens its colour picker instead (see Attack).
	var spray_equipped := attack != null and attack.current_weapon != null and attack.current_weapon.is_spray_paint
	# A holstered weapon can't ADS (so it also can't scoped-air-dash); holstering mid-scope breaks it.
	var wants := Input.is_action_pressed("Zoom") and not spray_equipped and not (attack != null and attack.holstered) and not OptionsMenu.is_open() and not InventoryScreen.is_open()
	var can_scope := attack == null or (attack.can_fire() and attack.can_enter_scope())
	var must_break := attack != null and attack.is_reload_or_swap_active()

	# A scope weapon (sniper) commits you to a shot: once fired while scoped you can't unscope until the
	# shot finishes (its attack cadence elapses). Blocks only the VOLUNTARY release — a forced break
	# (reload/swap) still drops the scope.
	var shot_locked := attack != null and attack.current_weapon != null \
		and attack.current_weapon.disable_dof_while_scoped and attack.is_shot_in_progress()

	if is_scoped:
		if must_break or (not wants and not shot_locked):
			is_scoped = false
			scoped_in.emit(false)
	else:
		if wants and can_scope:
			is_scoped = true
			scoped_in.emit(true)

	var target_fov: float
	if is_scoped:
		# Per-weapon scope FOV (e.g. a sniper's deep zoom); 0 = use the global scoped FOV.
		if attack and attack.current_weapon and attack.current_weapon.scoped_fov_override > 0.0:
			target_fov = attack.current_weapon.scoped_fov_override
		else:
			target_fov = GameSettings.camera.scoped_fov
	else:
		target_fov = GameSettings.camera.default_fov
	var t := 1.0 - exp(-GameSettings.camera.scope_zoom_speed * delta)
	camera.fov = lerpf(camera.fov, target_fov, t)

# Force the scope off immediately (e.g. the melee dash). Safe to call when not
# scoped. The FOV lerp in _process eases back out on its own.
func force_unscope() -> void:
	if is_scoped:
		is_scoped = false
		scoped_in.emit(false)
