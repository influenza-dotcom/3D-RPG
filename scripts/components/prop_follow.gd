class_name PropFollow
extends Node

## Drop-in "this prop follows the player" component (designer-first: drag onto any Throwable / RigidBody3D / Node3D
## prop — a claimed dog, a hover-drone, a floating companion orb). It makes the prop keep up with the player using
## the SAME trick recruited NPC companions use ([[companion_follow.gd]]): when the prop has fallen well behind AND is
## OFF-SCREEN, it silently blinks to a spot just behind the player. So a dropped dog that you walked away from
## reappears at your heel rather than being left in the dust.
##
## Why a separate component from CompanionFollow: that one is welded to the NPC brain (it needs host._leader,
## host._nav, navmesh pathing, _move_toward / _face_*). A Throwable is a PHYSICS PROP with NO navmesh and no AI, so
## this re-implements only the part that works without nav — the hidden teleport — and swaps the navmesh snap for a
## down-ray that rests the prop on the floor. It does NOT walk the prop toward you between blinks (a RigidBody has no
## pathing); the prop simply sits where it lands and blinks up again when you get far enough ahead.
##
## How it's used: shipped DISABLED on a prop and switched on when the player CLAIMS it ([[claimable.gd]] flips
## `enabled` / adds this node on claim). Off (enabled = false) it's completely inert — _physics_process early-outs —
## so an unclaimed prop never follows. Operates on its PARENT (get_parent()); off-tree (a bare .new() unit stub with
## no parent) it's inert too.

## How far BEHIND the player (m) a blink drops the prop — roughly arm's reach behind them, out of frame.
@export var teleport_behind: float = 3.0
## Sideways spread (m) tried around the straight-behind spot when the first candidate has no floor under it, so the
## prop can still land beside a wall/corner behind the player rather than not at all.
@export var teleport_side_spread: float = 2.0
## Flat (horizontal) distance (m) the prop must be BEHIND the player before a blink is even considered. Below it the
## prop is "keeping up" and stays put; above it (and off-screen) it blinks. Keep it comfortably larger than the
## carry distance so a held prop never qualifies.
@export var teleport_distance: float = 9.0
## Seconds between blinks — paces the teleport so the prop can't strobe. Bled down every physics frame.
@export var teleport_cooldown: float = 1.5
## dot(player_forward, dir_to_prop) at or above this means the prop sits inside the player's view cone (roughly
## on-screen) — so a blink is FORBIDDEN (it would pop in view). Below it the prop is off to the side / behind, where a
## hidden teleport reads as it simply catching up. Matches CompanionFollow.FOLLOW_VIEW_DOT.
@export var view_dot: float = 0.35
## How far up/down (m) the ground down-ray probes from a candidate spot to find a floor to rest the prop on. Raise it
## for tall steps / ledges behind the player.
@export var ground_probe: float = 3.0
## Master switch. Off => this prop never follows (the component is inert). Shipped off on an unclaimed prop; Claimable
## flips it on when the prop is claimed.
@export var enabled: bool = false

var _cooldown: float = 0.0  ## seconds until the next blink is allowed; bled down every physics frame

## The prop we move — our parent, resolved once. Null off-tree (bare .new() in a unit test) -> inert.
func _body() -> Node3D:
	var p := get_parent()
	return p as Node3D


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not enabled:
		return
	var body := _body()
	if body == null or not body.is_inside_tree():
		return
	# A held/frozen prop is at arm's length (never far enough to blink) and shouldn't be yanked out of the player's
	# hands — skip it outright. (Carried Throwables sit right on the camera, so the distance gate also covers this.)
	if body is RigidBody3D and (body as RigidBody3D).freeze:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var player := _real_player()
	if player == null:
		return
	var to_player := player.global_position - body.global_position
	var flat_dist := Vector2(to_player.x, to_player.z).length()
	if not should_blink(flat_dist, teleport_distance, _cooldown):
		return
	if _try_blink(body, player):
		_cooldown = teleport_cooldown


## Re-arm the cooldown so a just-claimed prop doesn't blink the instant it's switched on (mirrors
## CompanionFollow.reset_teleport_cooldown). Called by Claimable right after it enables us.
func reset_cooldown() -> void:
	_cooldown = teleport_cooldown


