extends AudioStreamPlayer3D

const UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472 = preload("uid://cpq0kwlpi35nu")
const CHA_CHING = preload("res://assets/audio/freesound_community-cash-register-purchase-87313.mp3")

func _on_enemy_died() -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472
	var death_position := global_position
	get_tree().root.add_child(player)
	player.global_position = death_position
	player.play()
	player.finished.connect(player.queue_free)
	# Kill reward: a 2D "cha-ching" so it reads as consistent player feedback
	# regardless of where the enemy died.
	AudioManager.play_2d_sfx(CHA_CHING)
