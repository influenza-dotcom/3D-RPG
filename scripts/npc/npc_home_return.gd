@tool
class_name NpcHomeReturn
extends Node

## "GO HOME" — the NPC leash / world-reset drop-in. Sends an NPC back to the spot it was authored at when the
## world should settle down, so a level stops slowly draining its cast into wherever the last firefight ended.
##
## TWO triggers, both optional:
##   1. THE PLAYER DIED (`GameState.player_died`). The default CHECKPOINT_RESPAWN death mode is a Dark-Souls
##      in-place revive — the world is NOT reloaded — so without this every NPC that chased you across the map is
##      still standing wherever it lost you when you come back. That cue is timed to the death cinematic's FULLY
##      BLACK frame (the beat the "You were killed by X" card fades in on), NOT the moment of death: fired earlier
##      you can literally watch the cast teleport away through the closing vignette. Because the screen is covered,
##      the on-screen guard is ignored by default here (`death_return_ignores_view`).
##   2. OFF-SCREEN FOR A WHILE (`off_screen_delay`). The NPC has been outside the player's view cone — and, with
##      `occlusion_check`, behind geometry counts as out of view — for that long AND is further from home than the
##      slack. This is the leash for "the guard chased me two districts away and just stayed there".
##
## AN NPC WITH AGGRO IS NEVER TELEPORTED BY TRIGGER 2. Locked on, hunting a lost trail, or just holding the player
## as a not-yet-noticed proximity target — breaking line of sight must not make an enemy evaporate mid-encounter.
## `_may_blink()` enforces that as a hard rule, not a knob: the most a leashed-but-aggro'd NPC does is stand down
## and walk back. Only the player-death reset (trigger 1, on a black screen) is allowed past it.
##
## HOW it returns is the dog / companion trick in reverse: a HIDDEN BLINK. [[companion_follow.gd]] teleports a
## companion that has fallen behind OFF-SCREEN up to the player's heel, and [[prop_follow.gd]] does the same for a
## claimed dog; this teleports an NPC that has been left behind off-screen back to its post. The rule is identical
## and non-negotiable: never move a body the player can see. When a blink is refused (or `blink_home` is off) the
## NPC still STANDS DOWN, and the GOAP Idle floor's existing walk-back (NpcLocomotion._idle's return-to-post /
## wander re-centre) brings it home on foot — which is the right read while the player is watching.
##
## WHAT IT DOES NOT RESET: hostility. `NPC.stand_down()` drops the current engagement (target, attacker lock,
## perception -> UNAWARE) but deliberately leaves `_provoked`, faction standing and NPC-vs-NPC grudges alone — a
## guard you shot is still angry the next time it sees you, it has simply gone back to its post. Quest / faction
## state is untouched.
##
## EXEMPT (see `_eligible()`): a recruited COMPANION (its home is the player — CompanionFollow owns its own blink),
## a BODYGUARD on duty (it belongs beside its VIP), an NPC under cutscene control, one walking up for a
## conversation, and the dead.
##
## AUTHORING: every NPC auto-builds one of these in `NPC._build_components`, seeded from `GameSettings.npc_ai`
## (resources/tuning/NpcAiSettings.tres) — the global leash dials. Drop a CONFIGURED `NpcHomeReturn` under an NPC in
## the scene to override any of it per instance (the auto-build then leaves your node alone), e.g. a shopkeeper with
## `off_screen_delay = 2.0` who is always behind his counter, or `enabled = false` for a story NPC that must stay
## exactly where the last scene left it.
##
## `host` is typed Node (not NPC) to break the NpcHomeReturn <-> NPC class cycle, so every host.X is a DYNAMIC call —
## vars built from host.* carry explicit type annotations, never `:=`. NPC also builds/matches this component by
## SCRIPT PATH, never by bare type, so the @tool NPC root never names the class at parse time (the new-classname
## reimport cascade). Off-tree (a bare `.new()` in a unit test) `host` stays null and every entry point no-ops.

