class_name ScreenShake
extends Node3D

## Trauma-based screen shake (Squirrel Eiserloh model). Callers add "trauma"; this
## node continuously decays it and applies a random rotation each frame. The camera
## is a CHILD of this node, so rotating it shakes the view. Fed by many systems:
## weapon fire (per-weapon screen_shake_amount), landings, the pinball ram bounce,
## interactable destruction, nearby enemy deaths, and every kill the player is
## credited with (Player.on_scored_kill, at any distance).

const MAX_TRAUMA: float = 1.0

## Current shake energy in [0, cap]. Decays every frame; the applied magnitude is
## trauma², not trauma.
var trauma: float = 0.0

## THE ROTATION THIS PIVOT SHOULD REST AT when nothing is shaking (radians, pitch/yaw/roll) — the shake's noise
## is composed ON TOP of it rather than replacing it. Zero for the whole first-person game, which is why this
## node could simply assign `rotation` for years.
##
## ⭐IT EXISTS FOR THE THIRD-PERSON FREE-LOOK ORBIT, and the reason is ownership. Swinging the camera around the
## character takes two writes — move it around the pivot AND turn it by the same angle, or it slides sideways
## while still staring off in the old direction — and the node that carries the camera's rotation is this one.
## Rather than have `ThirdPersonCamera` write `rotation` here and get clobbered by the next shake frame (the
## exact bug `GunMesh._on_aim_changed` documents about GunPose's `visible` write), it writes THIS and the
## composition stays in one place, with one writer of `rotation`.
var base_rotation: Vector3 = Vector3.ZERO

func _process(delta: float) -> void:
	# Linear trauma decay, but shake magnitude = trauma², so it falls off sharply:
	# a hit shakes hard then settles fast, reading as punchy rather than mushy.
	trauma = max(trauma - GameSettings.screen_shake.decay_rate * delta, 0.0)
	var amount := trauma * trauma
	# Random pitch/yaw only; z stays 0 so the horizon never rolls. Added to whatever rest angle the rig asked
	# for (see base_rotation), so a shake during a free-look swing rattles AROUND the swung view.
	rotation = base_rotation + Vector3(
		randf_range(-1, 1) * amount,
		randf_range(-1, 1) * amount,
		0.0
	) * GameSettings.screen_shake.intensity_multiplier

## Additive trauma from an ordinary event, clamped to the standard ceiling.
func shake(amount: float = 1.0) -> void:
	trauma = min(trauma + amount, MAX_TRAUMA)
	_rumble(amount, 0.15)

## Clear all active shake immediately. Used on respawn so a death-adjacent hit,
## explosion, or nearby gore shake cannot ride into the fresh life.
func reset() -> void:
	trauma = 0.0
	rotation = base_rotation  # the rest angle survives a respawn scrub; only the shake is cleared

## Controller haptics mirror screen shake: when the player's last input was a gamepad, rumble it scaled
## by the shake amount (no-op on mouse/keyboard). So a hit/landing/blast you'd SEE as shake you also FEEL.
func _rumble(amount: float, duration: float) -> void:
	if not InputManager.using_controller:
		return
	var a := clampf(amount, 0.0, 1.0)
	Input.start_joy_vibration(0, a * 0.6, a, duration)

## Additive trauma for explosions, allowed a higher ceiling than shake() so blasts
## can shake harder than ordinary events.
func shake_explosion(amount: float) -> void:
	trauma = min(trauma + amount, GameSettings.screen_shake.explosion_max_trauma)
	_rumble(amount, 0.3)  # blasts rumble harder + longer
