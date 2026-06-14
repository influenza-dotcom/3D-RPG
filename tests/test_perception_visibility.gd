extends GutTest

## Perception.visibility_factor -- the pure distance/angle detection-falloff scalar (stealth Slice 2). Unset
## curves -> 1.0 (the default, behaviour-preserving); authored curves scale the DETECTING meter fill, floored at
## min_visibility so a real sighting still reaches ALERTED. Pure: build a Perception off-tree, assign Curves,
## assert the factor. Assertions use endpoints + monotonicity + relative comparisons (robust to the Curve's
## interpolation mode -- only the X=0/X=1 sample values are exact).

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
