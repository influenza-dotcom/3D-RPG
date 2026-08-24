extends Node

## @system Effect And Audio Seams
## @seam One-shot SFX seam: play_sfx/play_2d_sfx spawn self-freeing players on the sfx bus (default) so volume sliders apply; play_applause is the shared kill+pet cheer; stop_sfx cuts all sfx-bus players, freeing only ONE_SHOT_META ones.
## @seam Pitch-variation seam: vary_pitch() is THE global per-play detune for DIEGETIC world SFX; play_sfx/play_2d_sfx apply it unless the caller passes vary=false, and play_varied() is the node-driven equivalent for an authored AudioStreamPlayer a world site retriggers.
## @risk A sound spawned bare (not via play_sfx) lands on Master and silently ignores the SFX volume slider AND the death cinematic's world duck (so it blares under the death card) — no error; the bus=&"sfx" default guards the code side, tests/test_audio_bus_hygiene.gd guards the authored-scene side.
## @risk Pitch variation is for DIEGETIC WORLD sound only (footsteps, gunfire, impacts, voices, doors). Menu chrome, HUD/alert stings, reward jingles and music must stay EXACT — a randomised UI blip or a detuned jingle reads as a defect, not as life; the vary=false opt-out on play_sfx/play_2d_sfx is how such a caller says so.
## @risk A new WORLD SFX site that calls player.play() directly instead of AudioManager.play_varied(player) is the ONE way to reintroduce a machine-exact retrigger — it sounds fine in isolation and only reads as fatiguing once it fires three times a second.
## @risk Re-adding a local applause copy in death.gd/pettable.gd instead of calling play_applause drifts the kill vs pet cheer apart, and no test asserts they delegate.
## @test res://tests/test_audio_manager_spawn.gd
## @test res://tests/test_audio_pitch_variation.gd
## @test res://tests/test_autoload_order.gd

# AudioManager — central helper for one-shot sound effects.
#
# Use this for free-standing one-shot sounds that do not need a persistent scene
# node. Keep authored/looping/animation-owned AudioStreamPlayer nodes when their
# position, lifetime, fade, or editor wiring is part of the feature.

const DEFAULT_3D_MAX_DISTANCE: float = 30.0
## AudioStreamPlayer3D's OWN default ceiling, mirrored here so the spawned one-shot keeps behaving exactly as it
## did before `max_db` became a parameter. NOT a tuning knob — a caller that wants a different ceiling passes one.
const DEFAULT_MAX_DB: float = 3.0
const SFX_BUS: StringName = &"sfx"
const ONE_SHOT_META: StringName = &"_audio_manager_one_shot"
## Floor the varied pitch can never fall below. pitch_scale 0 hangs a voice forever — it never advances, so
## `finished` never fires and a play_sfx one-shot (which frees itself on that signal) would LEAK. Guards both a
## pathological spread and a caller that hands in 0.
const MIN_PITCH: float = 0.01

## The crowd-applause cheer clip + its brief-beat/fade timing. THE single source for "the applause" reward, shared
## by the all-headshots kill (scenes/enemies/death.gd) AND petting a Pettable (scripts/components/pettable.gd) so the
## cheer never drifts between the two. See play_applause.
const APPLAUSE := preload("uid://ccuwf868b4w2j")
const APPLAUSE_HOLD: float = 0.88     ## seconds at full volume before the fade starts
const APPLAUSE_FADE: float = 0.8      ## seconds the fade-out runs
const APPLAUSE_FADE_TO_DB: float = -40.0  ## near-silence target the fade eases to
## Level the cheer plays at. It is NOT free-standing: the kill that earns it fires the gore splash from the SAME
## frame at the +6 dB ceiling (enemy.tscn's Death node authors volume_db 80, pinned by max_db 6), and that splash
## runs ~1.68 s — which is exactly APPLAUSE_HOLD + APPLAUSE_FADE, i.e. the whole of this cheer. At 0 dB the reward
## sat underneath its own kill for its entire length. This brings it to parity; being 2D (no distance attenuation,
## unlike the 3D splash) then puts it just on top. The fade below starts from HERE, so this lengthens nothing.
const APPLAUSE_VOLUME_DB: float = 6.0