## Master switch. Off => this NPC never leashes home (the component is inert). Seeded from
## GameSettings.npc_ai.home_return on the auto-built instance.
@export var enabled: bool = true

@export_group("Home")
## OPTIONAL override for "the original position": a Marker3D / Node3D whose transform is where this NPC belongs.
## Empty (the default) = the spot + facing the NPC was standing at when it spawned (its `_spawn_position` /
## `_spawn_yaw`, the same anchor wander and return-to-post already re-centre on, and which pool reuse + a save
## reload re-stamp). Place the marker at the NPC's OWN origin height, not on the floor.
@export var home_marker: NodePath
## How far (m, horizontal) the NPC may be from home before a return is worth doing. Inside this it is already
## "at its post". A WANDERER additionally gets its whole `wander_radius` as slack — roaming its own disc is not
## being away from home.
@export var home_slack: float = 3.0
## Snap the home point to the navmesh before teleporting onto it (and re-float it off the floor by the body's
## current height above ground). Leave OFF: the authored spawn spot is already a valid standing position, and
## snapping can drag a deliberately off-mesh NPC (a sentry on a crate, a seated shopkeeper) to the nearest walkable
## poly. Turn it on only if a level's NPCs are authored off the baked mesh.
@export var snap_home_to_navmesh: bool = false

@export_group("Player death")
## Send this NPC home when the player dies (GameState.player_died). The default CHECKPOINT_RESPAWN death mode
## leaves the world untouched, so this is what makes an encounter reset instead of staying scattered.
@export var return_on_player_death: bool = true
## EXTRA seconds to wait after the cue before the return fires. Defaults to 0 — and should normally stay there.
## `GameState.player_died` is already timed to the fully-black beat of the death cinematic (the moment the "You
## were killed by X" card comes up), so there is nothing left to hide behind; the delay exists only to push the
## reset later still, e.g. past the card's fade-out. Measured in REAL seconds (a wall-clock deadline), because the
## cinematic runs at Engine.time_scale 0.3 and a scaled countdown would stretch ~3x and land on the fade back UP.
@export var death_return_delay: float = 0.0
## Blink home on player death even if the NPC / its post is technically in the player's view cone. TRUE by default,
## and safe: the cue fires on the cinematic's FULLY BLACK frame, so "in the view cone" no longer means "on screen"
## — the camera is pointed at a black screen. Refusing here would just leave a camp half-reset. Set FALSE to hold
## the same guard as the off-screen trigger anyway; the request then falls through to the off-screen path, which
## fires it the moment the NPC is genuinely unobserved (so leave `return_when_off_screen` on if you do that).
@export var death_return_ignores_view: bool = true

@export_group("Off screen")
## Send this NPC home once it has been out of the player's view for `off_screen_delay` seconds.
@export var return_when_off_screen: bool = true
## Seconds unobserved before the leash pulls. The clock resets the instant the NPC is visible again (and, with
## `off_screen_requires_calm`, whenever it has something to fight).
@export var off_screen_delay: float = 15.0
## Only run the off-screen clock while the NPC is CALM — perception UNAWARE with no live target. ON (default) means
## the leash never yanks an enemy out of a running fight just because you ducked around a corner: it waits for
## perception to give up (forget_time / pursuit_grace_time) first, THEN counts. Turn it OFF for a hard leash where
## breaking line of sight for long enough resets the encounter outright — note that even then an NPC with aggro on
## you is only STOOD DOWN and walked back, never teleported (see `_may_blink`).
@export var off_screen_requires_calm: bool = true

