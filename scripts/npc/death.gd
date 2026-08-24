extends AudioStreamPlayer3D

const UNIVERSFIELD_HORROR_LIQUID_SPLASH_352472 = preload("uid://cpq0kwlpi35nu")
const CHA_CHING = preload("uid://dpu3xluhnn4u1")

## The dying NPC's VOICE — a last cry, layered over the wet splash above (the splash is the gore, this is the
## person). Authored per-scene rather than preloaded so a non-human body can carry its own (or none: null is
## inert, AudioManager.play_sfx early-outs) without a second script.
@export var death_cry: AudioStream

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
	# The SPLASH is wet meat hitting the floor — a physical world impact, so it varies. (The CRY below is the
	# person's voice and does NOT; see there.)
	AudioManager.play_varied(player)
	# The splash is hand-rolled (it carries this node's authored wide-reaching mix, which play_sfx would flatten),
	# so it also owns its own cleanup. Without this line it is parented to the tree ROOT and never freed — and
	# stop_sfx() cannot reclaim it either, because that queue_free is gated on ONE_SHOT_META, which a hand-rolled
	# spawn never sets. One orphaned player per NPC death, surviving level changes, for the whole session.
	player.finished.connect(player.queue_free)
	# The cry rides AudioManager instead of a hand-rolled spawn so it gets the one-shot hygiene the splash lacks
	# (ONE_SHOT_META, so the death cinematic's stop_sfx() can cut AND free it) and a normal 30 m falloff — the
	# splash's unit_size 100 / unlimited max_distance make it effectively global, and a voice screaming from
	# across the level on every distant kill is not the same sound design as a wet impact carrying. ⭐max_db is
	# the knob that's actually audible here (volume_db 80 pins to the ceiling project-wide), so both are carried.
	# ⭐VARIES, unlike the creature-voice sounds elsewhere (a dog's yap, a purr), and the distinction is
	# EXERTION vs IDENTITY. A death scream is a one-off performance: nobody screams twice at the same pitch, and
	# a whole squad shares this one clip — without variation a firefight kills five men who all die in perfect
	# unison, which is the single most obvious "it's a game" tell in the mix. What must NOT be re-pitched is a
	# voice whose pitch encodes WHO is speaking (Throwable.sound_pitch_mult = the animal's rolled body size).
	AudioManager.play_sfx(death_position, death_cry, volume_db, 1.0, bus, max_db)
	# The kill reward (cha-ching + applause) is 2D PLAYER feedback — skip it for NPC-vs-NPC kills so a
	# distant skirmish doesn't ring a reward in the player's ears. The dying NPC's _last_attacker is its
	# killer; if that's another NPC the player didn't earn this. (A null/unknown killer — e.g. an
	# explosion — counts as the player's, so blast kills still reward.) The cry and splash are DIEGETIC and
	# fire above this gate: an NPC killing an NPC still makes a noise, it just doesn't pay you.
	var enemy := get_parent()
	var killer: Variant = enemy.get(&"_last_attacker")
	if is_instance_valid(killer) and (killer as Node).is_in_group(Groups.NPC):
		return
	# Kill reward: a 2D "cha-ching" so it reads as consistent player feedback
	# regardless of where the enemy died.
	AudioManager.play_2d_sfx(CHA_CHING, 0.0, 1.0, &"sfx", false)  # vary=false: a melodic reward jingle, not a world sound
	# Applause: only when the kill was earned with crits (headshots) exclusively — no body shots.
	if enemy is Character and (enemy as Character).killed_by_only_crits():
		_play_applause()

## Brief crit-kill applause — delegates to the shared AudioManager.play_applause() so the cheer is defined in ONE
## place (the same effect now also fires when the player pets a Pettable). Kept as a named method because the enemy
## wiring + the death.gd surface test reference it.
func _play_applause() -> void:
	AudioManager.play_applause()
