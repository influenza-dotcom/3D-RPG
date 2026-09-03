extends GutTest
# Test: a weapon that RETRIGGERS faster than its sample finishes must not chop itself. The SMG fires every
# 0.125 s and its report (Rifle.mp3) runs 3.55 s, so restarting the one shared `Attack Audio` node cut every
# shot 125 ms in — at the loudest point of the decay, which reads as a click rather than as a burst. WeaponAudio
# now rings each trigger pull on its own throwaway clone of the node (_play_voice) under a voice cap.
#
# Assertions are structural (the voices exist, keep the authored mix, and are wired to self-free) rather than
# audible: the headless runner uses the dummy audio driver, where playback never advances and `finished` never
# fires — the same reason test_audio_manager_spawn.gd asserts the free CONTRACT instead of awaiting it.

var _host: Node3D
var _source: AudioStreamPlayer3D
var _shell: AudioStreamPlayer3D
var _audio: WeaponAudio
var _saved_limit: int

## A finite ~50 ms silent WAV — an AudioStreamGenerator would be an INFINITE stream that never finishes.
func _silent_wav() -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = 22050
	s.stereo = false
	var silence := PackedByteArray()
	silence.resize(int(22050 * 0.05))
	s.data = silence
	return s

func before_each() -> void:
	_saved_limit = GameSettings.audio.retrigger_voice_limit
	_host = Node3D.new()
	add_child_autofree(_host)
	# Stand-ins for weapon.tscn's `Attack Audio` / `ShellImpact`, carrying a deliberately ODD authored mix so a
	# voice that silently dropped one of those fields shows up as a mismatch rather than as a matching default.
	_source = AudioStreamPlayer3D.new()
	_source.name = "Attack Audio"
	_source.stream = _silent_wav()
	_source.bus = &"gunshots"
	_source.volume_db = 12.0
	_source.max_db = 6.0
	_source.unit_size = 42.0
	_source.max_distance = 77.0
	_source.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_host.add_child(_source)
	_shell = AudioStreamPlayer3D.new()
	_shell.name = "ShellImpact"
	_shell.stream = _silent_wav()
	_shell.bus = &"world"
	_host.add_child(_shell)
	_audio = WeaponAudio.new()
	_host.add_child(_audio)
	_audio.setup(_source, null, null, null, null, _shell)

func after_each() -> void:
	GameSettings.audio.retrigger_voice_limit = _saved_limit

## Every live voice spawned from `source`, in play order — its ONE_SHOT_META siblings, minus the ones already
## cut this frame (queue_free leaves the node parented until the end of the frame, so an un-filtered count
## would over-report). Identified by the meta rather than by name: a colliding name is auto-suffixed.
func _voices(source: AudioStreamPlayer3D) -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for c in source.get_parent().get_children():
		if c == source or not (c is AudioStreamPlayer3D):
			continue
		if not c.has_meta(AudioManager.ONE_SHOT_META) or c.is_queued_for_deletion():
			continue
		if String(c.name).begins_with(String(source.name)):  # `Attack AudioVoice3` vs `ShellImpactVoice2`
			out.append(c)
	return out

func _gun(ammo: int = 30) -> WeaponData:
	var w := WeaponData.new()
	w.audio = _silent_wav()
	w.max_ammo = ammo
	return w

## THE regression: three trigger pulls in one beat leave three sounds RINGING, not one restarted node.
func test_a_burst_rings_one_voice_per_shot_instead_of_restarting_the_shared_node() -> void:
	var weapon := _gun()
	for i in 3:
		_audio.play_fire(weapon, 30 - i)
	assert_eq(_voices(_source).size(), 3,
		"each trigger pull must ring on its OWN voice — restarting the shared `Attack Audio` node is what cut "
		+ "the SMG's 3.55 s report 125 ms in and made held fire read as a stuttering click")
	assert_false(_source.playing,
		"the shared node itself must never be retriggered by a shot — it stays free for the spray-can hiss, "
		+ "which is the one fire path that DOES want a single non-restarting play (attack.gd's burst tick)")

