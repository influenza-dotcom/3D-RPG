extends Node

## WorldClock (autoload): the game's day/night clock. `time_of_day` runs 0..1 (0 = midnight, 0.5 = noon),
## advancing once per `day_length_seconds` of real time. phase_of(t) maps a time to a Phase (DAY / NIGHT) by the
## day/night start fractions; `phase_changed(new_phase)` fires when the live time crosses a boundary. NPC
## Schedules (ScheduleBehavior) read `phase()`; a sky/lighting driver can read `time_of_day`. Pauses with the
## tree. Tunable at runtime (the knobs are plain vars, not consts — a designer/script can speed the cycle).

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
func set_time_of_day(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	_phase = phase_of(time_of_day)
