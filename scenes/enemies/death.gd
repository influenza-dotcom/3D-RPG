extends AudioStreamPlayer3D

const UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472 = preload("uid://cpq0kwlpi35nu")

func _on_enemy_died() -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472
	var death_position := global_position
	get_tree().root.add_child(player)
	player.global_position = death_position
	player.play()
	player.finished.connect(player.queue_free)
