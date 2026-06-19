@tool
class_name PatrolPath
extends Node3D

## A patrol ROUTE for an NPC: its Node3D / Marker3D CHILDREN are the waypoints, walked in order by a
## PatrolBehavior dropped on the NPC. Drop this in the level, add Marker3D children where you want the guard to
## stop. `loop` = walk a cycle (…->last->first->…); off = ping-pong back and forth. `wait_time` = seconds paused
## at each stop. Pure waypoint data — the PatrolBehavior owns the traversal (so one route can be shared).

## Cycle the route (…->last->first->…). Off = ping-pong (…->last->…->first->…).
@export var loop: bool = true
## Seconds the NPC pauses at each waypoint before moving to the next.
@export var wait_time: float = 1.0

## How many waypoints (Node3D children) the route has.
func get_waypoint_count() -> int:
	var n := 0
	for c in get_children():
		if c is Node3D:
			n += 1
	return n

## The WORLD position of the i-th waypoint (index clamped into range). ZERO when the route has none.
func get_waypoint(index: int) -> Vector3:
	var pts := _points()
	if pts.is_empty():
		return Vector3.ZERO
	return (pts[clampi(index, 0, pts.size() - 1)] as Node3D).global_position

func _points() -> Array:
	var out: Array = []
	for c in get_children():
		if c is Node3D:
			out.append(c)
	return out

func _get_configuration_warnings() -> PackedStringArray:
	if get_waypoint_count() < 1:
		return PackedStringArray(["PatrolPath has no waypoints — add Marker3D children to mark the route."])
	return PackedStringArray()
