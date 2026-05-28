extends AudioStreamPlayer3D

func _on_flash_muzzle() -> void:
	pitch_scale = randf_range(GameSettings.audio.muzzle_whiz_pitch_min, GameSettings.audio.muzzle_whiz_pitch_max)
	play()
