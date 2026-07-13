@tool
class_name Locomotor
extends Node

## Drop-in PATHFINDING + LOCOMOTION for any CharacterBody3D. Attach it under a CharacterBody3D, call move_to(pos),
## and it routes there on the baked navmesh — RVO-avoiding other agents / dynamic obstacles, applying gravity, and
## (optionally) turning to face travel. It OWNS its own NavigationAgent3D (parented to the body, so the agent
## navigates from the body's position) and, in the default AUTONOMOUS mode, drives the body itself (gravity +
## move_and_slide) each physics frame — drop it on a bare mob and it just moves. Set drive_body = false for DRIVEN
## mode: it only COMPUTES steering into `desired_velocity` and the host runs its own move_and_slide + RVO (the NPC
## path — it calls drive_move_to() + update_stuck() and reads desired_velocity; see scripts/npc/README.md).
##
## All host reads are duck-typed — get_parent() as CharacterBody3D for the body, and optional move_speed / move_accel
## / air_accel / turn_speed via get() with @export fallbacks — so it never hard-depends on a script type (the
## LocomotionFx idiom). It needs a baked NavigationRegion3D in the level (the same one NPCs path on); every nav-map
## query is gated on NavigationUtils.is_nav_map_ready so a freshly-loaded / re-baked map never errors ("query made
## before first map synchronization") — see the memory note nav-map-query-before-sync.
##
## DRIVEN mode also carries the NPC's full pursuit brain (lifted from npc.gd in the Phase B migration): the combat
## nav-hop (jump to reach a perched target), the anti-stuck / wall-slide give-up machine (update_stuck), and off-mesh
## recovery. The host calls drive_move_to() + update_stuck() each physics frame and reads desired_velocity; a bare
## AUTONOMOUS mob still just move_to()s and we drive it ourselves (the hop stays gated off via allow_hop=false).

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

# --- Anti-stuck / nav-hop tuning (portable copies; NPC aliases these so NPC.STUCK_TIME etc. stay the same values). ---
# Lifted from npc.gd's nav cluster in the Locomotor Phase B migration. These are the SINGLE SOURCE OF TRUTH for the
# behaviour; npc.gd declares `const STUCK_TIME := Locomotor.STUCK_TIME` (aliases) so its tests still read NPC.<CONST>.
const STUCK_SPEED_FRAC := 0.35  ## actual horizontal speed below this fraction of the intended = "blocked"
const STUCK_TIME := 0.35        ## seconds blocked (pressed against something while trying to move) before steering
const UNSTICK_TIME := 0.7       ## seconds to veer along the blocker to slip free
const STUCK_GIVEUP_TIME := 2.0  ## after this long trying-but-not-moving, STOP shuffling and just hold (anti-pacing)
const STUCK_HOLD_TIME := 1.5    ## seconds to stand still after giving up, before trying the move again
const OFF_MESH_RECOVER_DIST := 1.5  ## if we're this far OFF the baked navmesh (knocked off / fell), steer back onto it
const JUMP_COOLDOWN := 0.8      ## min seconds between nav-driven hops, so one ledge/link climb can't machine-gun into a bounce
const HOP_MIN_CLIMB := 0.6      ## ignore curb/stair-sized vertical deltas; only vault real low ledges/crates
const HOP_STEP_DISTANCE := 1.5  ## horizontal distance from the step/raised target required before a hop can fire
const HOP_HEIGHT_MARGIN := 0.2  ## extra apex clearance so a height-matched hop reaches past the lip/player floor

## OPTIONAL injected agent: when a host (the NPC) already owns a NavigationAgent3D — because other systems read
## host._nav (CompanionFollow) — it hands that agent here BEFORE _ready() and we use it instead of building a second.
## Two live agents on one body = double RVO registration; injection keeps ONE. Leave null for a bare mob (we build one).
var external_nav: NavigationAgent3D = null

## This frame's steering result (world space, horizontal, y = 0) — the RAW nav-follow velocity BEFORE RVO. In
## autonomous mode we RVO-blend + apply it; in driven mode the host reads it and does its own RVO (as npc.gd already does).
var desired_velocity: Vector3 = Vector3.ZERO

