class_name ScopeCoordinator
extends Node

## Reacts to the player entering / leaving ADS (scope): toggles the rifle-only crosshair dot + scope
## optics, declutters the "being aimed at" radials, hands the scope state to the camera DoF, and ducks
## the music bus a touch while scoped (mirrors the dialogue duck). Built in code under the Player and
## given a host ref right after .new(); the canonical _is_scoped flag stays on the Player (its
## _physics_process reads it for the scoped speed multiplier).
##
## Wired in Player._ready: weapon_system.scope_in.scoped_in.connect(_scope.on_scoped_in).

## How far the music bus drops while scoped (slightly quieter, focused feel) + the fade time.
const SCOPE_MUSIC_BUS := &"music"
const SCOPE_MUSIC_DUCK_DB: float = -6.0
const SCOPE_MUSIC_DUCK_TIME: float = 0.25

var host: Player

var _scope_music_prior_db: float = 0.0
var _scope_music_ducked: bool = false
var _scope_music_tween: Tween

func on_scoped_in(_tf: bool) -> void:
	host._is_scoped = _tf
	# Is this the dedicated rifle scope (crisp scope = disables DoF)? Only the rifle gets the full scope
	# OPTICS (vignette + lens flare); the inverting crosshair dot now shows for ANY weapon's ADS.
	var is_rifle := _tf and host.weapon_system != null and host.weapon_system.equipped_weapon != null \
			and host.weapon_system.equipped_weapon.disable_dof_while_scoped
	if host.ui:
		host.ui.set_scoped(_tf)  # crosshair dot for ANY ADS (the back-buffer copy + inversion ride this too)
	if host._hud:
		host._hud.set_aim_declutter(_tf)  # declutter the scope: hide the "being aimed at" radials while scoped
	if host.camera_effects and host.weapon_system and host.weapon_system.equipped_weapon:
		host.camera_effects.set_scope_dof(_tf, host.weapon_system.equipped_weapon.disable_dof_while_scoped)
	elif host.camera_effects:
		host.camera_effects.set_scope_dof(_tf, false)
	# Rifle scope optics (edge vignette + anamorphic lens flare) ride the same rifle-only gate.
	if host.ui:
		host.ui.set_scope_optics(is_rifle)
	# Music ducks a touch while scoped through ANY sight, restored on unscope.
	_duck_music_for_scope(_tf)

## Fade the music bus down slightly while scoped, back up on unscope (mirrors the dialogue duck). Safe
## to call repeatedly; captures the pre-duck level once so it always restores to the right baseline.
func _duck_music_for_scope(duck: bool) -> void:
	var bus := AudioServer.get_bus_index(SCOPE_MUSIC_BUS)
	if bus < 0:
		return
	if duck:
		if not _scope_music_ducked:
			_scope_music_prior_db = AudioServer.get_bus_volume_db(bus)
			_scope_music_ducked = true
	else:
		if not _scope_music_ducked:
			return
		_scope_music_ducked = false
	var target := (_scope_music_prior_db + SCOPE_MUSIC_DUCK_DB) if duck else _scope_music_prior_db
	if _scope_music_tween and _scope_music_tween.is_valid():
		_scope_music_tween.kill()
	_scope_music_tween = create_tween()
	_scope_music_tween.tween_method(_set_music_bus_db.bind(bus), AudioServer.get_bus_volume_db(bus), target, SCOPE_MUSIC_DUCK_TIME)

func _set_music_bus_db(db: float, bus: int) -> void:
	AudioServer.set_bus_volume_db(bus, db)
