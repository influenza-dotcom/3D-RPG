extends Node
# Test: call AudioManager.play_sfx with a short audio stream, wait past its
# duration, and confirm the temporary AudioStreamPlayer3D was auto-freed.
# To run: attach to a Node3D, F6.

func _ready() -> void:
	_run()

func _run() -> void:
	print("[test_audio_manager_spawn] starting...")
	assert(AudioManager != null, "FAIL: AudioManager autoload not present")
	print("PASS: AudioManager autoload is reachable")

	var root := get_tree().root
	var before := _count_audio_players(root)

	# Create a synthetic ~50ms silent audio stream so the player auto-frees quickly.
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.05
	AudioManager.play_sfx(Vector3.ZERO, stream, -80.0, 1.0)

	var during := _count_audio_players(root)
	assert(during > before, "FAIL: play_sfx should add an audio player to the tree")
	print("PASS: play_sfx added a player (before=%d, during=%d)" % [before, during])

	# Wait long enough for the player's `finished` signal -> queue_free chain.
	await get_tree().create_timer(0.4, true, false, true).timeout

	var after := _count_audio_players(root)
	assert(after <= before, "FAIL: temporary audio player did not free (before=%d, after=%d)" % [before, after])
	print("PASS: temporary player freed after playback (before=%d, after=%d)" % [before, after])
	print("[test_audio_manager_spawn] ALL PASS")

func _count_audio_players(node: Node) -> int:
	var n := 0
	if node is AudioStreamPlayer3D or node is AudioStreamPlayer:
		n += 1
	for child in node.get_children():
		n += _count_audio_players(child)
	return n
