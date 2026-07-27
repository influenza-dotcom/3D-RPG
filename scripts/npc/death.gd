extends AudioStreamPlayer3D

const UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472 = preload("uid://cpq0kwlpi35nu")
const CHA_CHING = preload("uid://dpu3xluhnn4u1")

func _on_enemy_died() -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472
	# Carry our authored splash mix onto the one-shot: a bare new() would play at engine defaults and
	# discard the loud, wide-reaching values tuned on this Death node (volume_db / unit_size / max_db / bus).
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.max_db = max_db
	player.bus = bus
	var death_position := global_position
	get_tree().root.add_child(player)
	player.global_position = death_position
	player.play()
	player.finished.connect(player.queue_free)
	# The kill reward (cha-ching + applause) is 2D PLAYER feedback — skip it for NPC-vs-NPC kills so a
	# distant skirmish doesn't ring a reward in the player's ears. The dying NPC's _last_attacker is its
	# killer; if that's another NPC the player didn't earn this. (A null/unknown killer — e.g. an
	# explosion — counts as the player's, so blast kills still reward.)
	var enemy := get_parent()
	var killer: Variant = enemy.get(&"_last_attacker")
	if is_instance_valid(killer) and (killer as Node).is_in_group(Groups.NPC):
		return
	# Kill reward: a 2D "cha-ching" so it reads as consistent player feedback
	# regardless of where the enemy died.
	AudioManager.play_2d_sfx(CHA_CHING)
	# Applause: only when the kill was earned with crits (headshots) exclusively — no body shots.
	if enemy is Character and (enemy as Character).killed_by_only_crits():
		_play_applause()

## Brief crit-kill applause — delegates to the shared AudioManager.play_applause() so the cheer is defined in ONE
## place (the same effect now also fires when the player pets a Pettable). Kept as a named method because the enemy
## wiring + the death.gd surface test reference it.
func _play_applause() -> void:
	AudioManager.play_applause()
