class_name WeaponAudio
extends Node3D

## All of the Weapon's gunfire sound playback — fire, dry-fire click, shell tink, reload, and the two
## impact sounds — pulled out of the Attack coordinator into its own child so Attack stays a thin
## firing hub. The AudioStreamPlayer3D nodes themselves live in the Weapon scene (wired as Attack's
## @exports); Attack hands their references in via setup(), and this captures each node's authored
## stream as the per-weapon fallback. Attack still decides WHEN to play (a shot fired, a clip emptied,
## an enemy hit); this owns the per-weapon stream swap + pitch feel.
##
## ⭐The two sounds a weapon can RETRIGGER faster than they finish — the gunshot and the shell tink — do NOT
## restart their shared node; each play rings on its own throwaway clone of it (see _play_voice), so a burst
## stops chopping its own samples. Everything else (dry-fire click, reload, impacts) plays the node directly.
##
## Built code-side and added in Attack._ready, so off-tree (a unit-test Attack via .new() with no
## add_child) it never exists and Attack's fire path — which already needs a live clip + timers it
## doesn't have off-tree — is never reached; every play call is null-guarded on Attack's side.

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

## The throwaway voices currently ringing for the two sounds a weapon RETRIGGERS faster than they finish —
## the gunshot and the shell tink. See _play_voice: each trigger pull rings on its own clone rather than
## restarting the one shared player, and these lists are what let the OLDEST be cut once the cap is reached.
## Per-WeaponAudio (one per wielder), so a firefight's NPCs each get their own budget instead of a shared one.
var _fire_voices: Array[AudioStreamPlayer3D] = []
var _shell_voices: Array[AudioStreamPlayer3D] = []

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

## Which bus this weapon's trigger sound belongs on. Real GUNFIRE under open sky routes to `gunshots` (the
## distant city-billow chain in default_bus_layout.tres). Everything else is `world`, the diegetic bus every
## footstep/foley sound rides: a melee swing whoosh and the spray can's hiss are world ACTIONS (never the
## billow), and gunfire while `indoors` — the LISTENER's roof state, see listener_indoors() — skips the
## billow too, because `world` itself carries the tight indoor room chain the IndoorAmbienceDucker switches
## on under a roof. The choice must be re-made per play: ONE shared `Attack Audio` node carries every
## weapon's trigger sound (authored on `gunshots`, the outdoor-gun default), and a sticky bus is exactly how
## the fists' punch once shipped echoing across the map. A bus missing from the layout degrades to plain
## `sfx` (clean, still under the Effects slider) rather than falling to Master — the StationSpeaker idiom.
## Static because the spray-burst path in attack.gd plays attack_audio directly and needs the same one rule.
static func fire_bus_for(weapon: WeaponData, indoors: bool = false) -> StringName:
	var is_gun := weapon == null or not (weapon.is_melee or weapon.is_spray_paint)
	if is_gun and not indoors and AudioServer.get_bus_index(&"gunshots") >= 0:
		return &"gunshots"
	return &"world" if AudioServer.get_bus_index(&"world") >= 0 else &"sfx"

## The LISTENER's roof state — the echo chain is a bus-wide treatment of what YOU hear, so the player's
## environment shapes every shot on the bus (an NPC firing at you indoors reads through your room; the same
## NPC outdoors billows). Reads Player.is_indoors, which the IndoorAmbienceDucker drop-in (a Player child in
## game.tscn) writes from its up-ray roof fan each sample. No ducker / no player in the tree leaves it
## false = the outdoor billow, so a bare test level changes nothing. Instance method (needs the tree);
## play_fire only runs in-tree, so off-tree unit tests never reach it.
func listener_indoors() -> bool:
	var p := Groups.human_player(get_tree())
	return p != null and p.get(&"is_indoors") == true

## Play the fire sound for this shot. Cruelty-Squad-style: the fire sound deepens as the magazine
## empties, using `ammo_before` (the count BEFORE this shot) so a full mag fires at full pitch.
## Infinite-ammo weapons (melee, fists) keep normal pitch.
##
## The ammo pitch is the BASE the voice is rolled around, so the global per-play variation multiplies onto it —
## the mag-empties sag still reads exactly as authored, it just stops firing the byte-identical sample on every
## trigger pull (most audible on a full-auto burst).
##
## ⭐Rings on its OWN voice (see _play_voice) instead of restarting the shared `Attack Audio` node, because a
## full-auto weapon pulls the trigger again long before its report has finished: the SMG's 0.125 s cadence used
## to cut a 3.55 s gunshot 125 ms in, at the loudest point of the decay, so held fire read as a stuttering click
## rather than as a burst. That also means the ammo sag + variation rolled here stay THIS shot's — a node-level
## `max_polyphony` would have retuned every still-ringing tail to the newest roll on every pull.
func play_fire(weapon: WeaponData, ammo_before: int) -> void:
	var base_pitch := 1.0
	if not weapon.is_infinite_ammo:
		var ammo_frac := clampf(float(ammo_before) / float(weapon.max_ammo), 0.0, 1.0)
		base_pitch = lerpf(GameSettings.audio.fire_pitch_empty_ammo, GameSettings.audio.fire_pitch_full_ammo, ammo_frac)
	_play_voice(attack_audio, _fire_voices, weapon.audio, fire_bus_for(weapon, listener_indoors()), base_pitch)