## Pure decision half (no view-cone / no floor — those need the live scene): far enough behind AND off cooldown.
## Static + tiny so it's unit-testable with literal numbers, mirroring Pettable.eligible / SilentTakedown.eligible.
static func should_blink(flat_dist: float, distance_threshold: float, cooldown_remaining: float) -> bool:
	return cooldown_remaining <= 0.0 and flat_dist > distance_threshold


## Try to teleport `body` to a reachable, OFF-SCREEN spot behind `player`. Returns true only if it actually moved.
## HARD RULE (same as the companion blink): never materialise where the player can see us. Reads the player's view
## camera read-only, samples points behind them, down-rays each to find a floor, and commits the first that has
## ground AND lands off-screen. No camera / no floor anywhere => no-op (we just stay put and try again next frame).
func _try_blink(body: Node3D, player: Node3D) -> bool:
	var cam := player.get(&"camera_effects") as Camera3D
	if cam == null or not is_instance_valid(cam):
		return false  # can't tell whether we'd pop on-screen -> refuse rather than risk it
	var cam_pos := cam.global_position
	var fwd := -cam.global_transform.basis.z  # Camera3D looks down -Z; this is where the player is looking
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length_squared() < 0.0001:
		return false  # looking straight up/down — bail rather than guess a "behind"
	fwd_flat = fwd_flat.normalized()
	var behind := -fwd_flat  # direction from the player toward "behind them"
	var side := Vector3(fwd_flat.z, 0.0, -fwd_flat.x)  # horizontal perpendicular for the side fan
	var base := player.global_position + behind * teleport_behind
	var candidates: Array[Vector3] = [
		base,
		base + side * teleport_side_spread,
		base - side * teleport_side_spread,
	]
	var space := body.get_world_3d().direct_space_state
	for c in candidates:
		var dest: Variant = _floor_under(space, c, body)  # Vector3 rest point, or null when no floor (annotate: Variant)
		if dest == null:
			continue  # no floor beneath this candidate
		var point: Vector3 = dest
		# Final gate: the landing spot must be OUTSIDE the view cone, so a candidate that snapped around a corner
		# back into frame is rejected.
		if in_view_cone(cam_pos, fwd_flat, point, view_dot):
			continue
		body.global_position = point
		if body is RigidBody3D:
			# Land clean: drop stale chase momentum so the prop doesn't keep sliding after the blink. Setting
			# global_position on a RigidBody is an immediate teleport; zeroing the velocities stops the physics step
			# from carrying the old motion into the new spot.
			(body as RigidBody3D).linear_velocity = Vector3.ZERO
			(body as RigidBody3D).angular_velocity = Vector3.ZERO
		return true
	return false


## Down-ray from just above `spot` to find the floor; returns the rest point (a hair above the hit) or null if there's
## no ground within ground_probe. Excludes the body itself so it can't hit its own collider.
func _floor_under(space: PhysicsDirectSpaceState3D, spot: Vector3, body: Node3D) -> Variant:
	var from := spot + Vector3.UP * ground_probe
	var to := spot + Vector3.DOWN * ground_probe
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return (hit["position"] as Vector3) + Vector3.UP * 0.1  # rest a hair above the floor; physics settles the rest


## True if `point` sits inside the player's horizontal view cone from `cam_pos` looking along `fwd_flat` — i.e.
## roughly on-screen. Same dot-vs-view_dot test CompanionFollow uses, factored static so it's unit-testable and so
## "don't land on-screen" has one definition.
static func in_view_cone(cam_pos: Vector3, fwd_flat: Vector3, point: Vector3, dot_threshold: float) -> bool:
	var to_point := point - cam_pos
	to_point.y = 0.0
	if to_point.length_squared() < 0.0001:
		return true  # right on top of the camera — treat as visible (refuse the blink)
	return fwd_flat.dot(to_point.normalized()) >= dot_threshold


## The HUMAN player (the non-NPC member of the Player group) — not a recruited companion (companions join the same
## group for targeting but are NPCs). Mirrors StatsScreen._find_real_player / the [[groups-registry-and-player-group]]
## rule. Null when there's no player (e.g. a bare unit scene).
func _real_player() -> Node3D:
	return Groups.human_player(get_tree())  # M6: centralized human-player lookup (off-tree get_tree() is null -> null)