@export_group("How it returns")
## Teleport home (the hidden blink) rather than walking. OFF = the NPC only stands down and WALKS back through the
## normal idle return-to-post, which cannot recover one stranded off the navmesh — that's what the blink is for.
## (A SEATED NPC does walk back: NPC.is_sitting() is false while it is away from its post, so the idle return-to-
## post drives it home and the seat only re-applies on arrival.) The blink is still never allowed while the
## player can see the NPC or its post.
@export var blink_home: bool = true
## How far (m, horizontal) the NPC must be from the player before a blink is allowed at all. Out of the view cone
## is not the same as unnoticeable: a body that disappears from a few metres away is felt even when it's behind
## you (its footsteps stop, and you're one turn away from looking straight at where it was). Under this distance
## the NPC stands down and WALKS back instead. Same reasoning as CompanionFollow's follow_teleport_distance.
@export var min_blink_distance: float = 8.0
## dot(player_forward, direction_to_point) at or above this counts as "in the player's view" — so a blink is
## FORBIDDEN. Matches CompanionFollow.FOLLOW_VIEW_DOT / PropFollow.view_dot: a deliberately WIDE cone, so the guard
## errs toward refusing rather than popping something on screen.
@export var view_dot: float = 0.35
## Also require a clear LINE OF SIGHT before treating a point as visible: a point inside the view cone but behind
## solid geometry (an NPC in a building you happen to be facing) counts as OUT of view, so it may blink. One
## raycast per scan, and only when the cone test already said "in view".
@export var occlusion_check: bool = true
## Seconds between off-screen evaluations (the cone test + at most one occlusion ray). The off-screen clock
## advances in these steps, so keep it well under `off_screen_delay`.
@export var scan_interval: float = 0.25

## The NPC we leash — bound by NPC._build_components right after the build (Node-typed to avoid the class cycle).
var host: Node = null

var _scan_t: float = 0.0        ## countdown to the next off-screen evaluation
var _off_screen_t: float = 0.0  ## seconds unobserved so far (reset by visibility / combat / being home)
## Time.get_ticks_msec() deadline for an armed player-death return; -1 = none armed. A WALL-CLOCK deadline, not a
## delta countdown, because the death cinematic runs at Engine.time_scale 0.3 (and hitstop can pin it near 0): a
## delta-based `death_return_delay` would stretch to 3x+ real seconds and land on/after the respawn, exactly the
## moment the screen fades back UP. The cinematic's own timing ignores time scale too, so this matches it.
var _death_due_msec: int = -1


func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor
	# The player-death cue is an autoload signal, so this connection survives NpcPool reuse (the component is never
	# rebuilt) and needs no spawn-order handshake with the Player node.
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)


## NPC-pooling reuse reset (NpcPool): drop the per-life timers so a reused body starts its off-screen clock fresh
## and never inherits a pending death return from the previous life.
func reset_for_reuse() -> void:
	_scan_t = 0.0
	_off_screen_t = 0.0
	_death_due_msec = -1


## Send this NPC home NOW. `ignore_view` skips the "never move a body the player can see" guard (the death
## cinematic is the only caller that does). Returns true when the NPC was actually sent home — either blinked, or
## stood down so the idle floor walks it back; false when it is exempt, or a blink was refused because the player
## could see the NPC or its post (call again later — the off-screen scan does exactly that).
## Public so a cutscene / dialogue consequence can reset an NPC too (NPC.send_home() is the facade).
func return_home(ignore_view: bool = false) -> bool:
	if not enabled or not _eligible():
		return false
	var dest: Vector3 = home_position()
	if blink_home and (ignore_view or _may_blink()):
		if not ignore_view and (_visible_to_player(_body_point()) or _visible_to_player(dest)):
			return false  # it (or its post) is on screen — refuse rather than pop; the caller retries
		_stand_down()
		_teleport_to(dest)
		return true
	# Walk mode: standing down is enough — the GOAP Idle floor's return-to-post / wander re-centre owns the walk.
	_stand_down()
	return true


