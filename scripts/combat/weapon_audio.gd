class_name WeaponAudio
extends Node3D

## All of the Weapon's gunfire sound playback — fire, dry-fire click, shell tink, reload, and the two
## impact sounds — pulled out of the Attack coordinator into its own child so Attack stays a thin
## firing hub. The AudioStreamPlayer3D nodes themselves live in the Weapon scene (wired as Attack's
## @exports); Attack hands their references in via setup(), and this captures each node's authored
## stream as the per-weapon fallback. Attack still decides WHEN to play (a shot fired, a clip emptied,
## an enemy hit); this owns the per-weapon stream swap + pitch feel.
##
## Built code-side and added in Attack._ready, so off-tree (a unit-test Attack via .new() with no
## add_child) it never exists and Attack's fire path — which already needs a live clip + timers it
## doesn't have off-tree — is never reached; every play call is null-guarded on Attack's side.

## Volume (dB) the per-hit impact one-shots play at when an AI wielder fired the shot. The .tscn authors
## the impact nodes very loud (volume_db 80) so a PLAYER hit reads as always-audible feedback at any
## range; at that level the AudioStreamPlayer3D distance falloff is saturated, so a distant NPC-vs-NPC
## trade blasts the player like a flat 2D sound. AI-fired impacts drop to this so the 3D attenuation
## actually applies. Mirrors projectile.gd's NPC_IMPACT_VOLUME_DB (the projectile path solves the same
## problem the same way).
const NPC_IMPACT_VOLUME_DB: float = 0.0

var attack_audio: AudioStreamPlayer3D
var reload_sfx: AudioStreamPlayer3D
var impact: AudioStreamPlayer3D
var impact_enemy_hit: AudioStreamPlayer3D
var empty_clip: AudioStreamPlayer3D
var shell_impact: AudioStreamPlayer3D

## Each player's authored stream, captured in setup() so a weapon with no per-weapon sound falls back to
## it (and a weapon WITH one doesn't leave its sound stuck on the next weapon you fire / reload).
var _default_reload_sfx: AudioStream
var _default_impact: AudioStream
var _default_impact_enemy: AudioStream

## Wire the scene's audio players in (Attack's @export node slots) and snapshot their authored streams
## as the per-weapon fallbacks. Called once from Attack._ready, right after this is added.
func setup(p_attack_audio: AudioStreamPlayer3D, p_reload_sfx: AudioStreamPlayer3D, p_impact: AudioStreamPlayer3D, p_impact_enemy_hit: AudioStreamPlayer3D, p_empty_clip: AudioStreamPlayer3D, p_shell_impact: AudioStreamPlayer3D) -> void:
	attack_audio = p_attack_audio
	reload_sfx = p_reload_sfx
	impact = p_impact
	impact_enemy_hit = p_impact_enemy_hit
	empty_clip = p_empty_clip
	shell_impact = p_shell_impact
	if reload_sfx:
		_default_reload_sfx = reload_sfx.stream
	if impact:
		_default_impact = impact.stream
	if impact_enemy_hit:
		_default_impact_enemy = impact_enemy_hit.stream

## Play the fire sound for this shot. Cruelty-Squad-style: the fire sound deepens as the magazine
## empties, using `ammo_before` (the count BEFORE this shot) so a full mag fires at full pitch.
## Infinite-ammo weapons (melee, fists) keep normal pitch.
func play_fire(weapon: WeaponData, ammo_before: int) -> void:
	attack_audio.stream = weapon.audio
	if not weapon.is_infinite_ammo:
		var ammo_frac := clampf(float(ammo_before) / float(weapon.max_ammo), 0.0, 1.0)
		attack_audio.pitch_scale = lerpf(GameSettings.audio.fire_pitch_empty_ammo, GameSettings.audio.fire_pitch_full_ammo, ammo_frac)
	else:
		attack_audio.pitch_scale = 1.0
	attack_audio.play()

## The dry-fire click (empty clip / last round chambered).
func play_empty() -> void:
	empty_clip.play()

