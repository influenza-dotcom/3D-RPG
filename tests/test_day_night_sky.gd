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

func test_sun_elevation_default_window_is_the_original_sinusoid() -> void:
	# The dawn/dusk window generalisation must be BYTE-COMPATIBLE at its defaults — a bare drop-in (and every
	# level authored before the window existed) keeps the exact -cos(TAU*t) arc.
	for i in range(0, 25):
		var t := float(i) / 24.0
		assert_almost_eq(DayNightSky.sun_elevation(t), -cos(TAU * t), 0.0001,
			"default 0.25/0.75 window == the original -cos sinusoid at t=%s" % t)

func test_sun_elevation_authored_window_moves_the_horizon_crossings() -> void:
	# The 2026-08-26 "way too dark by 4-5pm" fix: the main level authors dusk_time 0.8333 (8pm), so the sun
	# must still be up through the late afternoon and set at the AUTHORED dusk, not the old hard-coded 6pm.
	assert_gt(DayNightSky.sun_elevation(0.7083, 0.25, 0.8333), 0.0, "5pm is daytime with an 8pm dusk")
	assert_gt(DayNightSky.sun_elevation(0.8, 0.25, 0.8333), 0.0, "7:12pm is still daytime")
	assert_almost_eq(DayNightSky.sun_elevation(0.8333, 0.25, 0.8333), 0.0, 0.001,
		"sunset lands exactly on the authored dusk")
	assert_lt(DayNightSky.sun_elevation(0.9, 0.25, 0.8333), 0.0, "9:36pm is night")
	assert_almost_eq(DayNightSky.sun_elevation(0.25, 0.25, 0.8333), 0.0, 0.001, "dawn still crosses at 6am")

func test_day_factor_plateaus_at_full_brightness_through_the_afternoon() -> void:
	# full_brightness_elevation saturates the day factor: the afternoon holds FULL authored light instead of
	# sagging with the raw sine (which had 4pm at half energy — the complaint this shape exists to fix).
	assert_almost_eq(DayNightSky.day_factor(0.6667, null, 0.25, 0.8333, 0.35), 1.0, 0.001,
		"4pm is full daylight")
	assert_almost_eq(DayNightSky.day_factor(0.75, null, 0.25, 0.8333, 0.35), 1.0, 0.001,
		"6pm is still full daylight")
	assert_between(DayNightSky.day_factor(0.8, null, 0.25, 0.8333, 0.35), 0.05, 0.95,
		"7:12pm sits inside the dusk fade — the twilight band is where the whole fade now lives")
	assert_eq(DayNightSky.day_factor(0.85, null, 0.25, 0.8333, 0.35), 0.0,
		"past sunset the sun term is fully off (day > 0 ⇔ elev > 0 must survive the window knobs)")

func test_full_brightness_elevation_cannot_dim_the_authored_noon() -> void:
	# The knob may only WIDEN full brightness, never shrink it: a value > 1 would make day_factor < 1 at noon
	# and quietly break the "bare drop-in keeps the authored noon" contract — so it clamps to 1.0 live.
	assert_almost_eq(DayNightSky.day_factor(0.5, null, 0.25, 0.75, 5.0), 1.0, 0.001,
		"an over-1 saturation clamps: noon stays authored-full")

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

func test_arc_orientation_hands_back_to_the_authored_rake_at_night() -> void:
	# The bug this pins: below the horizon -elev flips sign, so the raw arc pitch turns POSITIVE — at midnight
	# the "moon" shone UP from underground (probe-measured +58°) and the street lost every edge the moon keeps.
	var authored := Quaternion.from_euler(Vector3(deg_to_rad(-17.0), 0.0, 0.0))  # the main level's down-rake
	var arc_midnight := Quaternion.from_euler(Vector3(deg_to_rad(58.0), deg_to_rad(-25.0), 0.0))
	assert_almost_eq(DayNightSky.key_light_quat_for(arc_midnight, authored, 1.0).angle_to(authored), 0.0, 0.001,
		"deep night = the authored rake verbatim — the arc must never shine up from under the world")
	var arc_noon := Quaternion.from_euler(Vector3(deg_to_rad(-58.0), deg_to_rad(35.0), 0.0))
	assert_almost_eq(DayNightSky.key_light_quat_for(arc_noon, authored, 0.0).angle_to(arc_noon), 0.0, 0.001,
		"full day = the arc verbatim — noon keeps the driven sun angle untouched")
	# Mid-handover happens only while the arc is still above the horizon (lead leaves 0 only when day < 0.25,
	# i.e. elev > 0), so both blend ends aim down — the halfway light must still shine DOWNWARD.
	var arc_dusk := Quaternion.from_euler(Vector3(deg_to_rad(-0.125 * 58.0), deg_to_rad(60.0), 0.0))
	var mid := DayNightSky.key_light_quat_for(arc_dusk, authored, 0.5)
	assert_lt((Basis(mid) * Vector3.FORWARD).y, 0.0,
		"halfway through the dusk handover the key light still points down at the street")
