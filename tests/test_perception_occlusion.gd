extends GutTest

## Perception.hearing_attenuation -- the sound-occlusion multiplier on a heard noise's radius (stealth Slice 7).
## OFF by default (GameSettings.npc_ai.hearing_occlusion) -> always 1.0, so sound rounds corners exactly as
## before (behaviour-preserving) AND a bare off-tree Perception never reaches the world raycast. The actual
## wall ray (_wall_between, reached only when occlusion is on + in-tree) is manual-playtest, like the other
## in-tree perception rays.

func test_attenuation_is_full_when_occlusion_off() -> void:
	# Default occlusion is OFF, so hearing_attenuation returns 1.0 BEFORE it would touch global_position / the
	# world — safe + behaviour-preserving on an off-tree Perception.
	assert_false(GameSettings.npc_ai.hearing_occlusion, "occlusion defaults OFF (the precondition for this test)")
	var p := Perception.new()
	assert_almost_eq(p.hearing_attenuation(Vector3(5.0, 0.0, 0.0)), 1.0, 0.0001, "occlusion off -> no muffling (sound rounds corners as before)")
	assert_almost_eq(p.hearing_attenuation(Vector3(0.0, 0.0, 0.0)), 1.0, 0.0001, "occlusion off -> 1.0 wherever the source is")
	p.free()
