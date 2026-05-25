extends AudioStreamPlayer3D

const UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472 = preload("uid://cpq0kwlpi35nu")

func _on_enemy_died() -> void:
	var player = AudioStreamPlayer3D.new()
	player.stream = UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472
	get_parent().get_parent().add_child(player)
	player.global_position = position
	player.play()
	player.finished.connect(player.queue_free)
