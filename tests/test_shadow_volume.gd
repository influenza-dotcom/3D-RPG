extends GutTest

## Rank 27.1 (ShadowVolume): a painted Area3D that writes light_exposure on a player body while inside and
## restores it on exit, so enemy Perception (with the global light curve) detects slower in the dark.

const ShadowVolumeScript = preload("res://scripts/components/shadow_volume.gd")

class StubBody extends Node:
	var light_exposure: float = 1.0

func test_writes_shadow_exposure_on_enter_restores_on_exit() -> void:
	var sv = ShadowVolumeScript.new()
	sv.shadow_exposure = 0.1
	var body := StubBody.new()
	body.add_to_group(Groups.PLAYER)  # the REAL player group (&"Player") — exercises the shipped default
	add_child_autofree(body)
	sv._on_body_entered(body)
	assert_almost_eq(body.light_exposure, 0.1, 0.001, "inside the shadow -> dim exposure")
	assert_true(sv.is_occupied(), "the shadow is occupied")
	sv._on_body_exited(body)
	assert_almost_eq(body.light_exposure, 1.0, 0.001, "left the shadow -> fully lit again")
	assert_false(sv.is_occupied(), "no longer occupied")
	sv.free()

func test_non_player_body_ignored() -> void:
	var sv = ShadowVolumeScript.new()
	sv.shadow_exposure = 0.0
	var crate := StubBody.new()  # not in the player group
	add_child_autofree(crate)
	sv._on_body_entered(crate)
	assert_almost_eq(crate.light_exposure, 1.0, 0.001, "a non-player body isn't dimmed")
	assert_false(sv.is_occupied(), "not occupied by a non-qualifying body")
	sv.free()

func test_config_warning_without_shape() -> void:
	var sv = ShadowVolumeScript.new()
	assert_gt(sv._get_configuration_warnings().size(), 0, "a shapeless ShadowVolume warns")
	sv.free()
