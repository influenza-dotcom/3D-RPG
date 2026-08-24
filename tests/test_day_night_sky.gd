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

func test_sun_energy_zero_peak_defers_to_the_authored_energy() -> void:
	assert_almost_eq(DayNightSky.sun_energy_for(1.0, 0.0, 2.026), 2.026, 0.001,
		"peak 0 = the authored-anchor contract: a bare drop-in keeps the level's authored noon sun")
	assert_almost_eq(DayNightSky.sun_energy_for(0.5, 0.0, 2.026), 1.013, 0.001,
		"the day factor scales the authored peak")
	assert_almost_eq(DayNightSky.sun_energy_for(1.0, 3.0, 2.026), 3.0, 0.001,
		"an explicit peak overrides the authored anchor")
	assert_eq(DayNightSky.sun_energy_for(0.0, 0.0, 2.026), 0.0, "below the horizon the sun is fully off")

func test_ambient_scales_the_authored_energy_never_absolutes() -> void:
	assert_almost_eq(DayNightSky.ambient_energy_for(0.15, 1.0, 1.0, 0.35), 0.15, 0.001,
		"noon at day_scale 1.0 preserves the authored ambient EXACTLY (the main level authors 0.15)")
	assert_almost_eq(DayNightSky.ambient_energy_for(0.15, 0.0, 1.0, 0.35), 0.0525, 0.001,
		"deep night is the authored ambient times the night scale — a fraction, never an absolute write")
	assert_almost_eq(DayNightSky.ambient_energy_for(0.15, 0.5, 1.0, 0.35), 0.10125, 0.001,
		"half-day lerps between the night and day fractions")
	assert_eq(DayNightSky.ambient_energy_for(-1.0, 1.0, 1.0, 0.35), 0.0,
		"a negative authored energy floors to 0 instead of going darker-than-black")

func test_fog_scale_full_when_grazing_reduced_overhead() -> void:
	assert_almost_eq(DayNightSky.fog_energy_scale_for(0.0, 0.25), 1.0, 0.001,
		"a grazing sun keeps the authored volumetric fog energy — the regime it was tuned in")
	assert_almost_eq(DayNightSky.fog_energy_scale_for(1.0, 0.25), 0.25, 0.001,
		"an overhead sun scales fog energy down — the noon white-out guard (probe-verified washout)")
	assert_almost_eq(DayNightSky.fog_energy_scale_for(-1.0, 0.25), 1.0, 0.001,
		"below the horizon clamps to the grazing scale (the sun is off anyway)")
	assert_almost_eq(DayNightSky.fog_energy_scale_for(1.0, 1.0), 1.0, 0.001, "high_scale 1.0 = the guard is off")

func test_moon_leads_only_once_the_sun_is_down() -> void:
	assert_eq(DayNightSky.moon_lead_for(1.0), 0.0, "at high noon the moon contributes nothing")
	assert_eq(DayNightSky.moon_lead_for(0.25), 0.0, "still full sun a quarter down — no moon yet")
	assert_almost_eq(DayNightSky.moon_lead_for(0.125), 0.5, 0.001, "the handover runs through the dusk fade")
	assert_eq(DayNightSky.moon_lead_for(0.0), 1.0, "below the horizon the moon is the whole key light")

func test_key_light_never_dips_through_a_dark_seam_at_dusk() -> void:
	# The reason this is a max() and not a lerp: at the crossover the sun term is falling while the moon term is
	# rising, and a lerp between them passes through a value lower than BOTH — a visible dip at dusk every day.
	var moon := 0.405   # the shipped 0.2 scale x the main level's authored 2.026
	var worst := 999.0
	for i in range(0, 101):
		var day := float(i) / 100.0
		var e := DayNightSky.key_light_energy_for(DayNightSky.sun_energy_for(day, 0.0, 2.026), moon, DayNightSky.moon_lead_for(day))
		worst = minf(worst, e)
	assert_gt(worst, 0.0,
		"the key light must never reach zero anywhere in the day (that is the pitch-black midnight bug)")
	assert_almost_eq(DayNightSky.key_light_energy_for(2.026, moon, 0.0), 2.026, 0.001,
		"full day = the authored sun energy, untouched by the moon")
	assert_almost_eq(DayNightSky.key_light_energy_for(0.0, moon, 1.0), moon, 0.001,
		"deep night = the moon alone")

func test_moon_can_be_switched_off_for_a_pitch_black_night() -> void:
	assert_eq(DayNightSky.key_light_energy_for(0.0, 0.0, 1.0), 0.0,
		"moon_energy_scale 0 restores the fully-dark night (and with it the fully-hidden stealth night)")
