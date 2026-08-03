class_name ScopeCoordinator
extends Node

## Reacts to the player entering / leaving ADS (scope): toggles the rifle-only crosshair dot + scope
## optics, declutters the "being aimed at" radials, hands the scope state to the camera DoF, and ducks
## the music bus a touch while scoped (mirrors the dialogue duck). Built in code under the Player and
## given a host ref right after .new(); the canonical _is_scoped flag stays on the Player (its
## _physics_process reads it for the scoped speed multiplier).
##
## Wired in Player._ready: weapon_system.scope_in.scoped_in.connect(_scope.on_scoped_in).

## The audio bus ducked while scoped (slightly quieter, focused feel). The duck amount + fade time are
## designer-tuned in GameSettings.camera (scope_music_duck_db / scope_music_duck_time).
const SCOPE_MUSIC_BUS := &"music"

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
	# Stand down while the death cinematic owns the music bus. It re-asserts that bus EVERY FRAME, and the
	# revive hands the player back input BEFORE the world finishes swelling (spawn_fade_in_time) — so ADSing
	# across a respawn is entirely reachable. Two owners writing absolute dB to one bus fight per-frame: the
	# music would slam up toward the duck target and snap back down as the cinematic reclaimed it. Returning
	# BEFORE the latch is what makes this safe — the duck is never armed, so the matching unscope is a clean
	# no-op instead of a stale restore. (Player.die() already reset() us, so no latch is held at that point.)
	if DeathMix.owns_bus(SCOPE_MUSIC_BUS):
		return
	if duck:
		# Derived from Settings (authored base + slider), NEVER sampled from the live bus — see MusicDucker's
		# matching comment. Scoping in while the death cinematic's world duck is still cross-fading back up
		# (the player is alive for all of spawn_fade_in_time) would otherwise bake that transient level in as
		# "normal" and leave the music permanently quieter on every unscope. Same accepted trade-off: nested
		# ducks no longer stack.
		if not _scope_music_ducked:
			_scope_music_prior_db = Settings.current_bus_db(SCOPE_MUSIC_BUS)
			_scope_music_ducked = true
	else:
		if not _scope_music_ducked:
			return
		_scope_music_ducked = false
	var target := (_scope_music_prior_db + GameSettings.camera.scope_music_duck_db) if duck else _scope_music_prior_db
	if _scope_music_tween and _scope_music_tween.is_valid():
		_scope_music_tween.kill()
	_scope_music_tween = create_tween()
	_scope_music_tween.tween_method(_set_music_bus_db.bind(bus), AudioServer.get_bus_volume_db(bus), target, GameSettings.camera.scope_music_duck_time)

func _set_music_bus_db(db: float, bus: int) -> void:
	AudioServer.set_bus_volume_db(bus, db)

## Hard-restore the music bus to its pre-duck level and drop the duck latch. Called from the player's
## death / teardown path (Player.die) so a death-while-scoped doesn't leave the bus ducked into the next
## life — the bus is global and a scene reload won't reset it. No-op if we never ducked (nothing to undo).
func reset() -> void:
	if _scope_music_tween and _scope_music_tween.is_valid():
		_scope_music_tween.kill()
	if _scope_music_ducked:
		var bus := AudioServer.get_bus_index(SCOPE_MUSIC_BUS)
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, _scope_music_prior_db)
	_scope_music_ducked = false