var _nav: NavigationAgent3D
var _has_target: bool = false
var _arrived: bool = true          ## latched so reached_target fires once per destination
var _blocked_notified: bool = false  ## latched so path_blocked fires once per destination
var _avoid_velocity: Vector3 = Vector3.ZERO
var _avoid_ready: bool = false     ## false until the first velocity_computed callback -> fall back to the raw desired

# --- Anti-stuck / nav-hop STATE (lifted from npc.gd). In DRIVEN mode the host consumes _unstick_t / _unstick_dir in
# its apply_velocity, and calls update_stuck() as the LAST move step. _stranded_cycles is NOT here — it stays on the
# host (soak_harness reads host._stranded_cycles); we call host._tick_stranded(pos) which owns that counter.
var _stuck_t: float = 0.0
var _unstick_t: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO
var _stuck_persist: float = 0.0
var _stuck_hold_t: float = 0.0
var _jump_cd: float = 0.0
var _hopping: bool = false
## _hopped_this_frame is true ONLY on the tick a hop actually fires — the "still travelling" bool (drive_move_to) reads
## THIS, not the persistent airborne _hopping latch, so give-up-hold + arrived frames read "not travelling" even while
## _hopping is still latched from a prior tick (a futile-pogo give-up must not report "moving").
var _hopped_this_frame: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only _get_configuration_warnings runs in the editor; never build nav / drive the body there
	var body := get_parent() as CharacterBody3D
	if body == null:
		return  # nothing to move (the config warning already tells the designer) — stay inert
	# INJECTED agent wins: an NPC hands us its own _nav (which CompanionFollow / soak read) so there's ONE agent on
	# the body, not two fighting over RVO. Its velocity_computed is already wired to the HOST's _on_avoidance_velocity,
	# so in driven mode the host reads its own _avoid_velocity — we never touch RVO in driven mode anyway.
	if external_nav != null:
		_nav = external_nav
		return
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
	# DRIVEN mode (the NPC): the host drives us via drive_move_to() + update_stuck() from its own move loop, so we do
	# NOTHING here — running the brain again would double-fire the hop and clobber _arrived. Autonomous only below.
	if not drive_body:
		return
	var body := get_parent() as CharacterBody3D
	if body == null:
		return
	# Autonomous (a bare mob): no hop / hop_target, flat scaled speed via the host tuning.
	desired_velocity = _compute_desired(body, _host_move_speed(body), false, null)
	_drive(body, delta)
	if face_travel and desired_velocity.length_squared() > 0.0001:
		_face(body, delta)

