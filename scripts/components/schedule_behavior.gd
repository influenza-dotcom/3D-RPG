@tool
class_name ScheduleBehavior
extends Node

## Drop under an NPC to make it follow a daily ROUTINE instead of idling/wandering: it reads the WorldClock phase
## and walks the NPC to the marker for that phase ("market by day, home by night"). Point `schedule` at a Schedule
## resource and drop a Marker3D into each phase's location_group. While the NPC has no target and isn't in combat,
## its idle locomotion hands movement here — ABOVE patrol/wander, BELOW companion-follow — so a fight interrupts
## it and it resumes after. Inert (falls through to normal idle) without a schedule, or when the current phase has
## no entry / no marker placed. Mirrors PatrolBehavior.
##
## `host` is typed Node (a dynamic call surface), NOT NPC, to keep the NPC <-> component class-cycle broken.

## Off = ignore the schedule and fall back to normal idle (patrol / wander / hold).
@export var enabled: bool = true
## The daily routine: which WorldClock phase -> which destination group.
@export var schedule: Schedule
## How close (m) counts as "arrived" — within this the NPC holds at the spot instead of nudging it forever.
@export var arrive_distance: float = 1.5

var _host: Node = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_host = get_parent()

## True when this should drive idle movement: enabled, with a schedule whose CURRENT-phase destination marker
## exists in the world. Otherwise the NPC falls through to patrol / wander.
func is_active() -> bool:
	return enabled and _destination() != null

## One schedule step (called each idle frame by the host's NpcLocomotion._idle): walk toward the current phase's
## destination marker via the NPC's own navmesh pathing; hold once within arrive_distance.
func act(delta: float) -> void:
	if _host == null:
		_host = get_parent()
	var dest := _destination()
	if _host == null or dest == null:
		return
	var target := dest.global_position
	if _host.global_position.distance_to(target) <= arrive_distance:
		return  # arrived — stand at the spot
	if _host._move_toward(target):
		_host._face_travel(delta)

## The destination Node3D for the live WorldClock phase (the first node in that phase's location_group), or null
## when the schedule has no entry for the phase / no marker is placed. Null = fall through to normal idle.
func _destination() -> Node3D:
	if schedule == null or not is_inside_tree():
		return null
	var grp := schedule.destination_for(WorldClock.phase())
	if grp == &"":
		return null
	for n in get_tree().get_nodes_in_group(grp):
		if n is Node3D:
			return n as Node3D
	return null

func _get_configuration_warnings() -> PackedStringArray:
	var p := get_parent()
	if p == null or not p.has_method(&"_move_toward"):
		return PackedStringArray(["ScheduleBehavior must be a child of an NPC (it drives that NPC's idle movement)."])
	if schedule == null:
		return PackedStringArray(["ScheduleBehavior has no `schedule` assigned — the NPC will fall back to patrol/wander."])
	return PackedStringArray()
