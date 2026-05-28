extends AudioStreamPlayer3D

## Enemy hurt SFX. Connected to the enemy's `damaged` signal (in the enemy scene);
## plays a positional pain/impact sound on every damage tick.

func _on_enemy_damaged(_current_hp: float, _max_hp: float) -> void:
	play()