## May we TELEPORT right now, as opposed to standing down and walking back? Two HARD refusals that hold even when a
## designer has opened the leash up (they are not behind `off_screen_requires_calm` — that knob only paces the
## clock). Only the player-death reset overrides them, and that one runs on a fully black screen.
##
##   1. WE HAVE AGGRO. An NPC that is locked onto the player, hunting them, or merely holding them as a proximity
##      target it hasn't consciously noticed yet must NEVER vanish because the player broke line of sight. Ducking
##      behind a wall is a combat move, not a despawn button — an enemy that evaporates mid-encounter reads as the
##      game deleting the fight, which is worse than it standing around out of position. It can still stand down
##      and walk home (that IS what off_screen_requires_calm = false buys you); it just never pops.
##   2. WE'RE TOO CLOSE. See min_blink_distance — outside the view cone is not the same as unnoticeable.
func _may_blink() -> bool:
	if _engaged():
		return false
	return _flat_distance_to_player() >= maxf(0.0, min_blink_distance)


## Drop the current engagement through the host's public write seam so the GOAP Idle floor takes the wheel next
## tick. Duck-typed (host is Node-typed) and a no-op on a host that has no such seam.
func _stand_down() -> void:
	if host.has_method(&"stand_down"):
		host.call(&"stand_down")


## Where "home" is: the `home_marker` transform when one is wired, else the spot this NPC spawned at.
func home_position() -> Vector3:
	var marker := _home_node()
	if marker != null:
		return marker.global_position
	if host == null:
		return Vector3.ZERO
	var p: Vector3 = host.get(&"_spawn_position")
	if snap_home_to_navmesh and host.has_method(&"_snap_to_navmesh") and host.has_method(&"_height_above_floor"):
		# The snap lands ON the mesh (floor level); re-float it by our current height above ground so the body
		# rests on the surface instead of sinking into it — the same lift CompanionFollow's blink applies.
		p = host.call(&"_snap_to_navmesh", p, 3.0)
		p += Vector3.UP * float(host.call(&"_height_above_floor"))
	return p


## Which way this NPC faces once home: the marker's yaw when one is wired, else the yaw it spawned facing.
func home_yaw() -> float:
	var marker := _home_node()
	if marker != null:
		return marker.global_rotation.y
	return float(host.get(&"_spawn_yaw")) if host != null else 0.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not enabled or host == null:
		return
	if _death_due_msec >= 0:
		if Time.get_ticks_msec() < _death_due_msec:
			return
		_death_due_msec = -1
		if not return_home(death_return_ignores_view):
			# Refused (the post / the body is on screen). Hand the request to the off-screen path with its clock
			# already full, so it fires the instant the NPC is genuinely unobserved instead of being dropped.
			_off_screen_t = off_screen_delay
		return
	if not return_when_off_screen:
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	var step: float = maxf(0.05, scan_interval)
	_scan_t = step
	if not _eligible() \
			or (off_screen_requires_calm and _engaged()) \
			or _at_home() \
			or _visible_to_player(_body_point()):
		_off_screen_t = 0.0
		return
	_off_screen_t += step
	if _off_screen_t >= off_screen_delay and return_home(false):
		_off_screen_t = 0.0


## GameState.player_died handler — arm the delayed return. Nothing happens here directly: die() emits this from
## inside the player's own death teardown, so the actual teleport is deferred to _physics_process a beat later.
func _on_player_died() -> void:
	if not enabled or not return_on_player_death or not _eligible():
		return
	_death_due_msec = Time.get_ticks_msec() + int(maxf(0.0, death_return_delay) * 1000.0)


