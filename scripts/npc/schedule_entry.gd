@tool
class_name ScheduleEntry
extends Resource

## One line of a Schedule: in WorldClock phase `phase`, the NPC heads to the first node in `location_group`
## (drop a Marker3D into that group — e.g. &"market", &"home"). The phase ints match WorldClock.Phase (0 = Night,
## 1 = Day), exposed as a dropdown so a designer never types a raw number.

@export_enum("Night", "Day") var phase: int = 1  ## matches WorldClock.Phase (Night = 0, Day = 1)
@export var location_group: StringName = &""      ## a group holding the destination marker for this phase
