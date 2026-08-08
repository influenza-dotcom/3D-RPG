class_name ScopeIn
extends Node3D

## The first-person camera whose fov this lerps between default and scoped FOV. Empty = an AI wielder with no camera, so ADS is skipped entirely.
@export var camera: Camera3D
## The weapon's attack, polled to decide when ADS is allowed: can't scope while reloading/swapping/cooling down, the spray can has no ADS, and a fired sniper locks the scope until the shot finishes.
@export var attack: Attack

signal scoped_in(_tf: bool)

const CAMERA_FOV_MIN := 1.0
const CAMERA_FOV_MAX := 179.0

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
	# Weapons flagged no_ads (the fists / bare hands — nothing to sight down) can't scope at all.
	var no_ads_weapon := attack != null and attack.current_weapon != null and attack.current_weapon.no_ads
	# A holstered weapon can't ADS (so it also can't scoped-air-dash); holstering mid-scope breaks it.
	# A DEAD wielder can't ADS either: Player.die() kills look/auto-fire by process-disabling MouseInput,
	# but this node polls Zoom in its OWN _process, which keeps running through the death cinematic — so
	# without a liveness gate the corpse could still scope in (death isn't in gameplay_suppressed()'s truth
	# set; that's modals/cutscenes only). Gating `wants` (not early-returning) means dying while scoped
	# also BREAKS the scope and the FOV lerp below eases back out under the cinematic. The checkpoint
	# revive clears the death latch before handing input back, so ADSing across a respawn (Zoom held
	# through the revive) still works — deliberately; see ScopeCoordinator._duck_music_for_scope.
	var wielder_dead := attack != null and attack.character != null and not attack.character.is_alive()
	var wants := Input.is_action_pressed("Zoom") and not spray_equipped and not no_ads_weapon and not (attack != null and attack.holstered) and not wielder_dead and not InputManager.gameplay_suppressed()
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

	# DialogueController drives CameraEffects.dialogue_fov during conversation focus. Let that camera-side
	# owner win instead of easing the unscoped FOV back to default over the top of it.
	if camera is CameraEffects and (camera as CameraEffects).dialogue_fov > 0.0:
		return

	var target_fov: float
	if is_scoped:
		# Per-weapon scope FOV (e.g. a sniper's deep zoom); 0 = use the global scoped FOV. That override is an
		# ABSOLUTE angle on purpose — a scope is a fixed optic, so its magnification is a property of the weapon
		# rather than of the player's FOV preference. Everything else goes through the magnification model.
		if attack and attack.current_weapon and attack.current_weapon.scoped_fov_override > 0.0:
			target_fov = attack.current_weapon.scoped_fov_override
		else:
			target_fov = global_scoped_fov()
	else:
		target_fov = GameSettings.camera.default_fov
	target_fov = _clamp_camera_fov(target_fov)
	var t := 1.0 - exp(-GameSettings.camera.scope_zoom_speed * delta)
	camera.fov = _clamp_camera_fov(lerpf(camera.fov, target_fov, t))

# Force the scope off immediately (e.g. the melee dash). Safe to call when not
# scoped. The FOV lerp in _process eases back out on its own.
func force_unscope() -> void:
	if is_scoped:
		is_scoped = false
		scoped_in.emit(false)


## The ADS target FOV for any weapon without its own scoped_fov_override.
##
## SOLVED from the player's current rest FOV so the zoom STRENGTH is invariant under the Field of View setting:
## scope_magnification 2.108 means "aiming brings the world 2.108x closer" whether the player rests at 75 or at
## 120. The old shape — pinning ADS to one absolute angle — made the zoom silently stronger every time the FOV
## slider went up (at 110 rest, a 40-degree scope is a 3.9x jump instead of the intended 2.1x). Set
## scope_magnification to 0 to get that absolute behaviour back.
##
## Magnification is a TANGENT ratio because a distant object's on-screen size goes with tan(fov/2), not with the
## FOV in degrees — so this is NOT `default_fov / magnification`. Public so the camera/HUD side and the contract
## test can ask what ADS is currently worth without re-deriving the formula.
func global_scoped_fov() -> float:
	var cam := GameSettings.camera
	if cam.scope_magnification <= 0.0:
		return cam.scoped_fov  # absolute mode (legacy); the caller clamps
	# Clamp the REST fov first: a bare/undefined CameraSettings could hold 0, and tan(0) would collapse the
	# scope to a 0-degree pinhole rather than merely being a tuning value the outer clamp can rescue.
	var rest := _clamp_camera_fov(cam.default_fov)
	var scoped_half_tan := tan(deg_to_rad(rest) * 0.5) / cam.scope_magnification
	return rad_to_deg(atan(scoped_half_tan)) * 2.0


func _clamp_camera_fov(value: float) -> float:
	return clampf(value, CAMERA_FOV_MIN, CAMERA_FOV_MAX)
