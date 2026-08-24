extends GutTest

## THE CARRIED-LIGHT PENALTY — what walking around with your flashlight on actually costs you.
##
## ⭐Why this is a SECOND field and not more light_exposure: the light meter SATURATES. `light_exposure` clamps at
## 1.0, which is also what standing under a streetlamp reads, and `Perception.visibility_factor` clamps its result
## at 1.0 too — so the meter can only ever CANCEL the darkness discount, never push a target past baseline. A torch
## that merely cancels a discount is free. `player.carried_light` (stamped by PlayerLightLevel from the
## &"carried_light" group) is the half that can charge for it: a wider enemy sight range + a faster detection fill.
##
## Layers pinned here: the sampler's pure reveal math, the two global multipliers, Perception's duck-typed read and
## its range/rate composition, and the group scan itself (in-tree, since it needs get_tree()).

## A stand-in player carrying the two duck-typed fields Perception reads off a target (Node3D so it assigns to
## Perception.target, which is typed Node3D; the reads touch no transform, so off-tree is fine).
class _Carrier:
	extends Node3D
	var carried_light: float = 0.0
	var light_exposure: float = 1.0
	var crouch: Node = null   ## the crouch component Perception reads duck-typed; null = standing

## A stand-in crouch component — Perception reads `target.crouch.crouch_t` duck-typed for the crouch discount.
class _CrouchStub:
	extends Node
	var crouch_t: float = 0.0

## The two global dials live on a PRELOADED, shared .tres (GameSettings.light_stealth), so an integration test that
## sets them would leak its tuning into every later test in the run. Save/restore around each one instead — that
## also lets these tests assert exact numbers without being coupled to whatever the shipped tuning currently is.
var _saved_sight: float = 0.0
var _saved_detect: float = 0.0

func before_each() -> void:
	_saved_sight = GameSettings.light_stealth.carried_light_sight_mult
	_saved_detect = GameSettings.light_stealth.carried_light_detect_mult

func after_each() -> void:
	GameSettings.light_stealth.carried_light_sight_mult = _saved_sight
	GameSettings.light_stealth.carried_light_detect_mult = _saved_detect


# --- The sampler's pure math -----------------------------------------------------------------------------------

func test_carried_reveal_is_flat_inside_the_radius_and_zero_outside() -> void:
	# Deliberately NOT distance-faded inside the radius: a torch on your belt gives you away as much as one held
	# out, and a soft edge would make the penalty unreadable. The radius is only the "is it still on me" test.
	assert_almost_eq(PlayerLightLevel.carried_reveal(1.0, 0.0, 3.0, 1.0), 1.0, 0.0001, "at the host -> full reveal")
	assert_almost_eq(PlayerLightLevel.carried_reveal(1.0, 2.9, 3.0, 1.0), 1.0, 0.0001, "still on you near the edge -> full reveal, not faded")
	assert_almost_eq(PlayerLightLevel.carried_reveal(1.0, 3.1, 3.0, 1.0), 0.0, 0.0001, "past the radius it is scenery, not carried -> 0")

func test_carried_reveal_scales_with_energy_and_guards_degenerate_config() -> void:
	assert_almost_eq(PlayerLightLevel.carried_reveal(0.4, 0.0, 3.0, 1.0), 0.4, 0.0001, "a dim candle is a smaller liability than a torch")
	assert_almost_eq(PlayerLightLevel.carried_reveal(3.5, 0.0, 3.0, 1.0), 1.0, 0.0001, "brighter than full_energy still clamps to 1")
	assert_almost_eq(PlayerLightLevel.carried_reveal(0.0, 0.0, 3.0, 1.0), 0.0, 0.0001, "a doused lamp (CrouchLightDouse -> energy 0) reveals nothing")
	assert_almost_eq(PlayerLightLevel.carried_reveal(1.0, 0.0, 0.0, 1.0), 0.0, 0.0001, "radius 0 disables the whole penalty")
	assert_almost_eq(PlayerLightLevel.carried_reveal(1.0, 0.0, 3.0, 0.0), 0.0, 0.0001, "full_energy 0 -> no divide-by-zero, no penalty")


