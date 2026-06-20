class_name Schedule
extends Resource

## An NPC's daily routine: which place to be in each WorldClock Phase. Author it as a .tres and assign it to a
## ScheduleBehavior under the NPC ("market by day, home by night"). The behavior reads WorldClock.phase() and
## walks the NPC to destination_for(phase) — the first node in that phase's location_group.

@export var entries: Array[ScheduleEntry] = []

## The destination group for `phase` (the FIRST matching entry's location_group), or &"" when the schedule has no
## entry for that phase (the NPC then falls through to its normal idle — patrol / wander). Pure.
func destination_for(phase: int) -> StringName:
	for e in entries:
		if e != null and e.phase == phase and e.location_group != &"":
			return e.location_group
	return &""
