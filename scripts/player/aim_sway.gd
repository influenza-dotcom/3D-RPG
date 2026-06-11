class_name AimSway
extends Node

## Deus Ex-style AIM WANDER: the player's true shot direction drifts smoothly around the camera centre
## instead of landing exactly on the camera ray. Player.get_aim_direction applies the current drift — so
## hitscan shots, projectiles, and tracers all follow it — and the crosshair is pinned to the same value
## (Player._update_crosshair), so the reticle always tells the truth about where a shot will go.
##
## STANCE drives the amplitude (GameSettings.player_aim): full ground speed is loosest, standing still
## tighter, crouching tighter again — accuracy is a stance choice, like the original Deus Ex. The drift
## itself is two incommensurate sines per axis, so it never visibly loops and needs no per-frame random.
##
## `host` is the Player — typed Node to avoid a Player <-> AimSway class cycle, so host.* is dynamic.

var host: Node = null

var _t: float = 0.0
var _offset := Vector2.ZERO  ## current wander in RADIANS: x = yaw (around the aim basis up), y = pitch

func _physics_process(delta: float) -> void:
	var s: PlayerAimSettings = GameSettings.player_aim
	_t += delta * s.sway_speed
	# Amplitude from stance: ground speed eases between the standing and moving amplitudes, then a crouch
	# multiplies it down (full crouch = sway_crouch_mult of the stance value).
	var speed: float = Vector2(host.velocity.x, host.velocity.z).length()
	var move_t: float = clampf(speed / maxf(GameSettings.player_movement.max_speed, 0.01), 0.0, 1.0)
	var amp_deg: float = lerpf(s.sway_standing_deg, s.sway_moving_deg, move_t)
	if host.crouch != null:
		amp_deg *= lerpf(1.0, s.sway_crouch_mult, host.crouch.crouch_t)
	# GUNPLAY stat: a practiced shooter holds steadier (the multiplier is 1.0 on a baseline sheet).
	if host.has_method(&"stats_or_default"):
		amp_deg *= host.stats_or_default().sway_mult()
	var amp := deg_to_rad(amp_deg)
	# Two incommensurate sines per axis (normalised by the 1.35 peak of sin + 0.35*sin): a smooth, figure-
	# eight-ish drift that never visibly repeats. Pitch runs slightly slower + smaller than yaw, which
	# reads as a natural hand-held waver rather than a mechanical circle.
	_offset = Vector2(
		(sin(_t * 1.1) + 0.35 * sin(_t * 2.7 + 1.3)) / 1.35 * amp,
		(sin(_t * 0.9 + 0.7) + 0.35 * sin(_t * 2.3 + 2.1)) / 1.35 * amp * 0.8)

## The camera-forward `dir` rotated by the current wander, using the aim basis axes (yaw around the
## camera's up, pitch around its right). Called by Player.get_aim_direction every time something asks
## where a shot would go — same answer for the whole frame (the offset only advances in _physics_process).
func apply(dir: Vector3, aim_basis: Basis) -> Vector3:
	if _offset == Vector2.ZERO:
		return dir
	return dir.rotated(aim_basis.y.normalized(), _offset.x).rotated(aim_basis.x.normalized(), _offset.y).normalized()
