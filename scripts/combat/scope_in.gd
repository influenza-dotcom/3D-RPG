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

## Wheel-dialed zoom per variable-zoom weapon (WeaponData -> FOV degrees). Holds ONLY values the wheel
## actually dialed (step_wheel_zoom is the sole writer — until then current_wheel_zoom_fov computes the
## resting zoom LIVE, which is what keeps an override-less scope FOV-slider-invariant). Never saved, and it
## dies with this rig (a level reload / quickload resets every dial). Keyed by the WeaponData RESOURCE —
## the same .tres every copy of that weapon kind shares — so re-equipping or picking up a second sniper
## keeps your dial.
var _wheel_zoom_fov: Dictionary = {}

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
		target_fov = scoped_target_fov(attack.current_weapon if attack else null)
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


## Mouse-wheel zoom for a VARIABLE-zoom scope (a weapon authoring scoped_zoom_fov_min/max — the sniper).
## Raw wheel events on purpose, mirroring SprayPainter's palette cycling: the wheel's ACTIONS (Hotbar
## Next/Prev) belong to weapon switching, and the Hotbar yields to us through the same
## wheel_owns_scope_zoom() predicate this gates on, so the two sides can never disagree about who owns a
## notch. Gated on AIMING (Zoom held), not on is_scoped — see the predicate for why.
func _unhandled_input(event: InputEvent) -> void:
	if not camera:
		return  # AI wielder — the same skip as _process; an NPC's scope has no wheel
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var zoom_dir := 0
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_dir = 1   # wheel up = zoom IN (deeper)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_dir = -1  # wheel down = zoom OUT (wider)
	else:
		return
	if not ScopeIn.wheel_owns_scope_zoom(attack):
		return
	step_wheel_zoom(attack.current_weapon, zoom_dir)
	get_viewport().set_input_as_handled()


## True while the mouse wheel belongs to the SCOPE rather than to weapon switching: aiming (Zoom held,
## un-holstered) a weapon that authors a variable-zoom range, with the global wheel-step knob on. Static so
## the Hotbar can ask without a ScopeIn reference (its _scope_owns_wheel, the _spray_owns_wheel idiom).
## Deliberately the same Zoom-HELD gate as the spray palette — NOT is_scoped — so a notch during a reload's
## forced scope break still dials the (stored) zoom you'll re-enter at, instead of surprise-switching your
## weapon mid-aim; and so the Hotbar's poll and our event handler read one truth that needs no node state.
static func wheel_owns_scope_zoom(attack_node: Attack) -> bool:
	if attack_node == null or attack_node.holstered:
		return false
	var weapon: WeaponData = attack_node.current_weapon
	if weapon == null or not weapon.has_variable_scope_zoom() or weapon.is_spray_paint or weapon.no_ads:
		return false
	if GameSettings.camera.scope_zoom_wheel_step <= 1.0:
		return false  # knob authored off — hand the wheel back to weapon switching everywhere
	return Input.is_action_pressed(&"Zoom") and not InputManager.gameplay_suppressed()


## The FOV the scope is worth for this weapon right now — what the scoped branch of _process eases toward:
## the wheel-dialed zoom for a variable scope, else the weapon's fixed ABSOLUTE override (a scope is a fixed
## optic — see the field doc), else the global magnification solve. Public for the contract tests.
func scoped_target_fov(weapon: WeaponData) -> float:
	if weapon:
		if weapon.has_variable_scope_zoom():
			return current_wheel_zoom_fov(weapon)
		if weapon.scoped_fov_override > 0.0:
			return weapon.scoped_fov_override
	return global_scoped_fov()


## The wheel-dialed FOV for a variable-zoom weapon. Until the wheel's FIRST notch on a weapon this is
## computed LIVE — the weapon's authored resting zoom (scoped_fov_override; the global magnification solve
## when it has none) clamped into the authored range — so scope-in always lands on the authored look, and
## an override-LESS variable scope keeps the global solve's Field-of-View-slider invariance (the whole
## point of scope_magnification) instead of freezing whatever the slider read on first aim. Only
## step_wheel_zoom writes the remembered dial; from that moment the dialed angle is deliberately ABSOLUTE
## for the rig's life — the player chose a real optic setting, so it must not drift under the slider.
func current_wheel_zoom_fov(weapon: WeaponData) -> float:
	if _wheel_zoom_fov.has(weapon):
		return float(_wheel_zoom_fov[weapon])
	var start_fov := weapon.scoped_fov_override
	if start_fov <= 0.0:
		start_fov = global_scoped_fov()
	return _clamp_wheel_zoom(weapon, start_fov)


## One wheel notch: dir 1 = zoom in (deeper), -1 = out (wider). The step is a TANGENT ratio — it multiplies
## the magnification, not the degrees (halving an angle does not double apparent size; see
## global_scoped_fov) — so every notch FEELS like the same step across the whole travel, then clamps to the
## weapon's authored range. The FOV lerp in _process eases onto the new target at scope_zoom_speed.
func step_wheel_zoom(weapon: WeaponData, dir: int) -> void:
	var step: float = GameSettings.camera.scope_zoom_wheel_step
	if step <= 1.0 or not weapon.has_variable_scope_zoom():
		return
	var half_tan := tan(deg_to_rad(current_wheel_zoom_fov(weapon)) * 0.5)
	half_tan = half_tan / step if dir > 0 else half_tan * step
	_wheel_zoom_fov[weapon] = _clamp_wheel_zoom(weapon, rad_to_deg(atan(half_tan)) * 2.0)


## The weapon's zoom range intersected with Camera3D's legal FOV, so bad authoring degrades exactly like
## scoped_fov_override does (an end under 1 degree pins at the 1-degree floor instead of tripping set_fov).
func _clamp_wheel_zoom(weapon: WeaponData, fov: float) -> float:
	return clampf(_clamp_camera_fov(fov),
		_clamp_camera_fov(weapon.scoped_zoom_fov_min), _clamp_camera_fov(weapon.scoped_zoom_fov_max))


## Carry a dialed wheel-zoom across a weapon-bench refit, RE-CLAMPED into the new block's range: a sight
## part that narrows scoped_zoom_fov_min/max must pull an out-of-range dial in, because
## current_wheel_zoom_fov returns a STORED value verbatim (only step_wheel_zoom re-clamps) — so a refit
## would otherwise strand an illegal absolute FOV that the player can only escape by dialing.
## A new block with no variable zoom simply DROPS the dial: current_wheel_zoom_fov is never consulted for
## it (scoped_target_fov falls through to the override / the global solve), so a stored key would be dead
## weight keyed on a resource nothing else references.
## Reached only through Weapon.migrate_weapon_state — see there for why the fan-out is a single entry.
func rekey_weapon(old: WeaponData, new: WeaponData) -> void:
	if old == null or new == null or old == new or not _wheel_zoom_fov.has(old):
		return
	var dialed := float(_wheel_zoom_fov[old])
	_wheel_zoom_fov.erase(old)
	if new.has_variable_scope_zoom():
		_wheel_zoom_fov[new] = _clamp_wheel_zoom(new, dialed)


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
