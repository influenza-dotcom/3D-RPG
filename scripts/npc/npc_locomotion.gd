class_name NpcLocomotion
extends Node

## NPC NON-COMBAT movement states. Owns WHERE an off-duty NPC
## goes: the idle update (companion-tail delegation -> wander -> return-to-post / hold), the wander roam
## (destination + dwell bookkeeping), and the flee run. Called from npc.gd through
## narrow facades (_idle / _act_flee), so NPC remains the coordination point.
##
## DELIBERATELY NOT here:
## apply_velocity is a Character override + RVO/knockback shell that stays on npc.gd (the sole move_and_slide writer);
## the anti-stuck give-up machine + wall_slide_dir body MIGRATED to Locomotor.update_stuck in Phase B (npc.gd keeps
## thin forwarding static shells so NPC.wall_slide_dir still resolves). _move_toward is now a shell onto Locomotor, and
## the _face_* helpers / _desired_velocity are SHARED with combat pursuit — all stay on npc.gd. _pick_wander_point also
## stays there: it's pure math pinned by test_ranged_behavior on an off-tree NPC (where no component children exist).
## This component only picks destinations and drives host._move_toward.
##
## `host` is typed Node (not NPC) to break the NpcLocomotion <-> NPC class cycle, so every host.X is a
## dynamic call — vars built from host.* use explicit type annotations (`: Vector3 =`), never `:=`
## (GDScript can't infer a type from a Variant). Built in NPC._build_components like the other children.

var host: Node = null  ## the NPC we move (Node-typed to avoid the class cycle)

## Wander bookkeeping (used only when host.wanders): the current roam destination + a dwell pause.
var _wander_target: Vector3
var _has_wander_target: bool = false
var _wander_dwell: float = 0.0

## The PatrolBehavior child of our host (found + cached once): when active it replaces wander with route walking.
var _patrol: Node = null
var _patrol_checked: bool = false

## The ScheduleBehavior child of our host (found + cached once): when active it drives idle movement to the
## WorldClock phase's destination — above patrol/wander, below companion-follow.
var _schedule: Node = null
var _schedule_checked: bool = false


## NPC-pooling reuse reset (NpcPool): drop the stale roam destination + dwell so a reused wanderer picks a fresh
## point near its NEW spawn instead of walking back toward the previous life's coordinates (or standing frozen for
## a stale dwell). The _patrol/_schedule sibling caches are DELIBERATELY kept — a homogeneous pool reuses the same
## sibling components, so re-scanning would be wasted work.
func reset_for_reuse() -> void:
	_has_wander_target = false
	_wander_dwell = 0.0
	_wander_target = Vector3.ZERO


## Non-combat idle update. A recruited COMPANION tails its leader (overriding wander/hold); otherwise
## wanderers roam near spawn, and a plain NPC either returns to its post (return_to_post, when knocked
## away) or holds still — so a non-following FIGHT combatant is unchanged.
func _idle(delta: float, return_to_post: bool) -> void:
	if host.is_following() and host._follow != null:
		host._follow.act(delta)  # tail the leader (+ the hidden teleport) — the CompanionFollow child owns the drive
		return
	if _host_is_sitting():
		# Parked: hold the seat and just settle onto the authored facing. This is NOT the "knocked off my post"
		# case — NPC.is_sitting() already requires being AT the post (GameSettings.npc_ai.seat_return_radius), so a
		# displaced sitter reads as standing and falls through to the return-to-post walk at the bottom instead.
		if return_to_post:
			host._face_yaw(host._spawn_yaw, delta)
		return
	var sched := _schedule_behavior()
	if sched != null and sched.is_active():
		sched.act(delta)  # follow the daily routine (WorldClock phase -> destination marker) — above patrol/wander
		return
	var patrol := _patrol_behavior()
	if patrol != null and patrol.is_active():
		patrol.act(delta)  # walk a fixed PatrolPath route instead of wander — runs only while idle, so combat interrupts it
		return
	if host.wanders:
		_wander(delta)
		return
	if not return_to_post:
		return
	# Snap the post to the navmesh so an NPC knocked off / spawned a hair off doesn't grind toward an off-mesh spot.
	if host._move_toward(host._snap_to_navmesh(host._spawn_position, 3.0)):
		host._face_travel(delta)
	else:
		host._face_yaw(host._spawn_yaw, delta)


