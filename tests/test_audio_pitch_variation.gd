extends GutTest
# Test: the GLOBAL per-play pitch variation seam — AudioManager.vary_pitch / play_varied, driven by
# GameSettings.audio.global_pitch_spread. This is the "no sound the WORLD makes ever plays at the exact same
# pitch twice" contract, and it is applied at ~20 world call sites, so the properties that make that safe are
# the ones worth pinning:
#
#   1. It MULTIPLIES the caller's pitch instead of replacing it. Every site whose pitch already MEANS
#      something (the ammo-driven fire sag, the HP-driven enemy-hit deepening, the wider per-site spreads on
#      footsteps/impacts/whiz) depends on this. A refactor to "return a random pitch" would silently flatten
#      all of them and nothing else would fail.
#   2. It never returns 0. pitch_scale 0 hangs a voice forever, which for a play_sfx one-shot (freed on
#      `finished`) is a LEAK, not just silence.
#   3. `vary = false` is an EXACT passthrough. That flag is what keeps the variation on the diegetic side of
#      the line: menu chrome, the MGS "!" alert and the other HUD stings, reward jingles and music must sound
#      the same every time, and the flag is the only thing standing between them and a wobble. VOICES are NOT
#      in that group — they vary like any other world sound, safely, because property 1 keeps a creature's
#      authored base pitch (its rolled body size) as the CENTRE of the roll rather than replacing it.
#
# The spread is restored in every test that touches it — GameSettings.audio is a shared preloaded Resource,
# so a leaked write would follow the whole suite into unrelated audio tests.

const SAMPLES: int = 200  ## enough rolls that "it actually varies" isn't a coin flip; see _roll_spread

func test_vary_pitch_multiplies_the_callers_pitch_rather_than_replacing_it() -> void:
	var restore: float = GameSettings.audio.global_pitch_spread
	GameSettings.audio.global_pitch_spread = 0.05
	# A caller that MEANS 0.7 (a near-empty magazine) must still land near 0.7, never near 1.0.
	for i in SAMPLES:
		var got := AudioManager.vary_pitch(0.7)
		assert_between(got, 0.7 * 0.95 - 0.0001, 0.7 * 1.05 + 0.0001,
			"vary_pitch must scale the caller's base pitch by +/- the spread, so an authored detune survives")
	GameSettings.audio.global_pitch_spread = restore


func test_vary_pitch_actually_varies() -> void:
	var restore: float = GameSettings.audio.global_pitch_spread
	GameSettings.audio.global_pitch_spread = 0.05
	assert_gt(_roll_spread(SAMPLES), 0.0,
		"with a non-zero spread, repeated plays must not all land on the same pitch — that IS the feature")
	GameSettings.audio.global_pitch_spread = restore


func test_zero_spread_is_an_exact_passthrough() -> void:
	# The escape hatch: 0.0 must pin every play to exactly what the caller asked for (a mix recording, or a
	# designer switching the whole effect off from the AudioSettings inspector).
	var restore: float = GameSettings.audio.global_pitch_spread
	GameSettings.audio.global_pitch_spread = 0.0
	for i in 20:
		assert_eq(AudioManager.vary_pitch(1.0), 1.0, "spread 0 must return the base pitch untouched")
		assert_eq(AudioManager.vary_pitch(0.75), 0.75, "spread 0 must not disturb an authored detune either")
	GameSettings.audio.global_pitch_spread = restore


func test_vary_pitch_never_returns_a_hanging_zero() -> void:
	# pitch_scale 0 never advances the stream, so `finished` never fires and AudioManager's one-shots (which
	# free themselves on that signal) would leak. Both a pathological spread and a 0 base are floored.
	var restore: float = GameSettings.audio.global_pitch_spread
	GameSettings.audio.global_pitch_spread = 1.0  # the extreme end: a roll can reach the 1.0 - spread == 0 edge
	for i in SAMPLES:
		assert_gte(AudioManager.vary_pitch(1.0), AudioManager.MIN_PITCH,
			"even at maximum spread the result must stay at or above MIN_PITCH — 0 hangs the voice forever")
	GameSettings.audio.global_pitch_spread = 0.05
	assert_gte(AudioManager.vary_pitch(0.0), AudioManager.MIN_PITCH,
		"a caller handing in 0 must still be floored, not passed straight through to a hung voice")
	GameSettings.audio.global_pitch_spread = restore


## THE DIEGETIC BOUNDARY. `vary = false` must be an EXACT passthrough on both spawn helpers — it is the only
## thing keeping the world-SFX variation off menu chrome, the MGS "!" alert and the rest of the HUD stings, the
## cha-ching reward jingles, and the hitmarker ding (whose pitch carries the target's HP and would be blurred by
## a wobble). Asserted against a real spawned player, not just the pure helper, because the bug this guards
## against is someone "simplifying" play_sfx back to an unconditional vary_pitch() call.
func test_vary_false_plays_at_exactly_the_requested_pitch() -> void:
	var restore: float = GameSettings.audio.global_pitch_spread
	GameSettings.audio.global_pitch_spread = 0.05  # a spread big enough that any leak would show up immediately

	# EPSILON, not assert_eq: pitch_scale is stored as a 32-bit float, so 0.83 reads back as 0.8299999833 and an
	# exact comparison against the double literal fails even when the passthrough is perfectly correct. The
	# epsilon is far tighter than the 0.05 spread above, so a leaked variation still fails loudly.
	for i in 25:
		assert_almost_eq(_spawn_2d_pitch(0.83, false), 0.83, 0.0001,
			"vary=false must play at EXACTLY the requested pitch — a UI sting / reward jingle must never wobble")

	assert_almost_eq(_spawn_3d_pitch(1.0, false), 1.0, 0.0001,
		"play_sfx's vary=false opt-out must be exact too, not only play_2d_sfx's")

	GameSettings.audio.global_pitch_spread = restore


