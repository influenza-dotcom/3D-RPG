extends AudioStreamPlayer3D


func _on_enemy_damaged(_current_hp: float, _max_hp: float) -> void:
	play()
