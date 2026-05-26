extends AudioStreamPlayer3D

func _on_flash_muzzle() -> void:
	pitch_scale = randf_range(GameTuning.MUZZLE_WHIZ_PITCH_MIN, GameTuning.MUZZLE_WHIZ_PITCH_MAX)
	play()