## The pitch half of the same fix: a voice per shot is only worth having if each keeps the pitch it was fired
## at. AudioStreamPlayer3D's own `max_polyphony` would not — `pitch_scale` is a NODE property the 3D mixer
## re-applies to every live playback, so the newest roll would drag every still-ringing tail with it.
func test_each_voice_keeps_its_own_pitch_and_the_shared_node_is_never_retuned() -> void:
	var weapon := _gun()
	_audio.play_fire(weapon, 30)  # full mag — the bright end
	_audio.play_fire(weapon, 1)   # last round — the deep end
	var voices := _voices(_source)
	assert_eq(voices.size(), 2, "two shots, two voices")
	if voices.size() < 2:
		return
	assert_eq(_source.pitch_scale, 1.0,
		"the shared node's pitch_scale must be left alone — writing it is what would transpose every tail "
		+ "still ringing from earlier shots")
	# The ammo sag survives the refactor. The two windows cannot overlap: full mag rolls 1.0 ± 15% (>= 0.85)
	# and the last round rolls 0.7 ± 15% (<= 0.805), so this is deterministic despite the random variation.
	assert_lt(voices[1].pitch_scale, voices[0].pitch_scale,
		"the Cruelty-Squad ammo sag must still deepen the shot as the mag empties — the last round fires "
		+ "lower than a full mag, with the global per-play variation multiplied AROUND that base")

## The voices carry the node's AUTHORED mix, which is why they are a duplicate() rather than a copy-N-fields
## helper: volume_db and the max_db ceiling (the knob that is actually audible at this project's volumes),
## the attenuation model, unit_size and max_distance. Only stream + bus are the caller's to overwrite.
func test_a_voice_carries_the_authored_mix_and_the_per_play_stream_and_bus() -> void:
	var weapon := _gun()
	_audio.play_fire(weapon, 30)
	var voices := _voices(_source)
	assert_eq(voices.size(), 1, "one shot, one voice")
	if voices.is_empty():
		return
	var v := voices[0]
	assert_eq(v.volume_db, _source.volume_db, "a voice must inherit the node's authored volume_db")
	assert_eq(v.max_db, _source.max_db,
		"a voice must inherit the authored max_db — at this project's volumes the ceiling IS the loudness, "
		+ "so dropping it would mute or blast the shot")
	assert_eq(v.unit_size, _source.unit_size, "a voice must inherit the authored unit_size falloff")
	assert_eq(v.max_distance, _source.max_distance, "a voice must inherit the authored max_distance")
	assert_eq(v.attenuation_model, _source.attenuation_model, "a voice must inherit the authored attenuation model")
	assert_eq(v.stream, weapon.audio,
		"the voice plays THIS weapon's trigger sound — one shared node serves every weapon, so the stream is "
		+ "the caller's to set, never the node's authored default")
	assert_eq(v.bus, &"gunshots",
		"an outdoor gun's voice still routes through WeaponAudio.fire_bus_for — the city-billow bus, re-picked "
		+ "per play so the fists never inherit a gun's echo")
	assert_true(v.has_meta(AudioManager.ONE_SHOT_META),
		"a voice must carry ONE_SHOT_META so AudioManager.stop_sfx() can both CUT and FREE it — without the "
		+ "meta a menu/death cut stops the voice and strands the node for the rest of the session")
	assert_true(v.finished.is_connected(Callable(v, "queue_free")),
		"a voice must self-free when its sound ends, or a held trigger leaks one node per round")

## Held fire is bounded: past the cap the OLDEST voice is cut, never the newest. By then that tail is many
## shots deep and buried under newer ones, so the cut lands where it is inaudible.
func test_the_voice_cap_cuts_the_oldest_not_the_newest() -> void:
	GameSettings.audio.retrigger_voice_limit = 3
	var weapon := _gun()
	var newest: AudioStreamPlayer3D = null
	for i in 6:
		_audio.play_fire(weapon, 30 - i)
		var live := _voices(_source)
		newest = live[live.size() - 1]
	var voices := _voices(_source)
	assert_eq(voices.size(), 3,
		"six rounds under a cap of 3 must leave exactly 3 ringing — an uncapped pool grows one node per round "
		+ "for as long as the trigger is held")
	assert_true(voices.has(newest),
		"the cap must cut the OLDEST voice — cutting the newest would silence the shot you just fired")

## The shell tink rides with the shot and had the same problem (a 1.9 s bounce, one per round), so it gets the
## same treatment — on its own `world` bus, because a casing is foley and never takes the gunshot billow.
func test_the_shell_tink_gets_its_own_voices_on_the_world_bus() -> void:
	_audio.play_shell()
	_audio.play_shell()
	var voices := _voices(_shell)
	assert_eq(voices.size(), 2,
		"the casing tink must ring per round too — on the shared node an SMG burst clipped every shell after "
		+ "the first 125 ms of its 1.9 s bounce")
	if voices.is_empty():
		return
	assert_eq(voices[0].bus, &"world",
		"a shell tink is world foley — it keeps the node's authored `world` bus and must never pick up the "
		+ "`gunshots` city billow")
	assert_eq(voices[0].stream, _shell.stream,
		"the shell tink has no per-weapon variant — the voice plays the node's authored stream")
