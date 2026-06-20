extends GutTest

## Rank 28a: WorldClock phase mapping (pure) + the autoload registration + Schedule/ScheduleEntry data. The live
## time advance + phase_changed signal are playtest-verified; phase_of + destination_for are unit-tested.
## (WorldClock.Phase: NIGHT = 0, DAY = 1.)

const WorldClockScript = preload("res://managers/WorldClock.gd")

func test_phase_of_day_and_night() -> void:
	var c = WorldClockScript.new()
	c.day_start = 0.25
	c.night_start = 0.75
	assert_eq(c.phase_of(0.5), 1, "noon -> DAY")
	assert_eq(c.phase_of(0.0), 0, "midnight -> NIGHT")
	assert_eq(c.phase_of(0.25), 1, "dawn boundary is DAY (half-open)")
	assert_eq(c.phase_of(0.75), 0, "dusk boundary is NIGHT")
	assert_eq(c.phase_of(0.9), 0, "late evening -> NIGHT")
	assert_eq(c.phase_of(1.25), 1, "wraps: 1.25 == 0.25 -> DAY")
	c.free()

func test_registered_as_autoload() -> void:
	assert_not_null(WorldClock, "WorldClock autoload exists")
	assert_true(WorldClock.has_method("phase"), "WorldClock exposes phase()")

func test_schedule_destination_lookup() -> void:
	var s := Schedule.new()
	var day := ScheduleEntry.new()
	day.phase = 1  # DAY
	day.location_group = &"market"
	var night := ScheduleEntry.new()
	night.phase = 0  # NIGHT
	night.location_group = &"home"
	var entries: Array[ScheduleEntry] = [day, night]
	s.entries = entries
	assert_eq(s.destination_for(1), &"market", "DAY -> market")
	assert_eq(s.destination_for(0), &"home", "NIGHT -> home")
	s = null

func test_schedule_missing_phase_returns_empty() -> void:
	var s := Schedule.new()
	var only_day := ScheduleEntry.new()
	only_day.phase = 1
	only_day.location_group = &"market"
	var entries: Array[ScheduleEntry] = [only_day]
	s.entries = entries
	assert_eq(s.destination_for(0), &"", "no NIGHT entry -> empty (NPC falls through to normal idle)")
	s = null
