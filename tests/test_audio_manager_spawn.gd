extends GutTest
# Test: call AudioManager.play_sfx with a short audio stream, wait past its
# duration, and confirm the temporary AudioStreamPlayer3D was auto-freed.
# This drives the live AudioManager autoload, so it awaits a real timer for the
# player's `finished` -> queue_free chain (GUT awaits frames inside a test fine).

func test_play_sfx_spawns_then_auto_frees() -> void:
	assert_not_null(AudioManager,
		"AudioManager autoload must be present — play_sfx() is called on it by name from attack/impact code")

	var root := get_tree().root
	var before := _count_audio_players(root)

	# Create a synthetic ~50ms silent audio stream so the player auto-frees quickly.
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.05
	AudioManager.play_sfx(Vector3.ZERO, stream, -80.0, 1.0)

	var during := _count_audio_players(root)
	assert_gt(during, before,
		"play_sfx() must add a temporary AudioStreamPlayer3D to the tree (before=%d, during=%d)" % [before, during])

	# Wait long enough for the player's `finished` signal -> queue_free chain.
	await get_tree().create_timer(0.4, true, false, true).timeout

	var after := _count_audio_players(root)
	assert_lte(after, before,
		"The temporary audio player must free itself after playback so play_sfx() doesn't leak nodes (before=%d, after=%d)" % [before, after])

func _count_audio_players(node: Node) -> int:
	var n := 0
	if node is AudioStreamPlayer3D or node is AudioStreamPlayer:
		n += 1
	for child in node.get_children():
		n += _count_audio_players(child)
	return n
