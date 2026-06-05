class_name ScreenShake
extends Node3D

## Trauma-based screen shake (Squirrel Eiserloh model). Callers add "trauma"; this
## node continuously decays it and applies a random rotation each frame. The camera
## is a CHILD of this node, so rotating it shakes the view. Fed by many systems:
## weapon fire (per-weapon screen_shake_amount), landings, the pinball ram bounce,
## interactable destruction, and nearby enemy deaths.

const MAX_TRAUMA: float = 1.0

## Current shake energy in [0, cap]. Decays every frame; the applied magnitude is
## trauma², not trauma.
var trauma: float = 0.0

func _process(delta: float) -> void:
	# Linear trauma decay, but shake magnitude = trauma², so it falls off sharply:
	# a hit shakes hard then settles fast, reading as punchy rather than mushy.
	trauma = max(trauma - GameSettings.screen_shake.decay_rate * delta, 0.0)
	var amount := trauma * trauma
	# Random pitch/yaw only; z stays 0 so the horizon never rolls.
	rotation = Vector3(
		randf_range(-1, 1) * amount,
		randf_range(-1, 1) * amount,
		0.0
	) * GameSettings.screen_shake.intensity_multiplier

## Additive trauma from an ordinary event, clamped to the standard ceiling.
func shake(amount: float = 1.0) -> void:
	trauma = min(trauma + amount, MAX_TRAUMA)
	_rumble(amount, 0.15)

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