## The default is the WORLD case. A caller that says nothing gets variation — that asymmetry is deliberate
## (there are far more world sounds than UI cues), so it is worth pinning that nobody flips the default.
func test_variation_is_the_default_for_a_caller_that_says_nothing() -> void:
	var restore: float = GameSettings.audio.global_pitch_spread
	GameSettings.audio.global_pitch_spread = 0.05

	var seen := {}
	for i in 40:  # spawns a real player per iteration, so keep it well under SAMPLES
		seen[_spawn_2d_pitch(1.0)] = true
	assert_gt(seen.size(), 1,
		"a play_2d_sfx caller that passes no `vary` argument must get the world-sound variation by default")

	GameSettings.audio.global_pitch_spread = restore


## play_varied is the NODE-driven half of the seam (an authored AudioStreamPlayer a WORLD site retriggers — the
## weapon's fire player, an NPC's death-cry player). It must stamp the pitch on EVERY call, not just the first:
## these nodes are reused, so a roll left behind by the previous play would transpose the next sound.
func test_play_varied_stamps_a_fresh_pitch_on_every_play() -> void:
	var restore: float = GameSettings.audio.global_pitch_spread
	GameSettings.audio.global_pitch_spread = 0.05

	var p := AudioStreamPlayer.new()
	p.stream = _silent_wav()
	p.bus = &"sfx"
	p.volume_db = -80.0
	add_child_autofree(p)

	var seen := {}
	for i in SAMPLES:
		AudioManager.play_varied(p)
		seen[p.pitch_scale] = true
	assert_gt(seen.size(), 1,
		"play_varied must re-roll pitch_scale on each call — a once-only stamp leaves a stale detune on a reused voice")
	p.stop()
	GameSettings.audio.global_pitch_spread = restore


## Callers stay unconditional (`AudioManager.play_varied(maybe_null_export)`), so a missing node is a silent
## no-op rather than an error — the same shape play_sfx's `stream == null` early-out already has.
func test_play_varied_is_a_silent_noop_on_a_node_that_cannot_play() -> void:
	AudioManager.play_varied(null)
	var plain := Node.new()
	add_child_autofree(plain)
	AudioManager.play_varied(plain)  # no `play` method — must not error
	assert_true(true, "play_varied tolerates null / a non-audio node so call sites can stay unconditional")


## Fire one play_2d_sfx and hand back the pitch_scale of the player it spawned, tidying that player up. Finding
## it by diffing the root's children is test_audio_manager_spawn.gd's idiom too: the headless dummy audio driver
## never emits `finished`, so a spawned one-shot never frees itself here and must be freed by hand.
func _spawn_2d_pitch(base_pitch: float, vary: bool = true) -> float:
	var before := _root_audio_players()
	AudioManager.play_2d_sfx(_silent_wav(), -80.0, base_pitch, &"sfx", vary)
	for child in get_tree().root.get_children():
		if child is AudioStreamPlayer and not before.has(child):
			var got: float = child.pitch_scale
			child.stop()
			child.queue_free()
			return got
	return NAN  # nothing spawned; every caller feeds this straight into an assert, which then fails loudly


## The 3D twin of _spawn_2d_pitch. AudioStreamPlayer3D is a SIBLING of AudioStreamPlayer, not a subclass, so
## the two type tests cannot be merged into one loop.
func _spawn_3d_pitch(base_pitch: float, vary: bool = true) -> float:
	var before := _root_audio_players()
	AudioManager.play_sfx(Vector3.ZERO, _silent_wav(), -80.0, base_pitch, &"sfx", AudioManager.DEFAULT_MAX_DB, vary)
	for child in get_tree().root.get_children():
		if child is AudioStreamPlayer3D and not before.has(child):
			var got: float = child.pitch_scale
			child.stop()
			child.queue_free()
			return got
	return NAN


## Set of the audio players parented DIRECTLY to the root — which is exactly where AudioManager puts its
## one-shots, so a shallow scan suffices and avoids walking the whole live scene on every iteration.
func _root_audio_players() -> Dictionary:
	var out := {}
	for child in get_tree().root.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			out[child] = true
	return out


## Spread of the varied pitch over `n` rolls at a fixed base. Zero means every roll was identical.
func _roll_spread(n: int) -> float:
	var lo := INF
	var hi := -INF
	for i in n:
		var v := AudioManager.vary_pitch(1.0)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


func _silent_wav() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var silence := PackedByteArray()
	silence.resize(22050)
	stream.data = silence
	return stream
