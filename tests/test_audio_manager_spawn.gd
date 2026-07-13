extends GutTest
# Test: AudioManager.play_sfx spawns a temporary AudioStreamPlayer3D that is wired to free ITSELF when
# playback ends, so one-shot SFX never leak. We assert that leak-prevention CONTRACT (finished -> queue_free
# on the spawned player) rather than waiting for real playback to end: the headless runner uses the dummy
# audio driver, where `finished` never fires, so an "await past the duration, then count nodes" approach
# can't observe the auto-free AND is fragile to any unrelated sound playing during the wait. Tracking the
# specific player play_sfx spawned (not a global node count) keeps this robust to other audio in the tree.

func test_play_sfx_spawns_self_freeing_player() -> void:
	assert_not_null(AudioManager,
		"AudioManager autoload must be present — play_sfx() is called on it by name from attack/impact code")

	var root := get_tree().root
	var before := _audio_players(root)

	# A FINITE ~50ms silent WAV (an AudioStreamGenerator is an INFINITE real-time stream that never finishes).
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var silence := PackedByteArray()
	silence.resize(int(22050 * 0.05))  # ~50ms mono @ 8-bit; zero bytes = silence
	stream.data = silence
	AudioManager.play_sfx(Vector3.ZERO, stream, -80.0, 1.0)

	# Find the player play_sfx just spawned — the AudioStreamPlayer3D that wasn't in the tree before.
	var spawned: Node = null
	for p in _audio_players(root):
		if not before.has(p):
			spawned = p
			break
	assert_not_null(spawned,
		"play_sfx() must add a temporary AudioStreamPlayer3D to the tree")
	if spawned == null:
		return

	# The leak-prevention contract: the spawned player frees itself when playback finishes. We assert the
	# wiring rather than awaiting real playback, since the dummy audio driver never emits `finished`.
	assert_true(spawned.finished.is_connected(Callable(spawned, "queue_free")),
		"play_sfx()'s temporary player must wire finished -> queue_free so it self-frees after playback instead of leaking")

	spawned.queue_free()  # tidy up our own spawned player so it doesn't linger into later tests

## play_applause() is THE single source for the crowd-clap cheer (an all-headshots kill via death.gd, AND petting a
## Pettable). Assert it exists and spawns a 2D player wired to the shared APPLAUSE clip on the SFX bus. The
## fade/free is a tween (not the `finished` signal), so we tidy up the spawned player ourselves rather than await it.
func test_play_applause_spawns_the_shared_clap_cheer() -> void:
	assert_not_null(AudioManager,
		"AudioManager autoload must be present — play_applause() is called by name from death.gd and Pettable.pet()")
	assert_true(AudioManager.has_method("play_applause"),
		"AudioManager must expose play_applause() — the one place the kill + pet cheer is defined")

	var root := get_tree().root
	var before := _audio_players(root)
	AudioManager.play_applause()

	var spawned: AudioStreamPlayer = null
	for p in _audio_players(root):
		if not before.has(p) and p is AudioStreamPlayer:  # 2D player (AudioStreamPlayer3D is a sibling, not a subclass)
			spawned = p
			break
	assert_not_null(spawned,
		"play_applause() must add a temporary 2D AudioStreamPlayer to the tree")
	if spawned == null:
		return
	assert_eq(spawned.stream, AudioManager.APPLAUSE,
		"the spawned player plays the shared APPLAUSE clip (single source — death.gd no longer owns its own copy)")
	assert_eq(spawned.bus, &"sfx",
		"the applause routes to the SFX bus so the volume slider applies, not Master")
	spawned.queue_free()  # tidy up; the real beat-then-fade-then-free tween is left to runtime


func test_stop_sfx_stops_only_sfx_bus_players() -> void:
	assert_not_null(AudioManager,
		"AudioManager autoload must be present because the start menu calls stop_sfx() before launching the game")
	assert_true(AudioManager.has_method("stop_sfx"),
		"AudioManager must expose stop_sfx() so menu transitions can immediately cut active SFX")

	var sfx_2d := AudioStreamPlayer.new()
	sfx_2d.stream = _silent_wav()
	sfx_2d.bus = &"sfx"
	add_child_autofree(sfx_2d)

	var sfx_3d := AudioStreamPlayer3D.new()
	sfx_3d.stream = _silent_wav()
	sfx_3d.bus = &"sfx"
	add_child_autofree(sfx_3d)

	var music := AudioStreamPlayer.new()
	music.stream = _silent_wav()
	music.bus = &"music"
	add_child_autofree(music)

	sfx_2d.play()
	sfx_3d.play()
	music.play()
	AudioManager.stop_sfx()

	assert_false(sfx_2d.playing, "stop_sfx() must stop 2D SFX-bus players such as menu click sounds")
	assert_false(sfx_3d.playing, "stop_sfx() must stop 3D SFX-bus players such as the computer-room hum/static")
	assert_true(music.playing, "stop_sfx() must leave non-SFX buses alone so music/ambience are not globally killed")
	music.stop()


func test_stop_sfx_frees_audio_manager_one_shots() -> void:
	var root := get_tree().root
	var before := _audio_players(root)
	AudioManager.play_2d_sfx(_silent_wav(), -80.0, 1.0)

	var spawned: AudioStreamPlayer = null
	for p in _audio_players(root):
		if not before.has(p) and p is AudioStreamPlayer:
			spawned = p
			break
	assert_not_null(spawned,
		"play_2d_sfx() must spawn a temporary player before stop_sfx() can prove it frees stopped one-shots")
	if spawned == null:
		return

	AudioManager.stop_sfx()
	assert_true(spawned.is_queued_for_deletion(),
		"stop_sfx() must queue AudioManager one-shots for deletion after stopping them; a stopped player will not emit finished")


func _silent_wav() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var silence := PackedByteArray()
	silence.resize(22050)  # About 1s mono at 8-bit; long enough to still be playing when stop_sfx() runs.
	stream.data = silence
	return stream


func _audio_players(node: Node) -> Dictionary:
	var out := {}
	_collect_audio_players(node, out)
	return out

func _collect_audio_players(node: Node, out: Dictionary) -> void:
	if node is AudioStreamPlayer3D or node is AudioStreamPlayer:
		out[node] = true
	for child in node.get_children():
		_collect_audio_players(child, out)