## ⭐THE global per-play pitch variation for DIEGETIC WORLD sound — the one place "a world sound never plays
## at the exact same pitch twice" is implemented. Returns `base_pitch` MULTIPLIED by a fresh random factor in
## [1 - spread, 1 + spread], where spread is `GameSettings.audio.global_pitch_spread` (default 0.15, matching
## this project's own `interactable_impact_pitch_spread`; 0.0 = off). See that export for how to SIZE it — the
## first cut shipped at 0.04 and was inaudible, which is the failure mode to watch for.
##
## ⭐⭐WHAT IT IS FOR, AND WHAT IT MUST NEVER TOUCH. Variation is how a sound that EXISTS IN THE WORLD stops
## sounding like one sample machine-gunned at you: footsteps, gunfire, reloads, bullet and melee impacts,
## explosions, gore splashes, screams, hurt cries and animal yaps, doors, switches, a flashlight click, a
## radio's on/off switch. It is emphatically NOT for anything the world isn't making:
##   * MENU / UI chrome — hover, click, open, back, tab, commit, the refusal buzz. A button must sound like the
##     same button every press; a randomised blip reads as a BUG, not as life. MenuStyle owns those and stays exact.
##   * NON-DIEGETIC STINGS AND HUD CUES — the MGS "!" alert, the aim/charge sting, the incoming-shot beep, the
##     hitmarker ding. These are the game TELLING you something; a wobbling siren undermines the signal, and where
##     one carries data in its pitch (the hitmarker deepens with the target's HP) a jitter actively muddies it.
##   * REWARD JINGLES — the cha-ching bounty, the pickup chime, the applause cheer. They are melodic; varied,
##     they just sound out of tune.
##
## ⭐⭐VOICES DO VARY, AND THE MULTIPLY IS WHY THAT IS SAFE. Every vocalisation the world makes — a hurt cry, a
## death scream, a falling yell, a dog's yap or purr — takes the variation, because it is applied AROUND the
## site's own base pitch rather than instead of it. Where a creature has an authored voice
## (`Throwable.sound_pitch_mult` is the animal's rolled BODY SIZE, via RandomSize.pitch_mult_for_size), that
## base stays the CENTRE of the roll: a big dog still yaps low, it just never fires the identical sample twice.
## A few-percent wobble is nowhere near the pitch ratio that separates a small dog from a large one.
## The highest-value site of the lot is scripts/npc/damage.gd, which fires on EVERY damage tick — one yell per
## shotgun pellet, one per burst round — so unvaried it reads as a stuck sample rather than a person.
##   * MUSIC, AMBIENCE AND ANY LOOP — beds restart themselves on `finished`, so a per-play roll would re-tune the
##     bed every lap. Music, AmbientSound, the radio's track, the CRT hum + fan, the falling/slide wind, the
##     held-prop pant, the heartbeat.
## `play_sfx` / `play_2d_sfx` therefore take a `vary` flag: it defaults TRUE (the common case is a world sound)
## and a non-diegetic caller passes `false`. Loops and menu cues never route through here at all.
##
## MULTIPLIES, never replaces — which is what makes it safe to apply across every world site: a caller whose
## pitch already MEANS something keeps its meaning. The ammo-driven fire sag and the HP-driven enemy-hit
## deepening still read exactly as authored, and the wider per-site spreads (footsteps, impacts, muzzle whiz)
## still do their own thing; they simply stop being byte-exact on a retrigger.
##
## Uses the global `randf_range` rather than an owned RandomNumberGenerator on purpose: nothing here needs to
## be reproducible from a seed, and one shared stream keeps this callable from any thread-free context.
##
## Reads GameSettings live, so this must not be called during autoload boot — AudioManager is autoload #1 and
## GameSettings is #4. Every caller is a gameplay event long after boot.
func vary_pitch(base_pitch: float = 1.0) -> float:
	var spread: float = GameSettings.audio.global_pitch_spread
	if spread <= 0.0:
		return maxf(MIN_PITCH, base_pitch)
	return maxf(MIN_PITCH, base_pitch * randf_range(1.0 - spread, 1.0 + spread))


## Play an AUTHORED audio player node with this play's pitch variation stamped on first — the node-driven half
## of what play_sfx/play_2d_sfx give one-shots for free. Use it in place of `some_player.play()` at any WORLD
## site that RETRIGGERS a persistent AudioStreamPlayer/2D/3D living in a scene (gunfire, the dry-fire click, a
## shell tink, a gore splash, a light switch) so that site doesn't hand-roll a 20th randf_range.
##
## ⭐Same boundary as vary_pitch, and it matters more here because this is the call you'd reach for by habit:
## a MENU cue, a HUD/alert sting, a reward jingle or a LOOP must keep calling `player.play()` directly.
##
## `base_pitch` is the pitch the site MEANS (1.0 for most; the ammo-driven sag for the weapon's fire player) and
## is multiplied, not replaced. The variation is written on EVERY play, never only the first: these nodes are
## reused, so a roll left behind by the previous play would silently transpose the next sound.
##
## Loosely typed `Node` because AudioStreamPlayer / ...2D / ...3D share no common audio base class; a node that
## can't play is a silent no-op so a caller can stay unconditional.
func play_varied(player: Node, base_pitch: float = 1.0) -> void:
	if player == null or not is_instance_valid(player) or not player.has_method(&"play"):
		return
	player.set(&"pitch_scale", vary_pitch(base_pitch))
	player.call(&"play")