## The raw nav-follow velocity toward the current target (no RVO — that's applied in _drive / by the host). ZERO when
## there's no target, we've arrived (fires reached_target), or the map hasn't synced yet. In DRIVEN mode (the NPC) this
## is the full pursuit brain: give-up hold, off-mesh recovery, straight-line charge through an unreachable target, and
## the combat nav-hop (which writes body.velocity.y directly — a knowing side-effect on the driven body).
##
## `speed` is the host's fully-scaled move speed (host._current_move_speed(): stance×limb×encumbrance×agility×status)
## when the host exposes it, else the flat move_speed export. `allow_hop` / `hop_target` come from the caller (combat /
## search / follow pass allow_hop=true; idle/patrol/civilian keep it false so a civilian never pogos at you).
func _compute_desired(body: CharacterBody3D, speed: float, allow_hop: bool, hop_target: Node3D) -> Vector3:
	if not _has_target:
		return Vector3.ZERO
	# Given up (blocked too long — see update_stuck): report "can't get there" so the host holds. In driven mode the
	# host reads is_moving()==false via this ZERO + returns false from its _move_toward shell (wanderer re-picks).
	if _stuck_hold_t > 0.0:
		_arrived = true  # so the host's _move_toward shell reads "not travelling" while we hold
		return Vector3.ZERO
	var target: Vector3 = _nav.target_position
	var self_pos := body.global_position
	var to_target := target - self_pos
	var target_flat_distance := Vector2(to_target.x, to_target.z).length()
	var target_climb := _hop_target_climb(body, target, hop_target)
	# Off-navmesh RECOVERY: once clearly struggling (_stuck_persist), if we've ended up OFF the baked mesh (knocked off
	# a ledge / walked off chasing), steer for the nearest ON-mesh point so we walk back onto walkable floor. Gated on
	# _stuck_persist so healthy NPCs never run the query; ALSO gated on map-ready because map_get_closest_point ERRORS
	# before the first sync — it's the ONLY pre-sync-unsafe call here, so the main pursuit path below still runs pre-sync
	# exactly as live npc.gd did (a blanket pre-sync hold would be a behaviour change, not an equivalence).
	if _stuck_persist > 0.5 and body.is_inside_tree() and NavigationUtils.is_nav_map_ready(_nav.get_navigation_map()):
		var nav_map := _nav.get_navigation_map()
		var nearest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, self_pos)
		var off := nearest - self_pos
		if off.length() > OFF_MESH_RECOVER_DIST:
			var flat := Vector3(off.x, 0.0, off.z)
			if flat.length() > 0.1:
				_arrived = false
				return flat.normalized() * speed
	# Branch precedence MATCHES the old npc._move_toward three-way: is_navigation_finished() is the INNER discriminant and
	# reachability is only consulted ONCE finished. Do NOT invert it (checking reachability first) — for an unreachable
	# target that changes both the path taken (approach: partial navmesh route vs straight-charge-into-walls) and the
	# arrival behaviour (at the rim: commit off the edge still moving, vs halt + report arrived).
	var to_next: Vector3
	if not _nav.is_navigation_finished():
		# NOT finished: follow the baked navmesh path (routes around walls). Runs for ANY not-finished frame regardless of
		# reachability — for an unreachable target this walks the PARTIAL path toward the nearest reachable point.
		to_next = _nav.get_next_path_position() - self_pos
		if Vector2(to_next.x, to_next.z).length() < 0.05:
			# Path won't advance (missing/floating/disconnected navmesh under us): head straight so pursuit still works.
			to_next = to_target
	elif not _nav.is_target_reachable():
		# Finished the partial path but the target itself is OFF-mesh (a disconnected island / a ledge you dropped onto):
		# COMMIT and charge straight at it, walking off the edge if pursuit demands it so pursuit never stalls at the rim.
		# Fire path_blocked once as a diagnostic (inert — nothing on the NPC connects it).
		if not _blocked_notified:
			_blocked_notified = true
			path_blocked.emit()
		to_next = to_target
		if target_flat_distance < 0.5 and not _try_hop(body, target_climb, target_flat_distance, allow_hop):
			_arrived = true
			return Vector3.ZERO
	else:
		# Genuinely arrived (finished + reachable): one last hop if a raised target sits right on top of us, else stop +
		# fire reached_target once.
		if _try_hop(body, target_climb, target_flat_distance, allow_hop):
			return Vector3.ZERO  # hop consumed this frame; horizontal handled next frame
		if not _arrived:
			_arrived = true
			reached_target.emit()
		return Vector3.ZERO
	_arrived = false
	var climb := to_next.y
	to_next.y = 0.0
	var hop_climb := climb
	var hop_horizontal := to_next.length()
	if target_flat_distance < HOP_STEP_DISTANCE and target_climb > hop_climb:
		hop_climb = target_climb
		hop_horizontal = target_flat_distance
	# Hop up toward a higher target the navmesh can't route onto (you on a crate/ledge, or a baked ledge). Launch SCALES
	# to the target height (jump_velocity_for_climb) so the NPC reaches your feet. Writes body.velocity.y directly — the
	# knowing driven-mode side-effect. Gated to threatening pursuit (allow_hop); is_on_floor + cooldown + proximity stop
	# a machine-gun climb. A futile pogo counts as "trying" in update_stuck (_hopping) so it converts to give-up + hold.
	var hop_velocity: float = _host_jump_velocity(body)
	if should_nav_hop(allow_hop, hop_velocity, body.is_on_floor(), _jump_cd, hop_climb, hop_horizontal):
		body.velocity.y = jump_velocity_for_climb(hop_climb, body.get_gravity().y, hop_velocity)
		_jump_cd = JUMP_COOLDOWN
		_hopping = true
		_hopped_this_frame = true
	if to_next.length() < 0.05:
		_arrived = true
		return Vector3.ZERO
	return to_next.normalized() * speed