# --- The global dials ------------------------------------------------------------------------------------------

func test_multipliers_are_exactly_neutral_when_carrying_nothing() -> void:
	# The whole feature has to vanish for a target with no lamp — that is every NPC and every torch-off player.
	var s := LightStealthSettings.new()
	assert_almost_eq(s.carried_sight_mult(0.0), 1.0, 0.0001, "carrying nothing -> today's sight range exactly")
	assert_almost_eq(s.carried_detect_mult(0.0), 1.0, 0.0001, "carrying nothing -> today's fill rate exactly")
	s = null

func test_multipliers_lerp_by_strength_and_clamp_it() -> void:
	var s := LightStealthSettings.new()
	s.carried_light_sight_mult = 2.0
	s.carried_light_detect_mult = 3.0
	assert_almost_eq(s.carried_sight_mult(0.5), 1.5, 0.0001, "a half-strength lamp costs half the range penalty")
	assert_almost_eq(s.carried_detect_mult(0.5), 2.0, 0.0001, "...and half the fill penalty")
	assert_almost_eq(s.carried_sight_mult(4.0), 2.0, 0.0001, "an out-of-range strength clamps to the full penalty")
	assert_almost_eq(s.carried_detect_mult(-1.0), 1.0, 0.0001, "a negative strength clamps to neutral")
	s = null

func test_the_shipped_tuning_actually_penalises() -> void:
	# This pillar ships LIVE, not inert — the point of it is that a flashlight costs something out of the box.
	# If someone tunes it back to 1.0/1.0 the torch is free again, and that should be a deliberate, visible choice.
	assert_gt(GameSettings.light_stealth.carried_light_sight_mult, 1.0,
			"the shipped tuning must widen enemy sight range while your torch is lit")
	assert_gt(GameSettings.light_stealth.carried_light_detect_mult, 1.0,
			"the shipped tuning must speed the detection meter up while your torch is lit")


# --- Perception's read + composition ---------------------------------------------------------------------------

func test_perception_reads_carried_light_duck_typed_with_a_safe_fallback() -> void:
	var p := Perception.new()
	assert_almost_eq(p._target_carried_light(), 0.0, 0.0001, "no target -> no penalty")
	var plain := Node3D.new()
	p.target = plain
	assert_almost_eq(p._target_carried_light(), 0.0, 0.0001,
			"a target without the field (every NPC) -> no penalty, the neutral fallback")
	var carrier := _Carrier.new()
	carrier.carried_light = 0.75
	p.target = carrier
	assert_almost_eq(p._target_carried_light(), 0.75, 0.0001, "a carrying target reports its strength")
	carrier.carried_light = 9.0
	assert_almost_eq(p._target_carried_light(), 1.0, 0.0001, "a nonsense value clamps into 0..1")
	plain.free()
	carrier.free()
	p.free()

func test_a_lit_torch_gets_you_spotted_further_away() -> void:
	GameSettings.light_stealth.carried_light_sight_mult = 2.0
	var p := Perception.new()
	p.sight_range = 25.0
	var carrier := _Carrier.new()
	p.target = carrier
	assert_almost_eq(p._effective_sight_range(), 25.0, 0.0001, "torch off -> the plain authored sight range")
	carrier.carried_light = 1.0
	assert_almost_eq(p._effective_sight_range(), 50.0, 0.0001, "torch on -> enemies spot you from twice as far")
	carrier.free()
	p.free()

func test_crouching_no_longer_hides_you_once_the_torch_is_on() -> void:
	# The two factors MULTIPLY, which is the design: crouching still helps a little, but a lit lamp eats most of
	# the discount. "Sneaking with your torch on is barely sneaking" is the decision this feature exists to force.
	GameSettings.light_stealth.carried_light_sight_mult = 1.6
	var p := Perception.new()
	p.sight_range = 25.0
	p.crouch_sight_mult = 0.5
	var carrier := _Carrier.new()
	var crouch := _CrouchStub.new()
	crouch.crouch_t = 1.0
	carrier.crouch = crouch
	p.target = carrier
	var crouched_dark := p._effective_sight_range()
	assert_almost_eq(crouched_dark, 12.5, 0.0001, "crouched with no lamp -> the unchanged crouch discount")
	carrier.carried_light = 1.0
	var crouched_lit := p._effective_sight_range()
	assert_almost_eq(crouched_lit, 20.0, 0.0001, "crouched WITH the torch -> the discount is mostly eaten")
	assert_gt(crouched_lit, crouched_dark, "a crouching player with a lit torch is spotted further off than one without")
	assert_lt(crouched_lit, 25.0, "...but crouching still buys something, so the two axes stay worth stacking")
	crouch.free()
	carrier.free()
	p.free()