## Put the body at `dest` facing home, and clear the steering state that would otherwise drag it straight back out:
## the live velocity, the nav agent's stale route, the Locomotor's anti-stuck latches, and NpcLocomotion's roam
## destination (a wander point picked near the OLD spot). Mirrors CompanionFollow's blink landing.
func _teleport_to(dest: Vector3) -> void:
	host.global_position = dest
	var rot: Vector3 = host.rotation
	rot.y = home_yaw()
	host.rotation = rot
	host.velocity = Vector3.ZERO
	var nav: Variant = host.get(&"_nav")
	if nav is Object and is_instance_valid(nav):
		nav.target_position = dest  # re-seed the agent so it doesn't path back from where we just left
	_reset_child(host.get(&"_locomotor"))   # anti-stuck / give-up latches + the cached path
	_reset_child(host.get(&"_locomotion"))  # the stale wander destination + dwell


## Call reset_for_reuse() on a host child if it's a live node that has one. (Both callers above are per-life
## steering state whose reuse reset is exactly the "forget where you were going" we need here.)
func _reset_child(child: Variant) -> void:
	if child is Object and is_instance_valid(child) and child.has_method(&"reset_for_reuse"):
		child.call(&"reset_for_reuse")


## The wired `home_marker`, or null when there is none / it no longer resolves.
func _home_node() -> Node3D:
	if home_marker.is_empty() or not is_inside_tree():
		return null
	return get_node_or_null(home_marker) as Node3D


## Is this NPC a candidate for the leash at all? Exempts the dead, a recruited companion (its home is the player),
## a bodyguard on duty (it belongs with its VIP), a cutscene-driven body, and one mid walk-up to a conversation.
func _eligible() -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return false
	if bool(host.get(&"_dead")) or float(host.get(&"hp")) <= 0.0:
		return false
	if bool(host.get(&"_cutscene_control")):
		return false
	if host.has_method(&"is_following") and bool(host.call(&"is_following")):
		return false  # a companion's home is the player — CompanionFollow owns its own catch-up blink
	var vip: Variant = host.get(&"_guarding")
	if vip is Object and is_instance_valid(vip):
		return false  # a bodyguard stays beside its protectee, not at its spawn point
	var talk: Variant = host.get(&"_talk")
	if talk is Object and is_instance_valid(talk) and talk.has_method(&"is_approaching") \
			and bool(talk.call(&"is_approaching")):
		return false  # walking up to be framed for dialogue — let it finish
	# Belt-and-braces: an open conversation pauses the tree (so this rarely gets a chance to run), but the
	# player-death cue is signal-driven and Player.die() aborts dialogue before emitting, so hold anyway.
	return not DialogueManager.is_engaged()


## Does this NPC have AGGRO right now — anything it wants to fight, chase or run from? True while perception is
## past UNAWARE (spotting, locked on, or sweeping a lost trail) OR it still holds a live target. Both halves
## matter: NpcTargeting acquires by pure PROXIMITY with no line-of-sight test, so a hostile locks the player as
## `_target` the moment they're in sight_range — before perception has consciously noticed them. That
## not-yet-noticed window is still "wants to attack you", so it counts.
##
## Used twice, for different jobs: it paces the off-screen clock (when `off_screen_requires_calm`), and it HARD
## FORBIDS the teleport in `_may_blink()` regardless of that knob.
func _engaged() -> bool:
	var perception: Variant = host.get(&"_perception")
	if perception is Object and is_instance_valid(perception) and int(perception.state) != Perception.State.UNAWARE:
		return true
	var target: Variant = host.get(&"_target")
	return target is Object and is_instance_valid(target)


## Flat (horizontal) distance from this NPC to the human player, or INF when there is no player in the tree (a
## unit-test / headless scene) — INF passes every "far enough" gate, which is the right degradation when there is
## nobody who could notice the move.
func _flat_distance_to_player() -> float:
	if host == null or not host.is_inside_tree():
		return INF
	var player := Groups.human_player(host.get_tree())
	if player == null:
		return INF
	var here: Vector3 = host.global_position
	var there: Vector3 = player.global_position
	return Vector2(here.x - there.x, here.z - there.z).length()