## Vertical climb from our capsule bottom to the target's (a raised target -> positive). Mirrors npc._nav_hop_target_climb.
func _hop_target_climb(body: CharacterBody3D, target: Vector3, hop_target: Node3D) -> float:
	var target_floor: float = collision_bottom_y(hop_target, target.y) if is_instance_valid(hop_target) else target.y
	var self_floor: float = collision_bottom_y(body, body.global_position.y)
	return target_floor - self_floor

## One-shot hop attempt (arrived / straight-line-close cases). Writes body.velocity.y + arms the cooldown/latch. Mirrors
## npc._try_nav_hop. Returns true when it fired.
func _try_hop(body: CharacterBody3D, climb: float, horizontal_distance: float, allow_hop: bool) -> bool:
	var hop_velocity: float = _host_jump_velocity(body)
	if not should_nav_hop(allow_hop, hop_velocity, body.is_on_floor(), _jump_cd, climb, horizontal_distance):
		return false
	body.velocity.y = jump_velocity_for_climb(climb, body.get_gravity().y, hop_velocity)
	_jump_cd = JUMP_COOLDOWN
	_hopping = true
	_hopped_this_frame = true
	return true

## DRIVEN-mode entry the host calls each frame (instead of us running _physics_process autonomously). Computes the
## desired velocity toward `target` with full pursuit logic. Returns TRUE while still travelling, FALSE when arrived /
## given-up (the exact bool contract npc.gd's _move_toward callers branch on). Reads host._current_move_speed() for the
## scaled speed. host is a duck-typed Node — every host.<x> read is annotated (Variant), never `:=` (INVARIANT 5).
func drive_move_to(target: Vector3, allow_hop: bool, hop_target: Node3D) -> bool:
	if _nav == null:
		return false
	move_to(target)
	var body := get_parent() as CharacterBody3D
	if body == null:
		return false
	_hopped_this_frame = false  # a hop that fires this call re-sets it in _compute_desired / _try_hop
	var speed: float = _host_move_speed(body)
	desired_velocity = _compute_desired(body, speed, allow_hop, hop_target)
	# "Still travelling?" = we produced steering OR a hop fired THIS frame. Arrived / given-up-hold -> false so the
	# caller re-picks / holds, even while the airborne _hopping latch is still set from a prior tick.
	return desired_velocity.length_squared() > 0.0001 or _hopped_this_frame

## Host's fully-scaled move speed (stance×limb×encumbrance×agility×status) when it exposes _current_move_speed(), else
## the flat move_speed tuning. `has_method`+`call` keeps this a duck-typed drop-in (no NPC type dependency).
func _host_move_speed(body: Node) -> float:
	if body.has_method(&"_current_move_speed"):
		var v: Variant = body.call(&"_current_move_speed")
		if v is float or v is int:
			return float(v)
	return _tuning(body, &"move_speed", move_speed)

## Host's jump_velocity export (the hop's base pop / disable-at-0), duck-typed. 0 -> hopping disabled for this host.
func _host_jump_velocity(body: Node) -> float:
	return _tuning(body, &"jump_velocity", 0.0)

