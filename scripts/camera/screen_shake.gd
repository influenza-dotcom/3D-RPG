class_name ScreenShake
extends Node3D

const MAX_TRAUMA: float = 1.0

var trauma: float = 0.0

func _process(delta: float) -> void:
	trauma = max(trauma - GameSettings.screen_shake.decay_rate * delta, 0.0)
	var amount := trauma * trauma
	rotation = Vector3(
		randf_range(-1, 1) * amount,
		randf_range(-1, 1) * amount,
		0.0
	) * GameSettings.screen_shake.intensity_multiplier

func shake(amount: float = 1.0) -> void:
	trauma = min(trauma + amount, MAX_TRAUMA)

func shake_explosion(amount: float) -> void:
	trauma = min(trauma + amount, GameSettings.screen_shake.explosion_max_trauma)
