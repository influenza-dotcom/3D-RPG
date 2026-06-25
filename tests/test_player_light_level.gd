extends GutTest

## PlayerLightLevel: the pure linear range-falloff a single lamp adds at a point (light_contribution), the
## DirectionalLight toggle, and auto_collect's ungrouped-light discovery. The full in-tree _sample (per-frame
## position sample + LOS rays + writing host.light_exposure) stays manual-playtest; the harness covers the rest.

func test_light_contribution_linear_falloff() -> void:
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 10.0, 0.0), 1.0, 0.0001, "at the lamp -> full energy")
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 10.0, 5.0), 0.5, 0.0001, "half range -> half")
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 10.0, 10.0), 0.0, 0.0001, "at the edge -> 0")
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 10.0, 15.0), 0.0, 0.0001, "beyond range -> 0")

func test_light_contribution_scales_with_energy_and_guards_range() -> void:
	assert_almost_eq(PlayerLightLevel.light_contribution(2.0, 10.0, 5.0), 1.0, 0.0001, "brighter lamp (energy 2) at half range -> 1.0")
	assert_almost_eq(PlayerLightLevel.light_contribution(1.0, 0.0, 5.0), 0.0, 0.0001, "zero range -> 0 (no divide-by-zero)")
	assert_almost_eq(PlayerLightLevel.light_contribution(-1.0, 10.0, 5.0), 0.0, 0.0001, "negative energy clamps to 0")

## Rank 27.3: dropped under the player with no host set, it auto-wires host = parent (no Player.tscn edit).
func test_resolves_host_from_parent_when_unset() -> void:
	var parent := Node3D.new()
	var pll = load("res://scripts/player/player_light_level.gd").new()
	parent.add_child(pll)
	add_child_autofree(parent)  # entering the tree fires pll._ready
	assert_eq(pll.host, parent, "host auto-resolves to the parent when unset (drop-in)")


## A DirectionalLight (sun/moon) lights the host globally ONLY while directional_contributes is on — the knob that
## lets a sun-lit level still have dark, by excluding the sun from the meter. Off-tree: visible defaults true and a
## directional needs no position/range/ray, so _light_contribution_for is pure here.
func test_directional_contributes_toggle() -> void:
	var pll := PlayerLightLevel.new()
	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.0
	pll.directional_contributes = true
	assert_almost_eq(pll._light_contribution_for(sun, Vector3.ZERO), 2.0, 0.0001, "the sun contributes its energy when enabled")
	pll.directional_contributes = false
	assert_eq(pll._light_contribution_for(sun, Vector3.ZERO), 0.0, "the sun contributes nothing when the toggle is off (sun-lit-level knob)")
	sun.free()
	pll.free()


## auto_collect (the default): _collect_lights finds an UNGROUPED Light3D in the scene, so a designer never has to
## tag lights into the &"lights" group for dark-stealth to work — this is the whole point of the dynamic discovery.
func test_auto_collect_finds_ungrouped_light() -> void:
	var pll := PlayerLightLevel.new()
	add_child_autofree(pll)  # in-tree so get_tree()/current_scene resolve
	var lamp := OmniLight3D.new()
	add_child_autofree(lamp)  # deliberately NOT added to the &"lights" group
	var found := pll._collect_lights()
	assert_true(found.has(lamp), "auto_collect discovers an ungrouped Light3D in the running scene (no tagging needed)")
