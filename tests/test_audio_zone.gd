extends GutTest

## Rank 17 (AudioZone): an Area3D that cross-fades a child AudioStreamPlayer between a silent floor and an active
## level as the player enters/leaves. Verifies the player-group ref-count, non-player rejection, and the fade math.

const AudioZoneScript = preload("res://scripts/components/audio_zone.gd")

func test_warnings_without_shape_or_player() -> void:
	var z = AudioZoneScript.new()
	var w := z._get_configuration_warnings()
	assert_gt(w.size(), 0, "a bare AudioZone warns (no shape, no player child)")
	z.free()

func test_refcount_tracks_player_bodies() -> void:
	var z = AudioZoneScript.new()
	z.autoplay = false
	var sp := AudioStreamPlayer.new()
	z.add_child(sp)
	add_child_autofree(z)
	var body := Node.new()
	body.add_to_group(&"Player")
	add_child_autofree(body)
	assert_false(z.is_active(), "no player inside at start")
	z._on_body_entered(body)
	assert_true(z.is_active(), "player inside => active")
	z._on_body_exited(body)
	assert_false(z.is_active(), "player left => inactive")

func test_non_player_body_ignored() -> void:
	var z = AudioZoneScript.new()
	z.autoplay = false
	var sp := AudioStreamPlayer.new()
	z.add_child(sp)
	add_child_autofree(z)
	var crate := Node.new()  # not in the player group
	add_child_autofree(crate)
	z._on_body_entered(crate)
	assert_false(z.is_active(), "a non-player body doesn't activate the zone")

func test_fade_moves_toward_active_then_inactive() -> void:
	var z = AudioZoneScript.new()
	z.autoplay = false
	z.active_volume_db = 0.0
	z.inactive_volume_db = -40.0
	z.fade_speed = 24.0
	var sp := AudioStreamPlayer.new()
	z.add_child(sp)
	add_child_autofree(z)
	assert_almost_eq(sp.volume_db, -40.0, 0.01, "starts at the inactive floor")
	var body := Node.new()
	body.add_to_group(&"Player")
	add_child_autofree(body)
	z._on_body_entered(body)
	z._process(1.0)
	assert_almost_eq(sp.volume_db, -16.0, 0.01, "fades up 24 dB/s toward active")
	z._process(1.0)
	assert_almost_eq(sp.volume_db, 0.0, 0.01, "reaches active and clamps")
	z._on_body_exited(body)
	z._process(1.0)
	assert_almost_eq(sp.volume_db, -24.0, 0.01, "fades back down toward inactive")
