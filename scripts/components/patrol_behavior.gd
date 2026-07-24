@tool
class_name PatrolBehavior
extends Node

## Drop under an NPC to make it WALK A FIXED ROUTE instead of random wander while idle. Point `patrol_path` at a
## PatrolPath (a node with Marker3D/Node3D waypoint children). When the NPC has no target and isn't in combat,
## its idle locomotion hands movement to this component, which walks the route — pausing PatrolPath.wait_time at
## each stop — and yields to combat automatically (the host only runs it while idle, so a fight interrupts the
## patrol and it resumes afterward). Reuses the NPC's own navmesh pathing + move/turn speed, so the route steers
## around walls exactly like wander does.
##
## `host` is typed Node (a dynamic call surface), NOT NPC, to keep the NPC <-> component class-cycle broken — the
## same discipline NpcLocomotion follows. NpcLocomotion._idle finds + drives this (npc.gd is untouched).

## Off = this NPC ignores the route and falls back to its normal wander/hold idle.
@export var enabled: bool = true
## The PatrolPath whose waypoint children this NPC walks, in order.
@export var patrol_path: NodePath

var _host: Node = null      ## the NPC (dynamic call surface) — its parent
var _index: int = 0         ## current waypoint
var _dir: int = 1           ## ping-pong direction (used only when the path doesn't loop)
var _waiting: float = 0.0   ## seconds left paused at the current waypoint

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_host = get_parent()

## True when this should drive the NPC's idle movement: enabled, with a path that has at least one waypoint.
func is_active() -> bool:
	if not enabled:
		return false
	var p := _path()
	return p != null and p.get_waypoint_count() > 0

## One patrol step, called each idle frame by the host's NpcLocomotion._idle. Walks toward the current waypoint
## via the NPC's own pathing; on arrival it pauses wait_time, then advances to the next waypoint.
func act(delta: float) -> void:
	if _host == null:
		_host = get_parent()
	var p := _path()
	if _host == null or p == null or p.get_waypoint_count() == 0:
		return
	if _waiting > 0.0:
		_waiting -= delta
		return  # standing at a waypoint
	_index = clampi(_index, 0, p.get_waypoint_count() - 1)
	if _host._move_toward(p.get_waypoint(_index)):
		_host._face_travel(delta)
	elif _host._move_holding():
		# The Locomotor GAVE UP for a beat (crowded by another NPC, an RVO doorway squeeze, a prop) — it did not ARRIVE.
		# Both cases make _move_toward return false, so advancing here skipped 1-2 posts (and with wait_time 0 it churned
		# waypoints EVERY frame of the ~1.5 s hold, resuming toward an essentially random post). Wait the hold out on the
		# CURRENT waypoint instead; a genuine arrival (not holding) still advances below.
		pass
	else:
		# Arrived (or the navmesh genuinely won't route there): pause here, then step to the next waypoint.
		_waiting = maxf(0.0, p.wait_time)
		_advance(p)

## Step the waypoint index: wrap when the path loops, ping-pong (bounce off each end) otherwise.
func _advance(p: PatrolPath) -> void:
	var n := p.get_waypoint_count()
	if n <= 1:
		return
	if p.loop:
		_index = (_index + 1) % n
		return
	if _index + _dir < 0 or _index + _dir >= n:
		_dir = -_dir  # bounce off the end
	_index += _dir

func _path() -> PatrolPath:
	if patrol_path.is_empty():
		return null
	return get_node_or_null(patrol_path) as PatrolPath

func _get_configuration_warnings() -> PackedStringArray:
	var p := get_parent()
	if p == null or not p.has_method(&"_move_toward"):
		return PackedStringArray(["PatrolBehavior must be a child of an NPC (it drives that NPC's idle movement)."])
	if patrol_path.is_empty():
		return PackedStringArray(["PatrolBehavior has no patrol_path assigned — the NPC will fall back to wander/hold."])
	return PackedStringArray()
