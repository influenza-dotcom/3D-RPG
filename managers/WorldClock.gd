extends Node

## WorldClock (autoload): the game's day/night clock. `time_of_day` runs 0..1 (0 = midnight, 0.5 = noon),
## advancing once per `day_length_seconds` of real time. phase_of(t) maps a time to a Phase (DAY / NIGHT) by the
## day/night start fractions; `phase_changed(new_phase)` fires when the live time crosses a boundary. NPC
## Schedules (ScheduleBehavior) read `phase()`; a sky/lighting driver can read `time_of_day`. Pauses with the
## tree. Tunable at runtime (the knobs are plain vars, not consts — a designer/script can speed the cycle).
##
## ⭐TWO WAYS TO MOVE THE CLOCK, AND THEY ARE NOT INTERCHANGEABLE: `set_time_of_day()` SEEKS silently (a save
## restore, a debug jump — no subscriber should react to it), while `advance_by()` / `advance_hours()` mean
## TIME PASSED and emit every boundary the span crosses (the player waiting). Picking the wrong one is either
## a phantom dawn on load or free rent forever — see the note on each.

signal phase_changed(new_phase: int)

enum Phase { NIGHT, DAY }

## Real seconds for one full in-game day (0 = clock frozen).
var day_length_seconds: float = 600.0
## time_of_day fractions where DAY begins (dawn) and NIGHT begins (dusk). DAY is the half-open [day_start, night_start).
var day_start: float = 0.25
var night_start: float = 0.75
## Current time of day, 0..1. Starts at noon so a fresh game opens in daylight.
var time_of_day: float = 0.5

var _phase: int = Phase.DAY

func _ready() -> void:
	_phase = phase_of(time_of_day)

func _process(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return
	time_of_day = fposmod(time_of_day + delta / day_length_seconds, 1.0)
	var p := phase_of(time_of_day)
	if p != _phase:
		_phase = p
		phase_changed.emit(p)

## The live phase (cached; updated each _process).
func phase() -> int:
	return _phase

## Pure: the Phase for a given time_of_day fraction — DAY in [day_start, night_start), else NIGHT. Unit-tested.
func phase_of(t: float) -> int:
	var f := fposmod(t, 1.0)
	return Phase.DAY if (f >= day_start and f < night_start) else Phase.NIGHT

## Set the clock directly (a save restore / a cutscene / debug), wrapping to 0..1, and refresh the cached phase so
## phase() is correct immediately. SILENT — it does NOT emit phase_changed: a clock JUMP is a discontinuity, not an
## organic dawn/dusk, so a subscriber (e.g. RentCollector) must NOT fire as a side-effect of loading/seeking the
## clock. The next real _process boundary emits the next genuine transition; schedules poll phase() live each tick.
##
## ⭐SEEKING IS NOT WAITING. To move the clock because TIME PASSED — the player waiting, a cutscene covering a
## night — call advance_by() instead, which walks the span and emits every boundary it crosses. Using this for
## that is the rent/interest exploit: the player would skip dawn after dawn and never be charged.
func set_time_of_day(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	_phase = phase_of(time_of_day)

## Safety valve on advance_by's boundary walk: two boundaries a day, so this bounds one call to ~a year of
## in-game time. A span longer than that finishes as a silent seek rather than hanging the frame.
const MAX_ADVANCE_STEPS := 800

## In-game hours in a day — the unit callers actually think in ("wait 6 hours"), converted here so nothing
## outside this file has to know that `time_of_day` is a 0..1 fraction.
const HOURS_PER_DAY := 24.0

## ⭐TIME ACTUALLY PASSING — the counterpart to the silent seek above. Advances the clock by `days` (a POSITIVE
## span in day-fractions) and emits `phase_changed` ONCE PER BOUNDARY CROSSED, in chronological order, exactly
## as if the span had been lived through frame by frame.
##
## WHY THE WALK RATHER THAN ONE JUMP + ONE EMIT: `RentCollector` and `LedgerAccrual` both count DAWN crossings
## — one charge, one interest posting per crossing. A three-day wait that jumped straight to the destination
## and emitted at most one transition would charge one day's rent for three days lived, and a wait that
## emitted nothing at all (the set_time_of_day path) would let a player skip every dawn forever. Walking
## boundary to boundary is what makes waiting cost what living costs.
##
## Subscribers therefore see several transitions IN ONE FRAME on a long span. That is the contract: a
## dawn handler must be idempotent-per-crossing and must not assume a frame elapses between calls.
func advance_by(days: float) -> void:
	var remaining := maxf(0.0, days)
	if remaining <= 0.0:
		return
	var guard := 0
	while guard < MAX_ADVANCE_STEPS:
		guard += 1
		var step := delta_to_next_boundary(time_of_day, day_start, night_start)
		if step > remaining:
			break                        # the span ends before the next boundary — nothing left to cross
		remaining -= step
		time_of_day = fposmod(time_of_day + step, 1.0)
		var p := phase_of(time_of_day)
		if p != _phase:
			_phase = p
			phase_changed.emit(p)
	# The tail: whatever is left after the last crossing, which by construction crosses nothing.
	time_of_day = fposmod(time_of_day + remaining, 1.0)
	_phase = phase_of(time_of_day)

## advance_by in the unit callers think in. 6.0 -> six in-game hours.
func advance_hours(hours: float) -> void:
	advance_by(maxf(0.0, hours) / HOURS_PER_DAY)

## Pure: the distance forward from `t` to the NEXT day/night boundary, always STRICTLY positive and at most a
## full day. Standing exactly ON a boundary reports the next one a full turn away rather than 0 — that is what
## keeps advance_by's walk making progress instead of spinning on the same instant forever. A degenerate clock
## whose two boundaries coincide still returns a positive step, so the walk terminates there too. Unit-tested.
static func delta_to_next_boundary(t: float, p_day_start: float, p_night_start: float) -> float:
	var here := fposmod(t, 1.0)
	var best := 1.0
	for b: float in [fposmod(p_day_start, 1.0), fposmod(p_night_start, 1.0)]:
		var d := fposmod(b - here, 1.0)
		if d <= 0.0:
			d = 1.0
		if d < best:
			best = d
	return best
