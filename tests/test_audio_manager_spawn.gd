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

func _audio_players(node: Node) -> Dictionary:
	var out := {}
	_collect_audio_players(node, out)
	return out

func _collect_audio_players(node: Node, out: Dictionary) -> void:
	if node is AudioStreamPlayer3D or node is AudioStreamPlayer:
		out[node] = true
	for child in node.get_children():
		_collect_audio_players(child, out)
