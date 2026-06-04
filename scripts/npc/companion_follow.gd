class_name CompanionFollow
extends Node

## The recruited-companion FOLLOW behaviour (Features I + J) — how a following NPC tails the player at a
## standoff and, when it falls behind off-screen, blinks up behind them rather than visibly trudging back.
## Split off NPC so the root keeps only the companion CONTRACT (can_recruit / start_following /
## stop_following / is_following — the dialogue stack calls them via has_method) plus the canonical
## `_leader` state that the root's own targeting (_acquire_target / _pick_defend_target) reads; this child
## owns the per-frame escort drive + the hidden teleport, with the FOLLOW_* tuning that's used nowhere else.
##
## Host-coupled: NPC builds it in _ready and sets `host` right after .new(); it READS host._leader / host._nav
## and CALLS back into the host's locomotion (_move_toward / _face_*) + physics helpers (_height_above_floor),
## and on a teleport writes host.global_position / velocity. Off-tree (a unit-test NPC built via .new() with
## no add_child) this child never exists — but a bare NPC also has _leader == null, so is_following() is false
## and the host never reaches the follow drive anyway, so nothing here runs in that case.

## Standoff gap (m) a following companion holds from the leader — close enough to read as an escort,
## far enough not to shove the player. It only paths toward the leader when farther than this.
const FOLLOW_STANDOFF: float = 3.0
## Beyond this distance from the leader, a following companion that's out of the player's view becomes
## eligible to TELEPORT up behind them (Feature J) instead of visibly trudging the whole way back.
const FOLLOW_TELEPORT_DISTANCE: float = 14.0
## Minimum seconds between follow-teleports, so a companion that keeps falling behind blinks up
## occasionally rather than stuttering forward every frame it's off-screen.
const FOLLOW_TELEPORT_COOLDOWN: float = 3.0
## How far BEHIND the leader (m) a teleport drops the companion — roughly the standoff, just out of
## frame. The candidate is snapped to the navmesh and re-checked to be off-screen before committing.
const FOLLOW_TELEPORT_BEHIND: float = 3.5
## Sideways spread (m) tried around the straight-behind teleport spot when the navmesh snap lands too
## far off, so the companion can reappear beside a wall/corner behind the player rather than not at all.
const FOLLOW_TELEPORT_SIDE_SPREAD: float = 2.5
## dot(player_forward, dir_to_companion) at or above this means the companion sits inside the player's
## view cone (roughly on-screen) — so a teleport is FORBIDDEN. Below it the companion is off to the
## side / behind, i.e. "not looking at it", and a hidden teleport reads as it simply keeping up.
const FOLLOW_VIEW_DOT: float = 0.35

## The NPC escorting a leader — set right after .new() in NPC._ready. The canonical `_leader` it's
## following lives on the host (the root's targeting reads it); this child only holds the teleport cd.
var host: NPC

## Follow-teleport (Feature J) cooldown countdown — seconds until this companion may blink up behind the
## leader again. Bled down every frame; the teleport only fires when it hits 0 AND the companion is far
## enough behind and out of the player's view (so it never pops on-screen).
var _follow_teleport_cd: float = 0.0

## Re-arm the teleport cooldown — called from the host's start_following so a just-recruited companion
## doesn't blink the instant it joins.
func reset_teleport_cooldown() -> void:
	_follow_teleport_cd = FOLLOW_TELEPORT_COOLDOWN

## Companion follow (Feature I): tail the leader at FOLLOW_STANDOFF. Far out -> path toward them (facing
## the way we travel); within the standoff -> hold and face the leader, escorting at their side. Before
## pathing we try a hidden teleport (Feature J) so a companion that has fallen behind off-screen blinks
## up rather than visibly trudging the whole way. Called from the host's _idle, so combat always preempts
## following.
func act(delta: float) -> void:
	if not is_instance_valid(host._leader):
		host._leader = null
		return
	_follow_teleport_cd = maxf(0.0, _follow_teleport_cd - delta)
	# Feature J: when we've fallen well behind AND we're outside the player's view, occasionally blink up
	# behind them so pursuit reads as keeping up — never while on-screen (the helper enforces both).
	var to_leader := host._leader.global_position - host.global_position
	var flat_dist := Vector2(to_leader.x, to_leader.z).length()
	if flat_dist > FOLLOW_TELEPORT_DISTANCE and _follow_teleport_cd <= 0.0:
		if _try_follow_teleport():
			_follow_teleport_cd = FOLLOW_TELEPORT_COOLDOWN
			host._face_point(host._leader.global_position, delta)
			return
	if flat_dist > FOLLOW_STANDOFF:
		if host._move_toward(host._leader.global_position):
			host._face_travel(delta)
		else:
			host._face_point(host._leader.global_position, delta)
	else:
		host._face_point(host._leader.global_position, delta)  # arrived at the leader's side — watch with them