## Retrigger `source` WITHOUT cutting the play before it: this trigger pull rings on its own throwaway CLONE
## of the node (added as its sibling, so it carries the authored transform and follows the wielder), while the
## previous one is left alone to finish. `voices` is that sound's live-voice list — the oldest is cut once
## GameSettings.audio.retrigger_voice_limit is reached, so a held trigger costs a bounded number of nodes and
## the cut only ever lands on a tail several shots deep, where it is inaudible.
##
## ⭐⭐WHY A CLONE AND NOT `max_polyphony`. AudioStreamPlayer3D's own polyphony would be the one-liner, but
## `pitch_scale` is a NODE property that the 3D mixer re-applies to every live playback each panning update —
## so the next shot's ammo sag + per-play variation would yank every still-ringing tail with it, ±15% every
## 125 ms. Assigning `stream` is worse still: it calls stop() internally, killing the voices outright. A clone
## per play is the only shape where each shot keeps the pitch it was fired at.
##
## ⭐It is a `duplicate()` rather than a hand-copied field list on purpose. These nodes carry an authored mix
## (volume_db, the ceiling that is actually audible at this project's volumes, attenuation model, unit_size,
## max_distance) and a copy-N-fields helper silently drifts the moment anyone tunes a field it does not know
## about — see _emit_positional_impact, which pays exactly that maintenance cost. `stream` and `bus` are the
## two the CALLER owns (one shared node serves every weapon), so they are passed in and overwritten.
##
## Carries ONE_SHOT_META so AudioManager.stop_sfx() can both cut AND free it; without the meta a menu/death cut
## would stop the voice and strand the node. `base_pitch` is the pitch the site MEANS and takes the global
## per-play variation on top, exactly as AudioManager.play_varied would have.
func _play_voice(source: AudioStreamPlayer3D, voices: Array[AudioStreamPlayer3D], stream: AudioStream, bus: StringName, base_pitch: float = 1.0) -> void:
	if stream == null or not is_instance_valid(source):
		return
	var parent := source.get_parent()
	if parent == null:
		return
	# Forget the voices that already finished and freed themselves, then cut the oldest survivors until this
	# play fits under the cap. Rebuilt rather than erased in place: a freed voice leaves a dangling entry, and
	# `is` on one of those hard-crashes (see the validity-first idiom used across this project).
	var live: Array[AudioStreamPlayer3D] = []
	for v in voices:
		if is_instance_valid(v):
			live.append(v)
	voices.assign(live)
	while voices.size() >= maxi(1, GameSettings.audio.retrigger_voice_limit):
		var oldest: AudioStreamPlayer3D = voices.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var voice := source.duplicate() as AudioStreamPlayer3D
	if voice == null:
		return
	voice.name = "%sVoice" % source.name
	voice.stream = stream
	voice.bus = bus
	voice.autoplay = false
	voice.pitch_scale = AudioManager.vary_pitch(base_pitch)
	voice.set_meta(AudioManager.ONE_SHOT_META, true)
	voices.append(voice)
	# force_readable_name: without it a colliding name becomes the internal `@Attack AudioVoice@7`, and these
	# are exactly the nodes you go looking for in the remote scene tree when a burst sounds wrong.
	parent.add_child(voice, true)
	voice.finished.connect(voice.queue_free)
	voice.play()

## The dry-fire click (empty clip / last round chambered).
func play_empty() -> void:
	AudioManager.play_varied(empty_clip)

## The ejected casing hitting the ground. Its own voice too, and for the same reason as the shot it rides with:
## the tink is a 1.9 s bounce fired once per round, so on the shared node an SMG burst clipped every casing
## after the first 125 ms of it. Keeps the node's authored `world` bus — a shell is foley, never a gunshot.
func play_shell() -> void:
	if not is_instance_valid(shell_impact):
		return
	_play_voice(shell_impact, _shell_voices, shell_impact.stream, shell_impact.bus)

## Play the reload sound — per-weapon if it defines one, else the node's authored default.
func play_reload(weapon: WeaponData) -> void:
	reload_sfx.stream = weapon.reload_sound if weapon.reload_sound else _default_reload_sfx
	AudioManager.play_varied(reload_sfx)

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
## per-weapon stream for the next pellet/shot. An AI wielder's hit drops to GameSettings.audio.npc_impact_volume_db
## so the 3D attenuation applies (the nodes are authored very loud for always-audible PLAYER feedback, which
## from a distant NPC reads as a flat 2D blast); the player's own shots keep the authored volume.
func _emit_positional_impact(source: AudioStreamPlayer3D, hit_pos: Vector3, pitch: float, from_ai: bool) -> void:
	if not is_instance_valid(source):
		return
	if source.stream == null:
		return  # a null-stream AudioStreamPlayer3D never emits `finished`, so the one_shot below would never free — skip
	var one_shot := AudioStreamPlayer3D.new()
	one_shot.stream = source.stream
	one_shot.bus = source.bus
	one_shot.volume_db = GameSettings.audio.npc_impact_volume_db if from_ai else source.volume_db
	one_shot.attenuation_model = source.attenuation_model
	one_shot.unit_size = source.unit_size
	one_shot.max_db = source.max_db
	one_shot.max_distance = source.max_distance
	one_shot.pitch_scale = AudioManager.vary_pitch(pitch)  # the HP/impact pitch above is the BASE; see AudioManager.vary_pitch
	get_tree().root.add_child(one_shot)
	one_shot.global_position = hit_pos
	one_shot.play()
	one_shot.finished.connect(one_shot.queue_free)
