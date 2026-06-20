extends GutTest

## Rank 27.4 (LightStealthSettings): the global light-falloff curve GameSettings.light_stealth exposes — a
## built-in dark->lit ramp by default, so painting a ShadowVolume slows detection game-wide with no per-NPC curve.

func test_registered_on_game_settings() -> void:
	assert_not_null(GameSettings.light_stealth, "light_stealth is registered on GameSettings")

func test_default_curve_is_a_dark_to_lit_ramp() -> void:
	var s := LightStealthSettings.new()
	var c := s.falloff()
	assert_not_null(c, "falloff() always returns a curve (built-in default)")
	assert_lt(c.sample(0.0), c.sample(1.0), "pitch dark is less visible than fully lit")
	assert_almost_eq(c.sample(1.0), 1.0, 0.001, "fully lit -> full visibility")
	s = null

func test_authored_curve_overrides_default() -> void:
	var s := LightStealthSettings.new()
	var custom := Curve.new()
	custom.add_point(Vector2(0.0, 0.5))
	custom.add_point(Vector2(1.0, 0.9))
	s.light_falloff = custom
	assert_eq(s.falloff(), custom, "an authored curve overrides the built-in ramp")
	s = null
