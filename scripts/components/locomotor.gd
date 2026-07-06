@tool
class_name Locomotor
extends Node

## Drop-in PATHFINDING + LOCOMOTION for any CharacterBody3D. Attach it under a CharacterBody3D, call move_to(pos),
## and it routes there on the baked navmesh — RVO-avoiding other agents / dynamic obstacles, applying gravity, and
## (optionally) turning to face travel. It OWNS its own NavigationAgent3D (parented to the body, so the agent
## navigates from the body's position) and, in the default AUTONOMOUS mode, drives the body itself (gravity +
## move_and_slide) each physics frame — drop it on a bare mob and it just moves. Set drive_body = false for DRIVEN
## mode: it only COMPUTES steering into `desired_velocity` and the host runs its own move_and_slide + RVO (how the
## NPC will consume it after the npc.gd nav-cluster migration — see scripts/npc/README.md).
##
## All host reads are duck-typed — get_parent() as CharacterBody3D for the body, and optional move_speed / move_accel
## / air_accel / turn_speed via get() with @export fallbacks — so it never hard-depends on a script type (the
## LocomotionFx idiom). It needs a baked NavigationRegion3D in the level (the same one NPCs path on); every nav-map
## query is gated on NavigationUtils.is_nav_map_ready so a freshly-loaded / re-baked map never errors ("query made
## before first map synchronization") — see the memory note nav-map-query-before-sync.
##
## DELIBERATELY NOT in this baseline: the NPC's combat nav-hop (jump to reach a perched target) and the anti-stuck /
## off-mesh-recovery steering — those pursuit refinements still live on npc.gd (npc_move_toward / _update_stuck). This
## is the clean generic mover; those can be lifted here when the NPC migrates onto it.

## Arrived within arrival_distance of the current move_to() target (fires once per destination, then again after the
## next move_to). Wire it to trigger the next patrol point, open a door, start a bark, etc.
signal reached_target
## The current target has NO navmesh path (unreachable — off the mesh / disconnected island). Fires once per move_to.
signal path_blocked

## Movement speed (m/s). A host `move_speed` property WINS (duck-typed) so an NPC's tuned speed drives this with no duplication.
@export var move_speed: float = 4.0
## Ground / air acceleration (m/s^2) easing velocity toward the desired — how snappily it starts, stops, and turns.
## Host `move_accel` / `air_accel` win when present.
@export var move_accel: float = 25.0
@export var air_accel: float = 2.0
## RVO agent radius (m) — how wide a berth it gives other agents + dynamic obstacles. Match the body's capsule radius.
@export var agent_radius: float = 0.6
## How close (m) counts as "arrived" — fires reached_target and stops. Also the agent's target_desired_distance.
@export var arrival_distance: float = 1.0
## Turn to face the travel direction? Off = keep the body's authored facing (e.g. a mob you rotate yourself).
@export var face_travel: bool = true
## Yaw turn rate (rad/s) when face_travel is on. Host `turn_speed` wins when present.
@export var turn_speed: float = 8.0
## AUTONOMOUS (default): drive the body — gravity + move_and_slide — ourselves, so a bare CharacterBody3D just moves.
## OFF (driven): only COMPUTE `desired_velocity`; the host runs its own move loop + RVO and reads it (the NPC path).
@export var drive_body: bool = true

## This frame's steering result (world space, horizontal, y = 0) — the RAW nav-follow velocity BEFORE RVO. In
## autonomous mode we RVO-blend + apply it; in driven mode the host reads it and does its own RVO (as npc.gd already does).
var desired_velocity: Vector3 = Vector3.ZERO

var _nav: NavigationAgent3D
var _has_target: bool = false
var _arrived: bool = true          ## latched so reached_target fires once per destination
var _blocked_notified: bool = false  ## latched so path_blocked fires once per destination
var _avoid_velocity: Vector3 = Vector3.ZERO
var _avoid_ready: bool = false     ## false until the first velocity_computed callback -> fall back to the raw desired

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only _get_configuration_warnings runs in the editor; never build nav / drive the body there
	var body := get_parent() as CharacterBody3D
	if body == null:
		return  # nothing to move (the config warning already tells the designer) — stay inert
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.5
	_nav.target_desired_distance = arrival_distance
	# RVO: route AROUND other agents + dynamic obstacles (a thrown crate carries a NavBlocker AVOID) instead of bumping.
	_nav.avoidance_enabled = true
	_nav.radius = agent_radius
	_nav.height = 1.9
	_nav.neighbor_distance = 6.0
	_nav.max_neighbors = 8
	_nav.max_speed = 12.0
	_nav.velocity_computed.connect(_on_avoidance_velocity)
	body.add_child(_nav)  # the agent navigates from its PARENT's position -> parent it to the BODY, like npc.gd's _nav