## Anti-stuck STATE MACHINE — the host calls this LAST in its move step (after move_and_slide), so get_slide_collision*
## and is_on_floor reflect this frame's contacts. Lifted verbatim from npc._update_stuck; every host.<x> is annotated.
## Writes _unstick_t / _unstick_dir that the host's apply_velocity consumes NEXT frame, and calls host._tick_stranded
## (which owns _stranded_cycles — soak_harness reads host._stranded_cycles).
func update_stuck(body: CharacterBody3D, delta: float) -> void:
	if _unstick_t > 0.0:
		_unstick_t -= delta
	if _jump_cd > 0.0:
		_jump_cd -= delta
	if _stuck_hold_t > 0.0:
		_stuck_hold_t -= delta
	if body.is_on_floor():
		_hopping = false
	var intended := Vector2(desired_velocity.x, desired_velocity.z).length()
	var blast_len: float = _host_blast_len(body)  # explosion_velocity.length() on Character, else 0 for a bare mob
	if intended < 0.1 or (not body.is_on_floor() and not _hopping) or blast_len > 1.0:
		_stuck_t = 0.0
		_stuck_persist = 0.0
		return
	if Vector2(body.velocity.x, body.velocity.z).length() >= intended * STUCK_SPEED_FRAC:
		_stuck_t = 0.0
		_stuck_persist = 0.0
		if body.has_method(&"_reset_stranded"):
			body.call(&"_reset_stranded")  # made progress -> host clears its _stranded_cycles / _stranded_warned
		return
	_stuck_persist += delta
	if _stuck_persist >= STUCK_GIVEUP_TIME:
		_stuck_persist = 0.0
		_stuck_t = 0.0
		_unstick_t = 0.0
		_stuck_hold_t = STUCK_HOLD_TIME
		if body.has_method(&"_note_stranded"):
			body.call(&"_note_stranded")  # host-side diagnostic (owns _stranded_cycles / display_name / global_position)
		return
	if not _nav.is_target_reachable():
		_stuck_t = 0.0
		return
	var wall_normal := Vector3.ZERO
	for i in body.get_slide_collision_count():
		var n := body.get_slide_collision(i).get_normal()
		if absf(n.y) < 0.7:
			wall_normal = n
			break
	if wall_normal == Vector3.ZERO:
		_stuck_t = 0.0
		return
	_stuck_t += delta
	if _stuck_t < STUCK_TIME:
		return
	_stuck_t = 0.0
	var want := Vector3(desired_velocity.x, 0.0, desired_velocity.z).normalized()
	_unstick_dir = wall_slide_dir(wall_normal, want)
	_unstick_t = UNSTICK_TIME

## Character.explosion_velocity length (a live blast) if the host has one, else 0. Duck-typed so a bare mob (no blast)
## reads neutral. `: Vector3` NOT `:=` — host.get returns Variant (INVARIANT 5).
func _host_blast_len(body: Node) -> float:
	var v: Variant = body.get(&"explosion_velocity")
	if v is Vector3:
		return (v as Vector3).length()
	return 0.0

# --- Pure nav-hop / wall-slide statics (lifted from npc.gd; NPC keeps forwarding shells so NPC.<static> still resolves
# for the tests). No host reads -> no := trap; safe verbatim. ---

## Upward velocity for a hop to land `climb` m above us; base_velocity is the minimum pop, a taller target scales up.
static func jump_velocity_for_climb(climb: float, grav: float, base_velocity: float) -> float:
	var base := maxf(base_velocity, 0.0)
	var g := absf(grav)
	if climb <= 0.0 or g <= 0.0:
		return base
	return maxf(base, sqrt(2.0 * g * (climb + HOP_HEIGHT_MARGIN)))

## Pure nav-hop gate: threatening + grounded + off-cooldown + a real nearby climb. No upper bound (launch scales).
static func should_nav_hop(allow_hop: bool, hop_velocity: float, on_floor: bool, jump_cooldown: float, climb: float, horizontal_distance: float) -> bool:
	if not allow_hop or hop_velocity <= 0.0 or not on_floor or jump_cooldown > 0.0:
		return false
	return climb > HOP_MIN_CLIMB \
			and horizontal_distance < HOP_STEP_DISTANCE

## Bottom Y of a character capsule (the CollisionShape3D itself or a direct child); fallback_y for a plain Vector3 target.
static func collision_bottom_y(node: Node3D, fallback_y: float) -> float:
	if not is_instance_valid(node):
		return fallback_y
	var col := node as CollisionShape3D
	if col != null:
		return _collision_shape_bottom_y(col, fallback_y)
	for c in node.get_children():
		col = c as CollisionShape3D
		if col != null:
			return _collision_shape_bottom_y(col, fallback_y)
	return fallback_y

static func _collision_shape_bottom_y(col: CollisionShape3D, fallback_y: float) -> float:
	var cap := col.shape as CapsuleShape3D
	if cap == null:
		return fallback_y
	return (col.global_position - col.global_basis.y * (cap.height * 0.5)).y

## Pure steering math: wall tangent toward the goal (the side with non-negative dot to `want`).
static func wall_slide_dir(wall_normal: Vector3, want: Vector3) -> Vector3:
	var tangent := Vector3(-wall_normal.z, 0.0, wall_normal.x).normalized()
	return tangent if tangent.dot(want) >= 0.0 else -tangent

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
