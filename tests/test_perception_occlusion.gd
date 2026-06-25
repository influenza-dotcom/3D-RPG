extends GutTest

## Perception.hearing_attenuation -- the sound-occlusion multiplier on a heard noise's radius (stealth Slice 7).
## When occlusion is OFF it returns 1.0, so sound rounds corners exactly as before AND a bare off-tree Perception
## never reaches the world raycast. This project SHIPS occlusion ON (GameSettings.npc_ai.hearing_occlusion), so the
## test forces it OFF locally to verify the occlusion-OFF code path in isolation. The actual wall ray (_wall_between,
## reached only when occlusion is on + in-tree) is manual-playtest, like the other in-tree perception rays.

func test_attenuation_is_full_when_occlusion_off() -> void:
	# Force occlusion OFF locally (independent of the shipped GameSettings.npc_ai.hearing_occlusion, now ON) so this
	# verifies the OFF path: hearing_attenuation returns 1.0 BEFORE it would touch global_position / the world ray.
	# Restored synchronously; GUT asserts don't halt, so the restore always runs even on a failed assert.
	var prior: bool = GameSettings.npc_ai.hearing_occlusion
	GameSettings.npc_ai.hearing_occlusion = false
	var p := Perception.new()
	assert_almost_eq(p.hearing_attenuation(Vector3(5.0, 0.0, 0.0)), 1.0, 0.0001, "occlusion off -> no muffling (sound rounds corners as before)")
	assert_almost_eq(p.hearing_attenuation(Vector3(0.0, 0.0, 0.0)), 1.0, 0.0001, "occlusion off -> 1.0 wherever the source is")
	p.free()
	GameSettings.npc_ai.hearing_occlusion = prior