## Route toward `target` on the navmesh; re-arms the arrival / blocked notifications for this new destination.
func move_to(target: Vector3) -> void:
	if _nav == null:
		return  # off-tree / non-CharacterBody3D host: nothing to steer
	_nav.target_position = target
	_has_target = true
	_arrived = false
	_blocked_notified = false

## Stop pathing (clears the destination); the body eases to a halt through accel, and gravity still applies.
func stop() -> void:
	_has_target = false
	desired_velocity = Vector3.ZERO

## Are we actively heading somewhere (a target set and not yet arrived)?
func is_moving() -> bool:
	return _has_target and not _arrived

func _on_avoidance_velocity(safe_velocity: Vector3) -> void:
	_avoid_velocity = safe_velocity
	_avoid_ready = true

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _nav == null:
		return
	var body := get_parent() as CharacterBody3D
	if body == null:
		return
	desired_velocity = _compute_desired(body)
	if drive_body:
		_drive(body, delta)
	if face_travel and desired_velocity.length_squared() > 0.0001:
		_face(body, delta)

## The raw nav-follow velocity toward the current target (no RVO — that's applied in _drive / by the host). ZERO when
## there's no target, we've arrived (fires reached_target), the target is unreachable (fires path_blocked), or the map
## hasn't synced yet. Mirrors npc.gd's _move_toward path-stepping, minus the pursuit-only hop / anti-stuck.
func _compute_desired(body: CharacterBody3D) -> Vector3:
	if not _has_target:
		return Vector3.ZERO
	# Wait for the nav map's first sync before trusting the path — querying earlier ERRORS (nav-map-query-before-sync).
	if not NavigationUtils.is_nav_map_ready(_nav.get_navigation_map()):
		return Vector3.ZERO
	if _nav.is_navigation_finished():
		if not _arrived:
			_arrived = true
			reached_target.emit()
		return Vector3.ZERO
	if not _nav.is_target_reachable():
		if not _blocked_notified:
			_blocked_notified = true
			path_blocked.emit()
		return Vector3.ZERO
	var to_next := _nav.get_next_path_position() - body.global_position
	to_next.y = 0.0
	if to_next.length() < 0.05:
		return Vector3.ZERO
	return to_next.normalized() * _tuning(body, &"move_speed", move_speed)

## Autonomous body drive: gravity first (matching Character.gravity ordering), RVO-blend the horizontal desired, ease
## velocity toward it at the ground/air accel, then move_and_slide. The single move step for a bare-mob host.
func _drive(body: CharacterBody3D, delta: float) -> void:
	var vel := body.velocity
	if not body.is_on_floor():
		vel += body.get_gravity() * delta
	var desired_h := Vector2(desired_velocity.x, desired_velocity.z)
	# RVO: feed the agent our intended velocity + adopt the collision-free result (1-frame lag; ~= the request in the
	# open, so a no-op with nothing nearby). Report stationary when idle so neighbours route around us (no idle shimmy).
	if desired_h.length() > 0.3:
		_nav.velocity = Vector3(desired_h.x, 0.0, desired_h.y)
		if _avoid_ready:
			desired_h = Vector2(_avoid_velocity.x, _avoid_velocity.z)
	else:
		_nav.velocity = Vector3.ZERO
	var rate := _tuning(body, &"move_accel", move_accel) if body.is_on_floor() else _tuning(body, &"air_accel", air_accel)
	var horizontal := Vector2(vel.x, vel.z).move_toward(desired_h, rate * delta)
	vel.x = horizontal.x
	vel.z = horizontal.y
	body.velocity = vel
	body.move_and_slide()

## Smoothly yaw the body toward its travel direction.
func _face(body: CharacterBody3D, delta: float) -> void:
	var yaw := atan2(desired_velocity.x, desired_velocity.z)
	var rot := body.rotation
	rot.y = lerp_angle(rot.y, yaw, _tuning(body, &"turn_speed", turn_speed) * delta)
	body.rotation = rot

## Duck-typed tuning: a numeric host property wins over the @export fallback, so an NPC's tuned values drive this with
## no duplication and a bare mob (no such property) uses the Inspector defaults. Never hard-depends on a host type.
func _tuning(body: Node, prop: StringName, fallback: float) -> float:
	var v: Variant = body.get(prop)
	return float(v) if (v is float or v is int) else fallback

## Editor warning: a Locomotor can only move a CharacterBody3D. Surfaces the mistake of dropping it under the wrong node.
func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is CharacterBody3D:
		return PackedStringArray()
	return PackedStringArray([
		"Locomotor must be a child of a CharacterBody3D — that's the body it pathfinds + moves. It does nothing under any other node type."
	])
