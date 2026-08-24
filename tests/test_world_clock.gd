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

## ---------------------------------------------------------------------------------------------------
## ADVANCING THE CLOCK (the Wait feature's engine). advance_by must behave as if the span had been LIVED —
## every day/night boundary it crosses emits, in order — because RentCollector and LedgerAccrual both count
## DAWN crossings. A jump that emitted once (or not at all) is the free-rent exploit, so these are economy
## tests as much as clock tests.

## Collect every phase_changed emitted while advancing a fresh clock from `from_t` by `days`.
func _advance_collecting(from_t: float, days: float) -> Array:
	var c = WorldClockScript.new()
	c.day_start = 0.25
	c.night_start = 0.75
	c.set_time_of_day(from_t)
	var seen: Array = []
	c.phase_changed.connect(func(p: int) -> void: seen.append(p))
	c.advance_by(days)
	var out := {"seen": seen, "t": c.time_of_day, "phase": c.phase()}
	c.free()
	return [out]


func test_advance_lands_on_the_right_time() -> void:
	var r: Dictionary = _advance_collecting(0.5, 0.25)[0]   # noon + 6h
	assert_almost_eq(float(r["t"]), 0.75, 0.0001, "noon + 6h = 18:00")
	r = _advance_collecting(0.9, 0.25)[0]                    # wraps past midnight
	assert_almost_eq(float(r["t"]), 0.15, 0.0001, "21:36 + 6h wraps to 03:36, never past 1.0")


func test_advance_emits_the_boundary_it_crosses() -> void:
	var r: Dictionary = _advance_collecting(0.5, 0.25)[0]   # noon -> dusk exactly
	assert_eq((r["seen"] as Array).size(), 1, "noon to dusk crosses exactly one boundary")
	assert_eq((r["seen"] as Array)[0], 0, "...and that boundary is DUSK (-> NIGHT)")


func test_advance_a_full_day_crosses_both_boundaries_once_each() -> void:
	var r: Dictionary = _advance_collecting(0.5, 1.0)[0]
	assert_eq(r["seen"], [0, 1], "noon -> noon crosses dusk then DAWN, in that order")
	assert_almost_eq(float(r["t"]), 0.5, 0.0001, "a full day returns to the same hour")


func test_advance_three_days_charges_three_dawns() -> void:
	# THE EXPLOIT TEST. RentCollector counts dawns; if a long wait emitted once, three days of rent would
	# cost one. If it emitted none, waiting would be free forever.
	var r: Dictionary = _advance_collecting(0.5, 3.0)[0]
	var dawns := 0
	for p in (r["seen"] as Array):
		if int(p) == 1:
			dawns += 1
	assert_eq(dawns, 3, "three days lived = three dawns billed")
	assert_eq((r["seen"] as Array).size(), 6, "...and six boundaries total (three dusks interleaved)")


func test_advance_within_one_phase_emits_nothing() -> void:
	var r: Dictionary = _advance_collecting(0.3, 0.1)[0]   # 07:12 -> 09:36, both DAY
	assert_eq((r["seen"] as Array).size(), 0, "a span that crosses no boundary is silent")
	assert_eq(int(r["phase"]), 1, "...and stays DAY")


func test_advance_from_exactly_on_a_boundary_does_not_double_fire() -> void:
	# Standing exactly ON dawn and stepping forward must not re-emit DAWN — delta_to_next_boundary reports a
	# boundary you are standing on as a full turn away, which is also what stops the walk spinning in place.
	var r: Dictionary = _advance_collecting(0.25, 0.1)[0]
	assert_eq((r["seen"] as Array).size(), 0, "leaving dawn crosses nothing")


func test_advance_by_zero_or_negative_is_a_no_op() -> void:
	var r: Dictionary = _advance_collecting(0.5, 0.0)[0]
	assert_almost_eq(float(r["t"]), 0.5, 0.0001, "zero span does not move the clock")
	assert_eq((r["seen"] as Array).size(), 0, "...and emits nothing")
	r = _advance_collecting(0.5, -1.0)[0]
	assert_almost_eq(float(r["t"]), 0.5, 0.0001, "a negative span is clamped to zero, never run backwards")
	assert_eq((r["seen"] as Array).size(), 0, "...and emits nothing")


func test_advance_hours_is_advance_by_in_hours() -> void:
	var c = WorldClockScript.new()
	c.day_start = 0.25
	c.night_start = 0.75
	c.set_time_of_day(0.0)
	c.advance_hours(6.0)
	assert_almost_eq(c.time_of_day, 0.25, 0.0001, "midnight + 6h = 06:00")
	c.free()


func test_set_time_of_day_stays_silent() -> void:
	# The other half of the contract: SEEKING (a save restore) must never bill anyone. If this ever starts
	# emitting, loading a save charges rent.
	var c = WorldClockScript.new()
	c.day_start = 0.25
	c.night_start = 0.75
	c.set_time_of_day(0.5)
	var seen: Array = []
	c.phase_changed.connect(func(p: int) -> void: seen.append(p))
	c.set_time_of_day(0.0)   # noon -> midnight, a DAY->NIGHT change
	assert_eq(seen.size(), 0, "seeking the clock emits nothing, however far it jumps")
	assert_eq(c.phase(), 0, "...but the cached phase is still corrected immediately")
	c.free()


func test_delta_to_next_boundary_is_always_positive() -> void:
	assert_almost_eq(WorldClockScript.delta_to_next_boundary(0.0, 0.25, 0.75), 0.25, 0.0001, "midnight -> dawn")
	assert_almost_eq(WorldClockScript.delta_to_next_boundary(0.5, 0.25, 0.75), 0.25, 0.0001, "noon -> dusk")
	assert_almost_eq(WorldClockScript.delta_to_next_boundary(0.25, 0.25, 0.75), 0.5, 0.0001,
			"standing ON dawn reports DUSK next, not 0 — a zero step would spin advance_by forever")
	assert_gt(WorldClockScript.delta_to_next_boundary(0.4, 0.4, 0.4), 0.0,
			"a degenerate clock whose boundaries coincide still returns a positive step, so the walk terminates")


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