## One-shot positional SFX. Routed to the `bus` (default "sfx") so the audio-options sliders actually
## affect it — a bare AudioStreamPlayer3D.new() lands on Master and ignores the SFX volume setting.
##
## ⭐`max_db` IS the audible loudness for this project's authored idiom, and callers that modulate volume have to
## pass it. AudioStreamPlayer3D outputs `min(volume_db + distance_attenuation, max_db)`, and the attenuation is
## POSITIVE inside `unit_size` (~+20 dB at 1 m with the default 10). At the volume_db ≈ 80 this project authors
## everywhere (weapon.tscn / enemy.tscn / the Player's audio exports), the sum is ~100 dB at any playable range —
## permanently pinned to the ceiling — so a caller that cuts only `volume_db` cuts NOTHING you can hear. Carrying
## the ceiling is the same discipline weapon_audio.gd / projectile.gd already follow when they copy an authored
## node's max_db onto their spawned one-shot.
## `vary` (default true) is the DIEGETIC flag: a world sound gets the global per-play pitch variation, a
## non-diegetic one (an alert sting, a HUD cue, a reward jingle) passes `false` and plays at exactly
## `pitch_scale`. See vary_pitch for why the boundary is drawn there.
func play_sfx(pos: Vector3, stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0, bus: StringName = &"sfx", max_db: float = DEFAULT_MAX_DB, vary: bool = true) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = vary_pitch(pitch_scale) if vary else pitch_scale
	player.max_db = max_db
	player.max_distance = DEFAULT_3D_MAX_DISTANCE
	player.bus = bus
	player.set_meta(ONE_SHOT_META, true)
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.global_position = pos
	player.play()


## One-shot 2D (in-your-ear) SFX. Routed to the `bus` (default "sfx") — see play_sfx, including `vary`.
## ⭐Being 2D is NOT the same as being non-diegetic, so the flag is never inferred from it: the bullet whiz, the
## ram thud and the grapple all play 2D and ARE world sounds, while the "!" sting and the cha-ching are not.
func play_2d_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0, bus: StringName = &"sfx", vary: bool = true) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = vary_pitch(pitch_scale) if vary else pitch_scale
	player.bus = bus
	player.set_meta(ONE_SHOT_META, true)
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()


## Play the crowd-applause cheer (2D, in-your-ear): a short beat at full volume then a quick fade, so the whole
## cheer lands in ~1.7s instead of dragging out the full crowd clip. Uses its OWN player + tween (NOT play_2d_sfx,
## whose auto-free-on-finish fights an early fade). The reward for an all-headshots kill (death.gd) AND for petting
## a Pettable both call this, so the cheer is defined in exactly one place.
func play_applause() -> void:
	var applause := AudioStreamPlayer.new()
	applause.stream = APPLAUSE
	applause.volume_db = APPLAUSE_VOLUME_DB  # the splash covers this cheer's whole span at +6 dB; see the const
	# NO pitch variation here on purpose: the cheer is a non-diegetic REWARD cue, not a world sound. See vary_pitch.
	applause.bus = &"sfx"  # respect the SFX volume slider (a bare player lands on Master and ignores it)
	applause.set_meta(ONE_SHOT_META, true)
	get_tree().root.add_child(applause)
	applause.play()
	var tw := applause.create_tween()
	tw.tween_interval(APPLAUSE_HOLD)
	tw.tween_property(applause, "volume_db", APPLAUSE_FADE_TO_DB, APPLAUSE_FADE)
	tw.tween_callback(applause.queue_free)


## Immediately cut any currently-playing SFX-bus players in the live tree.
## Persistent authored players are stopped in place; AudioManager one-shots are freed so stopping them does not leak.
func stop_sfx() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_stop_sfx_under(tree.root)


func _stop_sfx_under(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.get(&"bus") == SFX_BUS and bool(node.get(&"playing")):
			node.call(&"stop")
			if node.has_meta(ONE_SHOT_META):
				node.queue_free()
	for child in node.get_children():
		_stop_sfx_under(child)
