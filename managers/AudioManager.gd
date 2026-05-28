extends Node

# AudioManager — central helper for one-shot sound effects.
#
# Phase 1 deliverable: skeleton with the API shape. Existing AudioStreamPlayer3D
# nodes in the project (gun shots, footsteps, etc.) are NOT yet migrated to this
# manager — Phase 3 covers that. Until then, call sites can opt-in by switching
# from direct .play() to AudioManager.play_sfx(...).
#
# Migration rule for existing AudioStreamPlayer nodes (Phase 1 instruction):
#   - If a node is animation-driven (an AnimationPlayer track references its
#     stream/playing/volume_db properties), KEEP it and add the comment
#     "# disabled in favor of AudioManager" once migration is complete.
#   - Otherwise, remove the node and replace .play() with AudioManager.play_sfx.
# (This project has no AnimationPlayer-driven audio yet, so straight removal
# will be the default once we start the migration.)

const DEFAULT_3D_MAX_DISTANCE: float = 30.0


func play_sfx(pos: Vector3, stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_distance = DEFAULT_3D_MAX_DISTANCE
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.global_position = pos
	player.play()


func play_2d_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()
