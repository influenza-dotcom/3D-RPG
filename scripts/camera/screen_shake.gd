class_name ScreenShake
extends Node3D

const MAX_TRAUMA: float = 1.0

var trauma: float = 0.0

func _process(delta: float) -> void:
	trauma = max(trauma - GameTuning.SCREEN_SHAKE_DECAY * delta, 0.0)
	var amount := trauma * trauma
	rotation = Vector3(
		randf_range(-1, 1) * amount,
		randf_range(-1, 1) * amount,
		0.0
	) * GameTuning.SCREEN_SHAKE_AMOUNT_MULT

func shake(amount: float = 1.0) -> void:
	trauma = min(trauma + amount, MAX_TRAUMA)

func shake_explosion(amount: float) -> void:
	trauma = min(trauma + amount, GameTuning.EXPLOSION_MAX_TRAUMA)
