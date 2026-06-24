extends GutTest

## DayNightSky pure sun math (sun_elevation / day_factor). The in-tree visual driving (sun arc / colour / ambient)
## is playtest-gated; here we pin the curve logic off-tree via the static helpers.

func test_sun_elevation_key_times() -> void:
	assert_almost_eq(DayNightSky.sun_elevation(0.0), -1.0, 0.001, "midnight: sun below the horizon")
	assert_almost_eq(DayNightSky.sun_elevation(0.25), 0.0, 0.001, "dawn: on the horizon")
	assert_almost_eq(DayNightSky.sun_elevation(0.5), 1.0, 0.001, "noon: overhead")
	assert_almost_eq(DayNightSky.sun_elevation(0.75), 0.0, 0.001, "dusk: on the horizon")
	assert_almost_eq(DayNightSky.sun_elevation(1.0), -1.0, 0.001, "wraps back to midnight")

func test_day_factor_zero_at_night_peak_at_noon() -> void:
	assert_almost_eq(DayNightSky.day_factor(0.5), 1.0, 0.001, "full light at noon")
	assert_eq(DayNightSky.day_factor(0.0), 0.0, "no light at midnight")
	assert_eq(DayNightSky.day_factor(0.1), 0.0, "no light deep in the night (sun below the horizon)")
	assert_gt(DayNightSky.day_factor(0.4), 0.0, "lit through the day")

func test_day_factor_uses_custom_curve_when_given() -> void:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(1.0, 0.3))  # a flat 0.3 curve
	assert_almost_eq(DayNightSky.day_factor(0.5, c), 0.3, 0.01, "a custom energy curve overrides the sinusoid")
	c = null