## Feature J — try to teleport behind the leader to a reachable, OFF-SCREEN spot, masking the path back.
## Returns true only if it actually moved. HARD RULE: never teleport while the companion is in the
## player's view cone (dot of camera-forward vs direction-to-us). Reads the leader's camera forward
## read-only, samples points behind the player, snaps each to the navmesh (so the spot is reachable),
## and commits only one that lands behind the player AND out of view. No camera / no navmesh => no-op.
func _try_follow_teleport() -> bool:
	if host._nav == null or not host.is_inside_tree() or not is_instance_valid(host._leader):
		return false
	# Resolve the leader's view camera (the player exposes camera_effects). Without one we can't tell
	# whether we'd pop on-screen, so we refuse to teleport rather than risk it.
	var cam := host._leader.get(&"camera_effects") as Camera3D
	if cam == null or not is_instance_valid(cam):
		return false
	var cam_pos := cam.global_position
	var fwd := -cam.global_transform.basis.z  # Camera3D looks down -Z; this is where the player is looking
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length_squared() < 0.0001:
		return false  # looking straight up/down — bail rather than guess a "behind"
	fwd_flat = fwd_flat.normalized()
	# NEVER teleport while we're on-screen: if we already sit inside the view cone, abort.
	if _in_view_cone(cam_pos, fwd_flat, host.global_position):
		return false
	var map := host._nav.get_navigation_map()
	if not map.is_valid():
		return false
	# Candidate spots straight behind the leader, then fanned a little to each side so a wall/corner behind
	# the player still yields a reachable reappear point. First valid (reachable + behind + off-screen) wins.
	var behind := -fwd_flat  # direction from the player toward "behind them"
	var side := Vector3(fwd_flat.z, 0.0, -fwd_flat.x)  # horizontal perpendicular for the side fan
	var base := host._leader.global_position + behind * FOLLOW_TELEPORT_BEHIND
	var candidates: Array[Vector3] = [
		base,
		base + side * FOLLOW_TELEPORT_SIDE_SPREAD,
		base - side * FOLLOW_TELEPORT_SIDE_SPREAD,
	]
	var lift := host._height_above_floor()  # keep the body resting on the new floor instead of sinking into it
	for c in candidates:
		var snapped := NavigationServer3D.map_get_closest_point(map, c)
		# Reject a snap that drifted far from the requested spot (no navmesh nearby -> it clamps to the
		# closest mesh, which could be anywhere, even back in front of the player).
		if Vector2(snapped.x - c.x, snapped.z - c.z).length() > FOLLOW_TELEPORT_SIDE_SPREAD + 0.5:
			continue
		var dest := snapped + Vector3.UP * lift
		# Final gate: the destination must be BEHIND the player and outside the view cone, so we never
		# materialise where they can see us (e.g. the snap pulled the point around a corner into frame).
		if _in_view_cone(cam_pos, fwd_flat, dest):
			continue
		host.global_position = dest
		host.velocity = Vector3.ZERO  # land clean — don't carry stale chase momentum into the new spot
		if host._nav:
			host._nav.target_position = host.global_position  # re-seed the agent so it doesn't path back from the OLD spot
		return true
	return false

## True if `point` sits inside the player's horizontal view cone from `cam_pos` looking along `fwd_flat`
## — i.e. roughly on-screen. Uses the same dot-vs-FOLLOW_VIEW_DOT test for the on-screen guard AND the
## post-snap re-check, so "don't teleport on-screen" and "don't land on-screen" share one definition.
func _in_view_cone(cam_pos: Vector3, fwd_flat: Vector3, point: Vector3) -> bool:
	var to_point := point - cam_pos
	to_point.y = 0.0
	if to_point.length_squared() < 0.0001:
		return true  # right on top of the camera — treat as visible (refuse the teleport)
	return fwd_flat.dot(to_point.normalized()) >= FOLLOW_VIEW_DOT
