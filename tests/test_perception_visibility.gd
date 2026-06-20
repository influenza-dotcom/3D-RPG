extends GutTest

## Perception.visibility_factor -- the pure distance/angle detection-falloff scalar (stealth Slice 2). Unset
## curves -> 1.0 (the default, behaviour-preserving); authored curves scale the DETECTING meter fill, floored at
## min_visibility so a real sighting still reaches ALERTED. Pure: build a Perception off-tree, assign Curves,
## assert the factor. Assertions use endpoints + monotonicity + relative comparisons (robust to the Curve's
## interpolation mode -- only the X=0/X=1 sample values are exact).

## A Node3D target exposing `light_exposure` for _target_light_factor's duck-typed read (Node3D so it assigns to
## Perception.target, which is typed Node3D; the read touches no transform, so off-tree is fine).
class _LitTarget:
	extends Node3D
	var light_exposure: float = 1.0

func _perc() -> Perception:
	return Perception.new()

## A Curve from (0 -> y0) to (1 -> y1).
func _ramp(y0: float, y1: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, y0))
	c.add_point(Vector2(1.0, y1))
	return c

func test_no_curves_is_full_visibility() -> void:
	var p := _perc()
	assert_almost_eq(p.visibility_factor(0.0, 0.0), 1.0, 0.0001, "no curves -> 1.0 (behaviour-preserving)")
	assert_almost_eq(p.visibility_factor(1.0, 1.0), 1.0, 0.0001, "no curves -> 1.0 at the far edge too")
	p.free()

func test_range_falloff_endpoints_and_monotonic() -> void:
	var p := _perc()
	p.range_falloff = _ramp(1.0, 0.0)  # full up close, 0 at max range
	p.min_visibility = 0.0
	assert_almost_eq(p.visibility_factor(0.0, 0.0), 1.0, 0.01, "point-blank -> full fill rate")
	assert_almost_eq(p.visibility_factor(1.0, 0.0), 0.0, 0.01, "max range -> 0 (no floor)")
	assert_gt(p.visibility_factor(0.3, 0.0), p.visibility_factor(0.7, 0.0), "closer fills faster (monotonic)")
	p.free()

func test_floor_clamps_low_visibility() -> void:
	var p := _perc()
	p.range_falloff = _ramp(1.0, 0.0)
	p.min_visibility = 0.2
	assert_almost_eq(p.visibility_factor(1.0, 0.0), 0.2, 0.0001, "at max range the factor floors at min_visibility, not 0")
	assert_lt(p.visibility_factor(1.0, 0.0), p.visibility_factor(0.0, 0.0), "still well below point-blank")
	p.free()

func test_range_and_peripheral_combine() -> void:
	var p := _perc()
	p.range_falloff = _ramp(1.0, 0.0)
	p.peripheral_falloff = _ramp(1.0, 0.0)
	p.min_visibility = 0.0
	assert_almost_eq(p.visibility_factor(0.0, 0.0), 1.0, 0.01, "close + centred -> full")
	assert_almost_eq(p.visibility_factor(1.0, 1.0), 0.0, 0.01, "far + cone-edge -> 0")
	assert_lt(p.visibility_factor(0.5, 0.5), p.visibility_factor(0.5, 0.0), "off-centre lowers it further than distance alone")
	p.free()

func test_light_factor_scales_and_floors() -> void:
	var p := _perc()
	p.min_visibility = 0.1
	# No range/peripheral curves -> visibility_factor is just the (floored) light factor.
	assert_almost_eq(p.visibility_factor(0.0, 0.0, 1.0), 1.0, 0.0001, "fully lit -> full visibility")
	assert_almost_eq(p.visibility_factor(0.0, 0.0, 0.4), 0.4, 0.0001, "dimmer -> proportionally slower fill")
	assert_almost_eq(p.visibility_factor(0.0, 0.0, 0.02), 0.1, 0.0001, "near-dark floors at min_visibility")
	assert_almost_eq(p.visibility_factor(0.0, 0.0), 1.0, 0.0001, "light_factor defaults 1.0 -> Slice-2 calls unchanged")
	p.free()

func test_light_combines_with_range_falloff() -> void:
	var p := _perc()
	p.range_falloff = _ramp(1.0, 0.0)  # range factor 1.0 at dist 0
	p.min_visibility = 0.0
	assert_almost_eq(p.visibility_factor(0.0, 0.0, 0.5), 0.5, 0.01, "range(1.0) * light(0.5) -> 0.5")
	p.free()

func test_target_light_factor_reads_exposure_through_curve() -> void:
	var p := _perc()
	assert_almost_eq(p._target_light_factor(), 1.0, 0.0001, "no light_falloff -> 1.0 (light is opt-in)")
	p.light_falloff = _ramp(0.2, 1.0)  # dark(0) -> 0.2, lit(1) -> 1.0
	var t := _LitTarget.new()
	p.target = t
	t.light_exposure = 0.0
	assert_almost_eq(p._target_light_factor(), 0.2, 0.01, "pitch-dark target -> the curve's dark end")
	t.light_exposure = 1.0
	assert_almost_eq(p._target_light_factor(), 1.0, 0.01, "fully lit target -> the curve's lit end")
	t.free()
	p.free()

## Rank 27.2: with no per-NPC light_falloff, the effective curve is the global GameSettings.light_stealth one;
## a per-NPC curve overrides it. (Tests the selection, not the global curve's user-tunable values.)
func test_effective_light_falloff_prefers_local_then_global() -> void:
	var p := _perc()
	assert_eq(p._effective_light_falloff(), GameSettings.light_stealth.falloff(),
		"a null per-NPC curve falls back to the global light_stealth curve")
	var local := _ramp(0.3, 1.0)
	p.light_falloff = local
	assert_eq(p._effective_light_falloff(), local, "a per-NPC curve overrides the global one")
	p.free()
