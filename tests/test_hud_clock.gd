extends GutTest

## The HUD time-of-day readout (scripts/ui/hud_clock.gd). Everything that turns a WorldClock fraction into a
## clock face is a PURE static, so the whole conversion is pinned off-tree — the DayNightSky.sun_elevation /
## UI.quest_tracker_top_for idiom. The widget itself only wires those statics to a Label.
##
## The cases that matter here are the BOUNDARIES, because they are the ones that produce a face no real clock
## has: an hour of 24, a 12-hour face showing "0:05", or midnight and noon disagreeing about AM/PM.

const CLOCK := preload("res://scripts/ui/hud_clock.gd")


func test_minute_of_day_maps_the_cardinal_times() -> void:
	assert_eq(CLOCK.minute_of_day(0.0), 0, "0.0 is midnight")
	assert_eq(CLOCK.minute_of_day(0.25), 360, "0.25 is 06:00 — WorldClock.day_start, dawn")
	assert_eq(CLOCK.minute_of_day(0.5), 720, "0.5 is noon, the WorldClock's own documented anchor")
	assert_eq(CLOCK.minute_of_day(0.75), 1080, "0.75 is 18:00 — WorldClock.night_start, dusk")


func test_minute_of_day_wraps_like_the_world_clock() -> void:
	# WorldClock.time_of_day is fposmod'd to 0..1, but set_time_of_day and a save restore can hand this
	# function anything; it must land in range rather than producing a negative or 24xx face.
	assert_eq(CLOCK.minute_of_day(1.0), 0, "a full turn is midnight again, never minute 1440")
	assert_eq(CLOCK.minute_of_day(1.5), 720, "past one full day wraps to noon")
	assert_eq(CLOCK.minute_of_day(-0.25), 1080, "a negative fraction wraps forward, not to a negative minute")


func test_minute_of_day_floors_so_the_face_never_reads_twenty_four() -> void:
	# THE ROUNDING TRAP: 23:59:40 is 0.99977 of a day. Rounded to the nearest minute that is 1440 — an hour
	# no clock face has, and one that would print "24:00" for the last ~20 seconds of every single day.
	assert_eq(CLOCK.minute_of_day(0.99977), 1439, "the last minute of the day floors to 23:59, never 1440")
	assert_lt(CLOCK.minute_of_day(0.9999999), CLOCK.MINUTES_PER_DAY,
			"no fraction below 1.0 may produce a minute outside the day")


func test_hour_12_never_shows_a_zero_hour() -> void:
	assert_eq(CLOCK.hour_12(0), 12, "midnight reads 12, not 0 — the whole point of the conversion")
	assert_eq(CLOCK.hour_12(12), 12, "noon reads 12 too")
	assert_eq(CLOCK.hour_12(1), 1, "01:00 reads 1")
	assert_eq(CLOCK.hour_12(13), 1, "13:00 reads 1")
	assert_eq(CLOCK.hour_12(23), 11, "23:00 reads 11")


func test_face_text_24_hour_zero_pads_both_fields() -> void:
	assert_eq(CLOCK.face_text(0, true), "00:00", "midnight pads to four digits")
	assert_eq(CLOCK.face_text(65, true), "01:05", "an early hour pads BOTH fields")
	assert_eq(CLOCK.face_text(720, true), "12:00", "noon")
	assert_eq(CLOCK.face_text(1439, true), "23:59", "the last minute of the day")


func test_face_text_12_hour_selects_the_right_marker() -> void:
	# The half-of-day boundary in both directions: the minute before noon is still AM, the minute of noon is
	# PM, and midnight is AM — the three cases a naive `hour >= 12` on the CONVERTED hour gets wrong.
	assert_eq(CLOCK.face_text(0, false), "12:00 AM", "midnight is 12 AM")
	assert_eq(CLOCK.face_text(719, false), "11:59 AM", "the minute before noon is still AM")
	assert_eq(CLOCK.face_text(720, false), "12:00 PM", "noon itself is 12 PM")
	assert_eq(CLOCK.face_text(1439, false), "11:59 PM", "the last minute of the day is PM")


func test_face_text_12_hour_does_not_pad_the_hour() -> void:
	# The English 12-hour convention, and the reason the two faces are separate templates rather than one
	# with a conditional tail: "02:35 PM" is wrong on a wall clock.
	assert_eq(CLOCK.face_text(125, false), "2:05 AM", "the 12-hour hour is unpadded; the MINUTE still pads")


