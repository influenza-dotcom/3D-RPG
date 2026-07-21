extends GutTest

## Scene-wiring contract for radio.tscn — a drop-in diegetic Radio (Area3D look-at interactable). Its `audio_player`
## export is WIRED in the prefab (node_paths) to the child AudioStreamPlayer3D on the &"radio" bus. This ref matters:
## radio.gd auto-creates a player ONLY when it's missing (`if audio_player == null`), so a dropped wiring wouldn't
## error — it would silently spawn a stand-in player and the authored &"radio" effect-bus routing would be lost.
##
## Complements test_radio.gd / test_radio_playback_state.gd (off-tree logic). In-tree (add_child_autofree) so the
## node_paths export resolves to the live child, mirroring test_door_prefab.gd; radio._ready is harmless here
## (auto_fit_collider defaults off, so no off-tree transform math; the audio player is wired, so nothing is spawned).

const PREFAB := "res://scenes/components/radio.tscn"


func test_audio_player_export_resolves_to_the_wired_child() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "radio.tscn loads")
	if scene == null:
		return
	var radio := scene.instantiate()
	add_child_autofree(radio)  # in-tree so the exported node_paths ref resolves to the live child
	assert_true(radio is Radio, "the root carries the Radio script")
	assert_true(radio is LookAtInteractable, "a Radio is a LookAtInteractable (shares the talk-handler surface)")
	var wired := radio.get_node_or_null(^"AudioStreamPlayer3D")
	assert_not_null(wired, "the prefab has the AudioStreamPlayer3D child the export points at")
	assert_not_null(radio.audio_player, "`audio_player` resolved — a null here means the wiring dropped and _ready spawned a fallback")
	assert_eq(radio.audio_player, wired, "`audio_player` points at the authored child, not an auto-created stand-in")
	if radio.audio_player != null:
		assert_true(radio.audio_player is AudioStreamPlayer3D, "the wired player is an AudioStreamPlayer3D")
		assert_eq(radio.audio_player.bus, &"radio", "the wired player is on the &\"radio\" bus (the tinny radio effect chain)")


func test_prefab_has_a_look_at_collision_shape() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "radio.tscn loads")
		return
	var radio := scene.instantiate()
	var shape: CollisionShape3D = null
	for c in radio.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
			break
	assert_not_null(shape, "the prefab has a CollisionShape3D child (the body you aim at to toggle it)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	radio.free()