## The ejected casing hitting the ground.
func play_shell() -> void:
	shell_impact.play()

## Play the reload sound — per-weapon if it defines one, else the node's authored default.
func play_reload(weapon: WeaponData) -> void:
	reload_sfx.stream = weapon.reload_sound if weapon.reload_sound else _default_reload_sfx
	reload_sfx.play()

## Point the two impact players at this weapon's per-weapon impact sounds, falling back to the nodes'
## authored defaults when it has none. Done once per shot, before the raycast loop.
func apply_impact_defaults(weapon: WeaponData) -> void:
	impact.stream = weapon.impact_sound if weapon.impact_sound else _default_impact
	impact_enemy_hit.stream = weapon.impact_enemy_sound if weapon.impact_enemy_sound else _default_impact_enemy

## A bullet/melee swing hitting a non-character (a wall / prop): the generic impact at a randomised
## pitch, played POSITIONALLY at the world hit point so it reads as coming from the surface struck
## rather than flat from the player's hands (the weapon-mounted node sits on the view-model).
func play_generic_impact(hit_pos: Vector3, from_ai: bool) -> void:
	_emit_positional_impact(impact, hit_pos, randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max), from_ai)

## A bullet/melee swing hitting a character. The player's own shots use the per-weapon enemy-impact; an
## AI wielder uses the generic impact, so a distant NPC-vs-NPC trade just sounds where it happens. Either
## way it plays POSITIONALLY at the world hit point instead of from the weapon-mounted node at the hands.
func play_enemy_impact(enemy: Character, headshot: bool, from_ai: bool, hit_pos: Vector3) -> void:
	_play_enemy_impact(impact if from_ai else impact_enemy_hit, enemy, hit_pos, from_ai, headshot)

func _play_enemy_impact(player: AudioStreamPlayer3D, enemy: Character, hit_pos: Vector3, from_ai: bool, headshot: bool = false) -> void:
	# Pitch tracks the enemy's remaining HP — the closer to death, the deeper the
	# hit sounds. HP is already post-damage here (take_damage ran first).
	if not enemy:
		_emit_positional_impact(player, hit_pos, randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max), from_ai)
		return
	var frac := clampf(enemy.hp / maxf(enemy.max_hp, 1.0), 0.0, 1.0)
	var pitch := lerpf(GameSettings.audio.enemy_hit_pitch_low_hp, GameSettings.audio.enemy_hit_pitch_full_hp, frac) * (1.5 if headshot else 1.0)
	_emit_positional_impact(player, hit_pos, pitch, from_ai)

## Spawn a throwaway AudioStreamPlayer3D at the world hit point carrying the source node's stream / bus /
## 3D falloff, so the impact sounds AT the surface struck instead of flat from the weapon-mounted node at
## the player's hands. Mirrors projectile.gd's _emit_impact: copy the falloff fields, play, free on
## finished. The source node (Attack's @export) is left untouched — it's still pointed at this weapon's
## per-weapon stream for the next pellet/shot. An AI wielder's hit drops to NPC_IMPACT_VOLUME_DB so the
## 3D attenuation applies (the nodes are authored very loud for always-audible PLAYER feedback, which
## from a distant NPC reads as a flat 2D blast); the player's own shots keep the authored volume.
func _emit_positional_impact(source: AudioStreamPlayer3D, hit_pos: Vector3, pitch: float, from_ai: bool) -> void:
	if not is_instance_valid(source):
		return
	var one_shot := AudioStreamPlayer3D.new()
	one_shot.stream = source.stream
	one_shot.bus = source.bus
	one_shot.volume_db = NPC_IMPACT_VOLUME_DB if from_ai else source.volume_db
	one_shot.attenuation_model = source.attenuation_model
	one_shot.unit_size = source.unit_size
	one_shot.max_db = source.max_db
	one_shot.max_distance = source.max_distance
	one_shot.pitch_scale = pitch
	get_tree().root.add_child(one_shot)
	one_shot.global_position = hit_pos
	one_shot.play()
	one_shot.finished.connect(one_shot.queue_free)
