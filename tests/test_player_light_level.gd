extends GutTest

## PlayerLightLevel.light_contribution -- the pure linear range-falloff a single lamp adds at a point (stealth
## light slice, live sampling). Full `energy` at the lamp, 0 at the edge of `light_range`. The in-tree _sample
## (scan the &"lights" group + LOS rays + write host.light_exposure) is manual-playtest.

func test_light_contribution_linear_falloff() -> void:
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 10.0, 0.0), 1.0, 0.0001, "at the lamp -> full energy")
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 10.0, 5.0), 0.5, 0.0001, "half range -> half")
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 10.0, 10.0), 0.0, 0.0001, "at the edge -> 0")
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 10.0, 15.0), 0.0, 0.0001, "beyond range -> 0")

func test_light_contribution_scales_with_energy_and_guards_range() -> void:
	assert_almost_eq(PlayerLightLevel.light_contribution(2.0, 10.0, 5.0), 1.0, 0.0001, "brighter lamp (energy 2) at half range -> 1.0")
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 0.0, 5.0), 0.0, 0.0001, "zero range -> 0 (no divide-by-zero)")
	assert_almost_eq(PlayerLightLevel.light_contribution(-1.0, 10.0, 5.0), 0.0, 0.0001, "negative energy clamps to 0")