func test_a_lit_torch_fills_the_detection_meter_faster() -> void:
	GameSettings.light_stealth.carried_light_detect_mult = 3.0
	var p := Perception.new()
	var carrier := _Carrier.new()
	p.target = carrier
	assert_almost_eq(p._carried_light_detect_mult(), 1.0, 0.0001, "torch off -> the meter fills at today's rate")
	carrier.carried_light = 1.0
	assert_almost_eq(p._carried_light_detect_mult(), 3.0, 0.0001, "torch on -> they lock on three times as fast")
	carrier.free()
	p.free()

func test_an_npc_target_is_completely_unaffected() -> void:
	# The regression that matters most: this must not quietly retune NPC-vs-NPC combat or a torch-less player.
	GameSettings.light_stealth.carried_light_sight_mult = 4.0
	GameSettings.light_stealth.carried_light_detect_mult = 8.0
	var p := Perception.new()
	p.sight_range = 25.0
	var npc_target := Node3D.new()
	p.target = npc_target
	assert_almost_eq(p._effective_sight_range(), 25.0, 0.0001, "a target with no carried_light field sees no range change")
	assert_almost_eq(p._carried_light_detect_mult(), 1.0, 0.0001, "...and no fill change, however the dials are set")
	npc_target.free()
	p.free()


# --- The group scan (in-tree: it needs get_tree()) --------------------------------------------------------------

func test_sampler_stamps_the_strongest_lamp_in_the_group() -> void:
	var host := _Carrier.new()
	add_child_autofree(host)
	var pll := PlayerLightLevel.new()
	pll.host = host
	host.add_child(pll)
	var torch := SpotLight3D.new()
	torch.light_energy = 3.5          # the flashlight's authored energy — well past carried_light_full_energy
	torch.add_to_group(Groups.CARRIED_LIGHT)
	add_child_autofree(torch)
	assert_almost_eq(pll._sample_carried(), 1.0, 0.0001,
			"a lit lamp in the &\"carried_light\" group at the host -> full reveal strength")

func test_switching_the_torch_off_costs_nothing() -> void:
	# The off switch IS the whole verb, and it works with no extra bookkeeping: flash_light.gd already drives
	# `visible` off the toggle (and off being alive), and the sampler skips invisible lamps.
	var host := _Carrier.new()
	add_child_autofree(host)
	var pll := PlayerLightLevel.new()
	pll.host = host
	host.add_child(pll)
	var torch := SpotLight3D.new()
	torch.light_energy = 3.5
	torch.visible = false
	torch.add_to_group(Groups.CARRIED_LIGHT)
	add_child_autofree(torch)
	assert_almost_eq(pll._sample_carried(), 0.0, 0.0001, "an invisible (switched-off) lamp reveals nothing")

func test_a_lamp_you_walked_away_from_stops_revealing_you() -> void:
	var host := _Carrier.new()
	add_child_autofree(host)
	var pll := PlayerLightLevel.new()
	pll.host = host
	pll.carried_light_radius = 3.0
	host.add_child(pll)
	host.global_position = Vector3.ZERO
	var lantern := OmniLight3D.new()
	lantern.light_energy = 3.5
	lantern.add_to_group(Groups.CARRIED_LIGHT)
	add_child_autofree(lantern)
	lantern.global_position = Vector3(0.0, 0.0, 12.0)
	assert_almost_eq(pll._sample_carried(), 0.0, 0.0001,
			"a lit lantern you dropped and walked away from is scenery again (it still feeds the light meter)")