func test_face_text_wraps_an_out_of_range_minute() -> void:
	assert_eq(CLOCK.face_text(CLOCK.MINUTES_PER_DAY, true), "00:00",
			"minute 1440 is minute 0 — a caller that computed its own minute cannot produce a 24:00 face")


func test_time_text_composes_the_two_pure_steps() -> void:
	assert_eq(CLOCK.time_text(0.5, true), "12:00", "noon in 24-hour")
	assert_eq(CLOCK.time_text(0.5, false), "12:00 PM", "noon in 12-hour")
	assert_eq(CLOCK.time_text(0.0, false), "12:00 AM", "midnight in 12-hour")


func test_face_text_never_produces_an_unsubstituted_token() -> void:
	# TextFormat.subst leaves a MISSING token visible ("{hours}") as a loud authoring bug. Sweeping the whole
	# day in both faces proves every template's tokens are actually fed, which one spot-check cannot.
	for m in range(0, CLOCK.MINUTES_PER_DAY, 7):
		for use_24 in [true, false]:
			var face: String = CLOCK.face_text(m, use_24)
			assert_false(face.contains("{"), "minute %d (24h=%s) left an unsubstituted token: %s" % [m, use_24, face])
			assert_false(face.is_empty(), "minute %d (24h=%s) produced an empty face" % [m, use_24])


func test_every_minute_of_the_day_has_a_distinct_face() -> void:
	# Guards the conversion end-to-end: a bug in the hour split (integer division, a stray floor) collapses
	# distinct minutes onto one face, which a handful of spot-checks would sail straight past.
	var seen := {}
	for m in CLOCK.MINUTES_PER_DAY:
		var face: String = CLOCK.face_text(m, true)
		assert_false(seen.has(face), "24-hour face %s is produced by two different minutes" % face)
		seen[face] = true
	assert_eq(seen.size(), CLOCK.MINUTES_PER_DAY, "all 1440 minutes of the day render a unique 24-hour face")


func test_widget_is_click_through() -> void:
	# Every HUD element in this project is explicitly IGNORE; the Control default would make this line eat
	# clicks in the corner of the screen.
	var clock = CLOCK.new()
	add_child_autofree(clock)
	assert_eq(clock.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the clock must not swallow clicks")


func test_the_clock_has_options_rows() -> void:
	# The rows are DATA (SettingSpecs in SettingsCatalog.tres), not hand-built UI — CLAUDE.md's settings rule,
	# in the tests/test_enemy_health_bar.gd shape.
	var catalog: SettingsCatalog = load("res://resources/settings/SettingsCatalog.tres")
	var want := {
		&"clock": [&"clock_enabled", &"set_clock_enabled"],
		&"clock_24_hour": [&"clock_24_hour", &"set_clock_24_hour"],
	}
	var found := {}
	for spec in catalog.specs:
		if spec != null and want.has(spec.key):
			found[spec.key] = true
			assert_eq(spec.tab, &"Accessibility", "the %s row lives on the Accessibility tab" % spec.key)
			assert_eq(spec.getter, StringName(want[spec.key][0]), "%s is bound to the Settings field" % spec.key)
			assert_eq(spec.setter, StringName(want[spec.key][1]), "%s is bound to the Settings setter" % spec.key)
			assert_false(spec.label.is_empty(), "%s carries a visible label" % spec.key)
	for key in want:
		assert_true(found.has(key),
				"SettingsCatalog.tres must carry a '%s' spec — an Options row is not optional for a player-facing HUD element" % key)


func test_the_face_choice_is_a_bool_not_a_dropdown() -> void:
	# There are exactly two faces, and a generic DROPDOWN spec LOSES its options on an editor .tres re-save
	# (SettingSpec's own @risk, a bug that has recurred). minimap_rotates made the same call for the same reason.
	var catalog: SettingsCatalog = load("res://resources/settings/SettingsCatalog.tres")
	for spec in catalog.specs:
		if spec != null and spec.key == &"clock_24_hour":
			assert_eq(spec.control, SettingSpec.Widget.TOGGLE,
					"the 12/24-hour choice must stay a TOGGLE — a DROPDOWN empties itself on an editor re-save")


func test_hidden_clock_does_no_work() -> void:
	# The "a hidden map costs nothing" contract, one row down: OFF must be a real cost win, not a hidden node
	# still reading the autoload and re-stamping a Label every frame.
	var clock = CLOCK.new()
	add_child_autofree(clock)
	clock.visible = false
	clock._process(0.016)
	assert_eq(clock.text, "", "a hidden clock never stamps its face")