## Our host's PatrolBehavior child, if it has one (found + cached once). When active it takes over idle
## movement — walking a fixed PatrolPath route — in place of wander. Looked up here so npc.gd stays untouched.
func _patrol_behavior() -> Node:
	if not _patrol_checked:
		_patrol_checked = true
		for c in host.get_children():
			if c is PatrolBehavior:
				_patrol = c
				break
	return _patrol


## Our host's ScheduleBehavior child, if any (found + cached once). When active it takes over idle movement —
## walking to the WorldClock phase's destination — above patrol/wander. Looked up here so npc.gd stays untouched.
func _schedule_behavior() -> Node:
	if not _schedule_checked:
		_schedule_checked = true
		for c in host.get_children():
			if c is ScheduleBehavior:
				_schedule = c
				break
	return _schedule


## True while a DIRECTED idle route is active — a ScheduleBehavior (daily routine) or PatrolBehavior (fixed path)
## currently driving idle movement. The music-reaction body-turn (npc.gd _react_music, via host._on_directed_route)
## checks this so stopping to face a radio never interrupts a guard's patrol / an NPC's schedule; a plain wanderer /
## posted NPC (no active route) still stops to look. Companion-follow isn't checked — _react_music bails for followers.
func has_active_route() -> bool:
	var sched := _schedule_behavior()
	if sched != null and sched.is_active():
		return true
	var patrol := _patrol_behavior()
	return patrol != null and patrol.is_active()

func _host_is_sitting() -> bool:
	return host != null and host.has_method(&"is_sitting") and bool(host.call(&"is_sitting"))


## Roam: walk to a random point within wander_radius of spawn, dwell a beat on arrival, then pick a
## fresh one. Reuses the same navmesh pathing + facing as combat pursuit, so it routes around walls.
func _wander(delta: float) -> void:
	if _wander_dwell > 0.0:
		_wander_dwell -= delta  # lingering at a stop, standing where we arrived
		return
	if not _has_wander_target:
		_wander_target = host._pick_wander_point()
		_has_wander_target = true
	if host._move_toward(_wander_target):
		host._face_travel(delta)
	else:
		# Arrived, or the navmesh wouldn't route there: pause, then choose a new spot next time.
		_has_wander_target = false
		_wander_dwell = randf_range(host.wander_dwell_min, host.wander_dwell_max)


## Flee: each frame, head for a point flee_distance straight away from the threat. Recomputed every
## frame so the destination keeps running ahead of us; we face the way we run and never fire. The threat
## point comes from host._flee_threat_point() (NOT _aim_point) so a TARGET-LESS flee — a scripted
## investigate() / alarm that leaves perception non-UNAWARE but with no _target — flees from
## last_known_position instead of null-derefing _aim_point on both target handles (C6).
func _act_flee(delta: float) -> void:
	var away: Vector3 = host.global_position - host._flee_threat_point()
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(sin(host._spawn_yaw), 0.0, cos(host._spawn_yaw))  # standing on the threat: bolt spawn-ward
	# Snap the (computed, ever-moving) flee point to walkable ground so a fleer runs ALONG the mesh away from the
	# threat instead of grinding into a wall/corner; off-mesh recovery still rescues it if it does slip off.
	var flee_to: Vector3 = host._snap_to_navmesh(host.global_position + away.normalized() * host.flee_distance, 4.0)
	if host._move_toward(flee_to):
		host._face_travel(delta)
	else:
		host._face_point(flee_to, delta)