## Already at its post? Horizontal distance only (a raised sentry is still at its post). A wanderer is "home"
## anywhere inside its own roam disc, so the leash never fights `wander_radius`.
func _at_home() -> bool:
	var home: Vector3 = home_position()
	var here: Vector3 = host.global_position
	var slack: float = maxf(0.0, home_slack)
	if bool(host.get(&"wanders")):
		slack = maxf(slack, float(host.get(&"wander_radius")))
	return Vector2(here.x - home.x, here.z - home.z).length() <= slack


## The point we test the NPC's own visibility at — its body origin (inside the capsule, so the occlusion ray
## terminates on its own collider when the line is clear).
func _body_point() -> Vector3:
	var here: Vector3 = host.global_position
	return here


## Can the player see `point` right now? Cone test against the player's camera first (cheap), then — when
## `occlusion_check` is on — one ray for solid geometry in between. No player / no camera => nobody can see it.
func _visible_to_player(point: Vector3) -> bool:
	var cam := _player_camera()
	if cam == null:
		return false
	var fwd := -cam.global_transform.basis.z  # Camera3D looks down -Z
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length_squared() < 0.0001:
		return true  # looking straight up / down — refuse to guess a "behind", treat as visible
	if not in_view_cone(cam.global_position, fwd_flat.normalized(), point, view_dot):
		return false
	if not occlusion_check:
		return true
	return not _occluded(cam.global_position, point)


## The human player's view camera, or null (no player yet, or a headless / unit-test tree). Same duck-typed
## `camera_effects` read CompanionFollow uses for its own on-screen guard.
func _player_camera() -> Camera3D:
	if host == null or not host.is_inside_tree():
		return null
	var player := Groups.human_player(host.get_tree())
	if player == null:
		return null
	var cam: Variant = player.get(&"camera_effects")
	if cam is Camera3D and is_instance_valid(cam):
		return cam as Camera3D
	return null


## Is something solid strictly between `from` and `to`? Hitting nothing (the point is in the open) or hitting the
## NPC's own body (a clear line right to it) both mean NOT occluded. Masks out the held-prop layer exactly as
## Perception's line-of-sight does, so a box the player is carrying in front of the camera never counts as a wall.
func _occluded(from: Vector3, to: Vector3) -> bool:
	var world := (host as Node3D).get_world_3d()
	if world == null or not world.space.is_valid():
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF & ~TalkHelpers.held_prop_collision_layer()
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return hit.get("collider") != host


## True if `point` sits inside the horizontal view cone from `cam_pos` looking along the (normalized, flattened)
## `fwd_flat` — i.e. roughly on screen. PURE (touches no state), so a bare `.new()` unit test can pin the geometry
## off-tree; deliberately NOT `static` so that dynamic `.call()` dispatch reaches it (a GDScript static function is
## not in an instance's method list, so `instance.in_view_cone(...)` on an untyped ref fails at runtime — which is
## exactly how GUT and any duck-typed caller would reach it). Same dot-vs-threshold rule as
## CompanionFollow._in_view_cone and PropFollow; kept local rather than shared because those two are welded to
## their own hosts.
func in_view_cone(cam_pos: Vector3, fwd_flat: Vector3, point: Vector3, dot_threshold: float) -> bool:
	var to_point := point - cam_pos
	to_point.y = 0.0
	if to_point.length_squared() < 0.0001:
		return true  # right on top of the camera — treat as visible (refuse the blink)
	return fwd_flat.dot(to_point.normalized()) >= dot_threshold


func _get_configuration_warnings() -> PackedStringArray:
	var parent := get_parent()
	if parent == null or not parent.has_method(&"send_home"):
		return PackedStringArray(["NpcHomeReturn must be a child of an NPC — it sends that NPC back to its post when the player dies or after it has been off-screen."])
	if not home_marker.is_empty() and is_inside_tree() and get_node_or_null(home_marker) == null:
		return PackedStringArray(["home_marker does not resolve to a node — clear it to use the NPC's spawn position as home."])
	return PackedStringArray()
