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
## RVO agent radius (m) — how wide a berth it gives other agents + dynamic obstacles when steering around them. This is
## the ORCA avoidance disc ONLY: it does not narrow the baked path corridor and is unrelated to the navmesh's bake-time
## agent_radius. Widen it for a bulkier mob that should be given more room. Ignored when a host injects `external_nav`
## (that agent is configured by its host — the NPC path).
@export var agent_radius: float = 0.6
## Explicit override for the agent's `path_height_offset` (see apply_path_height_offset). 0 = DERIVE it from the host's
## capsule, which is what you want. Set it only for a host whose collision bottom isn't where its path should be read
## (a hovering drone, a body whose capsule doesn't reach the floor). Must be NEGATIVE to raise the path toward the origin.
@export var path_height_offset_override: float = 0.0
## Re-issuing the SAME destination to a NavigationAgent3D forces a fresh A* query, and drive_move_to() calls move_to()
## every physics frame — so an unguarded write re-paths the whole map per NPC per tick, and (once paths actually run)
## re-fires `link_reached` every frame while an agent sits on a link. Only submit a destination that moved more than
## this many metres. Raise it to path less often for a fast-moving target; 0 restores the per-frame re-path.
@export var repath_epsilon: float = 0.25
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
const CHASE_STUCK_GIVEUP_TIME := 3.2  ## hop-capable pursuit gets longer before it stops trying; ledges/corners need persistence
const CHASE_STUCK_HOLD_TIME := 0.35   ## hop-capable pursuit only pauses briefly, then presses the chase again
# Anti-pacing BACKSTOP thresholds (net-displacement give-up). STUCK_SPEED_FRAC above gates on instantaneous SPEED, so a
# wall-slide sidestep — full lateral speed, ~zero net progress — reads as "moving" and keeps resetting the give-up timer,
# and the NPC then paces a blocker (an un-carved / movable / AVOID-mode prop, or a TrenchBroom brush the path routes
# through) FOREVER. These add an independent "did we actually get anywhere over a window" test so the give-up hold fires.
const PROGRESS_WINDOW := 2.0        ## seconds still trying to move but going nowhere before the backstop gives up
const PROGRESS_MIN_TRAVEL := 0.6    ## min net horizontal metres over PROGRESS_WINDOW to count as real progress (below = churning)
const PROGRESS_FAIL_GIVEUP := 2     ## consecutive net-progress windows going nowhere before a HOP-CAPABLE chaser also gives up (else it pogos a tall blocker forever and never strands/diagnoses)
const OFF_MESH_RECOVER_DIST := 1.5  ## if we're this far OFF the baked navmesh (knocked off / fell), steer back onto it
const JUMP_COOLDOWN := 0.8      ## min seconds between nav-driven hops, so one ledge/link climb can't machine-gun into a bounce
const HOP_MIN_CLIMB := 0.6      ## ignore curb/stair-sized vertical deltas; only vault real low ledges/crates
const HOP_STEP_DISTANCE := 1.5  ## horizontal distance from the step/raised target required before a hop can fire
const HOP_HEIGHT_MARGIN := 0.2  ## extra apex clearance so a height-matched hop reaches past the lip/player floor
const STUCK_HOP_TIME := 0.45    ## hop-capable pursuit blocked this long tries a recovery vault before giving up
const LEDGE_PROBE_AHEAD := 0.5   ## how far PAST the agent's radius to sample the drop ahead (m) — just beyond the lip
const LEDGE_PROBE_MARGIN := 0.5  ## extra probe depth below max_pursuit_drop so a drop AT the limit still registers a floor
const UNREACHABLE_CLOSE_STOP_DISTANCE := 0.5  ## close enough to stop at same-level / upward unreachable targets
const LOWER_TARGET_PARTIAL_END_DISTANCE := 1.0  ## close enough to a partial path's rim endpoint to commit off
const LOWER_PATH_DROP_COMMIT_DISTANCE := 1.8  ## lower path point this close means "at the rim; jump/commit now"
const LOWER_TARGET_DIRECT_DROP_DISTANCE := 4.0  ## close lower combat target: ignore rim path shuffling and drop after it

# --- STAIR STEP-UP tuning (see enable_step_up / try_step_up). Mirrors the Player's constants (player.gd) so an NPC
# steps the same brush stairs the player does. A CharacterBody3D can't climb a vertical riser on its own — move_and_slide
# is stopped dead by it — so this test_move-based probe snaps the body up a riser it's pressing into. HOP_MIN_CLIMB (0.6)
# is the clean boundary: step-up handles risers <= step_up_height (~0.5 m stairs), the combat hop vaults taller ledges. ---
const STEP_UP_CLEARANCE := 0.04         ## headroom margin added above step_up_height when probing for a clear lift
const STEP_MIN_DELTA := 0.015           ## a rise smaller than this isn't worth a step (noise / already-grounded)
const STEP_MIN_FORWARD_PROBE := 0.18    ## min forward probe distance (m) so a slow/near-stalled body still finds the tread
const STEP_MAX_ANGLED_PROBE_EXTRA := 0.22  ## extra into-riser probe for diagonal stair approaches (mirrors Player)
const STEP_RISER_NORMAL_Y_MAX := 0.35    ## riser collision must be mostly vertical; floors/slopes are not risers
const STEP_MIN_RISER_DOT := 0.05         ## horizontal motion must actually be pressing into the riser
const STEP_UPWARD_VELOCITY_EPS := 0.01  ## only step when NOT already rising (a jump/hop owns the vertical; don't fight it)
const STEP_DOWN_MIN_SPEED := 0.1        ## min horizontal speed (m/s) before the descending-tread catch engages

## Link traversal (author-placed NavLink). UP links inject a launch sized to reach the exit; DOWN links inject a short
## horizontal commit so the CharacterBody physically steps over the rim instead of rubbing against the link entry.
## DECOUPLED from the combat allow_hop gate: an authored link is an explicit "traverse here", so IDLE / civilian NPCs
## climb/drop too. link_climb_velocity is the base pop (a taller link scales the launch up); set it to 0 to disable link
## ascent for a host (it can still DROP down links).
@export var link_climb_velocity: float = 4.5
## Ignore near-flat links the bake already bridges (agent_max_climb ~0.4) — only launch for a real upward span.
@export var link_climb_min: float = 0.4
## Ceiling (m) on the anti-stuck RECOVERY vault's launch height (_try_stuck_recovery_hop). That hop fires on sustained
## no-progress WITHOUT the combat hop's proximity gate, so it must not size itself to a far-off, storeys-high target —
## it only has to clear the blocker under the body's nose. The proximity-gated combat hop (should_nav_hop) is still
## free to scale its launch to any height. Raise this only if NPCs fail to vault a genuinely tall nearby obstacle.
@export var recovery_hop_max_climb: float = 1.2
const LINK_DESCENT_COMMIT_TIME := 0.6   ## seconds to keep driving forward across a down ledge after commit arms
const LINK_ASCENT_COMMIT_MAX_TIME := 1.1  ## cap for forced forward drive across long up/stair links
const LEDGE_DROP_HOP_VELOCITY := 4.2    ## decisive hop that unsticks the capsule from the rim while it moves forward
const LEDGE_DROP_FORWARD_MULT := 1.75   ## extra horizontal drive so the body clears the lip instead of bouncing back
const LINK_ASCENT_FORWARD_MULT := 1.25  ## gentler forced drive for upward/stair links: commit forward without overshooting

## FALL-SAFETY for the off-ledge pursuit commit. When the nav path can't REACH the target (a disconnected lower
## island — chiefly YOU, after you dropped off a ledge) the driven brain COMMITS off the rim and charges straight,
## which is exactly how an NPC follows you down (descent is flatten + gravity, no launch — verified). This caps how
## DEEP a drop it will willingly leap off: a down-probe just past the lip refuses the step-off when the floor ahead is
## more than max_pursuit_drop below (or bottomless), so an enemy chases you off a balcony but NOT off a cliff / into a
## pit. Only bites while GROUNDED at the rim — once airborne (already committed to a probe-cleared drop) the fall
## finishes. A deliberately-authored NavLink makes such a target REACHABLE, so this commit branch never runs there:
## big intentional drops are the NavLink's job. Set <= 0 to disable the gate (always commit — the pre-gate behaviour).
@export var max_pursuit_drop: float = 4.0

## STAIR STEP-UP (opt-in; npc.gd turns it on, a bare mob leaves it off). A CharacterBody3D is stopped dead by a vertical
## stair riser — move_and_slide never climbs one — which is why the Player has its own _try_step_up and, without an
## equivalent here, NPCs can't use brush stairs (0.5 m risers > the navmesh's agent_max_climb 0.4, so the flight bakes as
## disconnected islands AND the body can't physically mount a step). With this on, the host calls try_step_up/try_step_down
## from its move loop (around move_and_slide) and the body auto-steps risers up to step_up_height, exactly like the player.
## NOTE: step-up only handles the PHYSICAL climb. For an NPC to be ROUTED onto a staircase between two floors, drop a
## WALK-mode NavLink across the flight (a > agent_max_climb flight still bakes as disconnected islands A* won't cross).
@export var enable_step_up: bool = false
## Max riser height (m) the body auto-steps. Match the level's stair riser + a small margin (this project's 0.5 m brush
## risers -> 0.6). Above this, a real ledge is the combat hop's job (HOP_MIN_CLIMB), not step-up.
@export var step_up_height: float = 0.6
## Downward snap (m) applied after a step + the descending-tread catch (try_step_down). Keep >= step_up_height so a body
## walking DOWN stairs stays grounded on each tread instead of launching off the nosing (mirrors PlayerMovement.step_down_snap).
@export var step_down_snap: float = 0.65

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
var _link_descent_t: float = 0.0
var _link_descent_dir: Vector3 = Vector3.ZERO
var _link_drive_mult: float = LEDGE_DROP_FORWARD_MULT
## _hopped_this_frame is true ONLY on the tick a hop actually fires — the "still travelling" bool (drive_move_to) reads
## THIS, not the persistent airborne _hopping latch, so give-up-hold + arrived frames read "not travelling" even while
## _hopping is still latched from a prior tick (a futile-pogo give-up must not report "moving").
var _hopped_this_frame: bool = false
# Anti-pacing BACKSTOP state (see PROGRESS_WINDOW). Measures NET body displacement over a rolling window so a wall-slide's
# lateral speed can't masquerade as progress. Seeded on the first trying-to-move frame; the not-trying early-return in
# update_stuck un-seeds it so a standing / hopping / blasted NPC never accrues "went nowhere".
var _progress_t: float = 0.0               ## seconds accumulated in the current net-progress window
var _progress_ref: Vector3 = Vector3.ZERO  ## body position at the window start — the net-displacement anchor
var _progress_seeded: bool = false         ## false until the first trying-to-move frame seeds _progress_ref
var _progress_fail_count: int = 0          ## consecutive PROGRESS_WINDOWs under PROGRESS_MIN_TRAVEL; a hop-capable chaser gives up at PROGRESS_FAIL_GIVEUP
var _target_submitted: bool = false        ## false until move_to has written target_position at least once this "trip" (see move_to / repath_epsilon)
var _last_allow_hop: bool = false          ## last driven move was a hostile/search pursuit that may jump to keep chasing
var _last_target_climb: float = 0.0         ## target floor delta from the last drive_move_to, used by stuck recovery hops
var last_step_rise: float = 0.0            ## vertical rise the most recent try_step_up() applied (0 = didn't step); host reads it to visually ease the instant riser snap

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
		apply_path_height_offset(body)  # the injected agent needs the feet correction too — see the func doc
		_connect_link_signal()  # the injected NPC agent still drives the link-ascent hop
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
	apply_path_height_offset(body)
	_connect_link_signal()

## THE FEET CORRECTION — without this an agent NEVER advances its path index, and nothing here ever follows a path.
##
## A NavigationAgent3D advances to the next path waypoint when the 3D distance from its PARENT's origin to that
## waypoint drops under path_desired_distance (0.5). Baked path vertices lie on the FLOOR, but a character's origin
## sits at its capsule CENTRE — on this project's NPC capsule (enemy.tscn: height 1.95, shape offset y -0.028) the
## origin floats 1.0034 m above the feet. So the distance has a hard FLOOR of ~1.0 m against a 0.5 m threshold: the
## index is pinned at 0 forever and get_next_path_position() keeps returning the point directly UNDER us. `to_next`
## then comes out near-vertical, so its FLAT length hovers right at the 0.05 m threshold of the "path won't advance ->
## head straight" emergency fallback — and the body OSCILLATES across it, one frame charging the destination and the
## next steering back at path[0] behind it, at full walk speed, netting ~zero. That fallback was written as a last
## resort for a missing navmesh; before this fix it was the only branch any host ever took. Worse, the per-frame speed
## check in update_stuck sees full speed and keeps resetting the stuck timers, so only the PROGRESS_WINDOW
## net-displacement backstop catches it: give up -> hold -> twitch again. Measured, same route, same Locomotor:
##
##   f0  flat=0.000 -> fallback   desired=( 0.21, 0,  3.99)
##   f1  flat=0.067 -> path[0]    desired=(-0.21, 0, -3.99)   ... repeating forever
##
## `path_height_offset` is Godot's remedy: it is SUBTRACTED from each path vertex's y, so it must be NEGATIVE to lift
## the path up to the agent origin. We derive it from the body's own capsule (collision_bottom_y, the same helper the
## hop math uses) rather than hardcoding a number, so any host — a taller mob, a crouched NPC, a differently-authored
## prefab — self-corrects. A host with no capsule degrades to 0 (unchanged behaviour). `path_height_offset_override`
## wins when non-zero, for a host whose visual feet aren't its collision bottom.
##
## A/B on the live level's real 2529-poly bake, a 25 m 7-waypoint route, identical Locomotor, only the offset differing:
##   offset  0.0000  -> max path index 0, travelled 25.00 -> 25.03 m in 600 frames (no net progress)
##   offset -1.0034  -> max path index 6, travelled 25.00 ->  0.99 m in 362 frames (arrived)
func apply_path_height_offset(body: CharacterBody3D) -> void:
	if _nav == null or body == null:
		return
	if not is_zero_approx(path_height_offset_override):
		_nav.path_height_offset = path_height_offset_override
		return
	# Negative = raise the path to the origin. collision_bottom_y returns the fallback (our own y) when the host has no
	# capsule, which yields 0.0 — i.e. "leave the engine default alone" rather than guessing.
	_nav.path_height_offset = collision_bottom_y(body, body.global_position.y) - body.global_position.y

## Connect the agent's link_reached ONCE (guarded) so an authored NavLink fires the ascent hop. For the INJECTED NPC
## agent this connection persists across NpcPool reuse (agent + Locomotor survive) — reset_for_reuse must NOT re-connect
## it (a double connection double-fires the launch). link_reached is otherwise unclaimed; velocity_computed stays wired
## to the host in driven mode, so there's no conflict.
func _connect_link_signal() -> void:
	if _nav != null and not _nav.link_reached.is_connected(_on_link_reached):
		_nav.link_reached.connect(_on_link_reached)

## NPC-pooling reuse reset (NpcPool): zero every per-life steering/anti-stuck latch so a reused NPC starts
## stationary and un-stuck. Touches FIELDS ONLY — it must NOT rebuild _nav, null external_nav, or re-connect
## velocity_computed (that would double-register RVO / double-fire the callback). The injected _nav persists
## across reuse (the NPC keeps its one agent); the next drive_move_to()/move_to() re-seeds the route. The link traversal
## driver (_on_link_reached) reuses the hop latches for UP links and owns a tiny DOWN-link commit timer, all zeroed below;
## the link_reached connection is likewise NOT re-touched.
func reset_for_reuse() -> void:
	desired_velocity = Vector3.ZERO
	_has_target = false
	_arrived = true            # post-_ready default (latches reached_target once per destination)
	_blocked_notified = false
	_avoid_velocity = Vector3.ZERO
	_avoid_ready = false
	_stuck_t = 0.0
	_unstick_t = 0.0
	_unstick_dir = Vector3.ZERO
	_stuck_persist = 0.0
	_stuck_hold_t = 0.0
	_jump_cd = 0.0
	_hopping = false
	_link_descent_t = 0.0
	_link_descent_dir = Vector3.ZERO
	_link_drive_mult = LEDGE_DROP_FORWARD_MULT
	_hopped_this_frame = false
	_progress_t = 0.0
	_progress_ref = Vector3.ZERO
	_progress_seeded = false
	_progress_fail_count = 0
	_target_submitted = false  # force the next move_to to re-seed the route even if it re-issues the same destination
	_last_allow_hop = false
	_last_target_climb = 0.0
	last_step_rise = 0.0
	# Re-derive the feet correction: a pooled NPC can come back with a different body/capsule (BodyModelSwap), and this
	# is a property write on the SURVIVING agent, not a rebuild — so it respects this function's "fields only" contract.
	var body := get_parent() as CharacterBody3D
	if body != null:
		apply_path_height_offset(body)

## Route toward `target` on the navmesh; re-arms the arrival / blocked notifications for this new destination.
##
## The target_position write is GATED on repath_epsilon. In DRIVEN mode drive_move_to() funnels through here every
## physics frame, and assigning target_position always queues a fresh A* — so an unguarded write ran a full map query
## per NPC per tick. It was invisible before only because the agent's path was never followed anyway (see
## apply_path_height_offset); with paths live it also machine-guns `link_reached` while a body sits on a NavLink, which
## re-fires the ascent launch far faster than JUMP_COOLDOWN can damp. `_target_submitted` forces the first write after
## a stop() / reset_for_reuse even when the destination is unchanged, so a re-issued identical target still re-seeds.
func move_to(target: Vector3) -> void:
	if _nav == null:
		return  # off-tree / non-CharacterBody3D host: nothing to steer
	if not _target_submitted or _nav.target_position.distance_squared_to(target) > repath_epsilon * repath_epsilon:
		_nav.target_position = target
		_target_submitted = true
	_has_target = true
	# NOT gated: these re-arm every frame in driven mode exactly as before, so the bool contract drive_move_to()'s
	# callers branch on is untouched. (reached_target / path_blocked have no consumers — verified by grep.)
	_arrived = false
	_blocked_notified = false

## Stop pathing (clears the destination); the body eases to a halt through accel, and gravity still applies.
func stop() -> void:
	_has_target = false
	desired_velocity = Vector3.ZERO
	_link_descent_t = 0.0
	_link_descent_dir = Vector3.ZERO
	_link_drive_mult = LEDGE_DROP_FORWARD_MULT
	_target_submitted = false  # next move_to re-seeds the route, even to the same destination
	_last_allow_hop = false
	_last_target_climb = 0.0

## Are we actively heading somewhere (a target set and not yet arrived)?
func is_moving() -> bool:
	return _has_target and not _arrived

## In the post-give-up HOLD (stood still for STUCK_HOLD_TIME after blocking too long). Distinct from ARRIVAL: both make
## drive_move_to() return false, but a hold means "couldn't get there", not "made it". Callers that advance on arrival
## (PatrolBehavior, cutscene walks) check this so a give-up hold doesn't read as reaching the waypoint.
func is_holding() -> bool:
	return _stuck_hold_t > 0.0

## Fighting a blocker it can't route past — accruing net-progress failures OR sitting in the give-up hold. Callers that
## credit "travel" (e.g. GoapActionSearch refreshing the investigate give-up clock while moving) use this to STOP
## crediting motion that isn't progressing, so an investigate / forget clock can actually expire against an unreachable
## spot instead of being re-pinned every frame the body merely produces steering. See update_stuck's net-progress backstop.
func is_struggling() -> bool:
	return _progress_fail_count > 0 or _stuck_hold_t > 0.0

func is_drop_committing() -> bool:
	return _link_descent_t > 0.0 and _link_descent_dir.length_squared() > 0.0001

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
	if _link_descent_t > 0.0:
		return _consume_link_descent(body, speed)
	var target: Vector3 = _nav.target_position
	var self_pos := body.global_position
	var to_target := target - self_pos
	var target_flat_distance := Vector2(to_target.x, to_target.z).length()
	var target_climb := _hop_target_climb(body, target, hop_target)
	_last_target_climb = target_climb
	# Only ballistic-commit off the rim toward a lower target the nav CAN'T route to (chiefly YOU, after you dropped to a
	# disconnected island). A REACHABLE lower target (a ramp, or a WALK-linked stair flight) is walked via the nav path +
	# step-up below — committing there would re-fire a hop every window and defeat the walk-down descent (the drop-commit
	# also refuses a LETHAL drop inside the helper, mirroring the partial/unreachable branches).
	if not _nav.is_target_reachable():
		var direct_drop_dir := _direct_lower_target_drop_commit_dir(body, to_target, target_climb, target_flat_distance, allow_hop)
		if direct_drop_dir.length_squared() > 0.0001:
			_begin_drop_commit(body, direct_drop_dir, true)
			return _consume_link_descent(body, speed)
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
		if _link_descent_t > 0.0:
			return _consume_link_descent(body, speed)
		# Same reachability gate as the direct-drop above: only commit off a descending PATH point when the target is
		# unreachable (partial route ending at a rim). While the target IS reachable we're mid-route on a legit descending
		# path (ramp / WALK stairs) — follow it with to_next + step-up, don't ballistic-commit down our own path.
		if not _nav.is_target_reachable():
			var path_drop_dir := _lower_path_drop_commit_dir(body, target_climb, allow_hop)
			if path_drop_dir.length_squared() > 0.0001:
				_begin_drop_commit(body, path_drop_dir, true)
				return _consume_link_descent(body, speed)
		var partial_commit_dir := _lower_target_partial_path_commit_dir(body, to_target, target_climb)
		if partial_commit_dir.length_squared() > 0.0001:
			if not _blocked_notified:
				_blocked_notified = true
				path_blocked.emit()
			if body.is_on_floor() and _drop_ahead_unsafe(body, partial_commit_dir):
				_arrived = true
				return Vector3.ZERO
			if allow_hop and body.is_on_floor():
				_begin_drop_commit(body, partial_commit_dir, true)
				return _consume_link_descent(body, speed)
			to_next = partial_commit_dir
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
		var lower_commit_dir := _lower_target_commit_dir(body, to_target, target_climb)
		var drop_probe_travel := to_target if lower_commit_dir == Vector3.ZERO else lower_commit_dir
		# FALL-SAFETY (max_pursuit_drop): refuse to charge off a LETHAL drop. Only while GROUNDED at the rim — once
		# airborne we've already committed to a probe-cleared drop, so let the fall finish. Holds at the rim (report
		# arrived) rather than leaping into a pit; a modest ledge / stair tread passes the probe and descends as before.
		if body.is_on_floor() and _drop_ahead_unsafe(body, drop_probe_travel):
			_arrived = true
			return Vector3.ZERO
		to_next = to_target
		# Close unreachable targets on our level or above stop here after an optional hop. A target below us is the
		# ledge-drop pursuit case: keep the horizontal commit velocity instead of declaring arrival at the rim.
		if should_stop_at_unreachable_close_target(target_climb, target_flat_distance) \
				and not _try_hop(body, target_climb, target_flat_distance, allow_hop):
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
		if not should_arrive_on_tiny_flat_steering(target_climb):
			var commit_dir := _lower_target_commit_dir(body, to_target, target_climb)
			if commit_dir.length_squared() > 0.0001:
				if allow_hop and body.is_on_floor():
					if _drop_ahead_unsafe(body, commit_dir):
						_arrived = true  # lethal drop ahead: hold at the rim rather than pop off it
						return Vector3.ZERO
					_begin_drop_commit(body, commit_dir, true)
					return _consume_link_descent(body, speed)
				return commit_dir * speed
		_arrived = true
		return Vector3.ZERO
	return to_next.normalized() * speed

## Whether an unreachable target that is horizontally close should halt the body instead of continuing to steer.
## Downward targets are excluded: they are the "player dropped off the ledge" case, where the NPC needs to keep
## committing over the rim rather than treating near-identical X/Z as arrival.
static func should_stop_at_unreachable_close_target(target_climb: float, target_flat_distance: float) -> bool:
	return target_flat_distance < UNREACHABLE_CLOSE_STOP_DISTANCE and target_climb >= -STEP_MIN_DELTA

## Whether a nearly-zero horizontal steering vector should count as arrival. Same-level and upward targets keep the
## old stop behavior; lower targets are ledge pursuit and need a fallback step direction instead.
static func should_arrive_on_tiny_flat_steering(target_climb: float) -> bool:
	return target_climb >= -STEP_MIN_DELTA

## Whether an unreachable lower target should stop following the partial navmesh path and commit off the reachable
## endpoint. This is the rim case: the nav agent can keep "not finished" while walking/rubbing around the last
## reachable polygon, so waiting for is_navigation_finished() is too late.
static func should_commit_from_partial_path_to_lower_target(
		target_climb: float,
		path_end_flat_distance: float,
		target_reachable: bool,
		target_below_path_end: bool = false) -> bool:
	return target_climb < -STEP_MIN_DELTA \
			and path_end_flat_distance <= LOWER_TARGET_PARTIAL_END_DISTANCE \
			and (not target_reachable or target_below_path_end)

static func should_force_lower_path_drop(
		allow_hop: bool,
		target_climb: float,
		lower_path_flat_distance: float) -> bool:
	return allow_hop \
			and target_climb < -STEP_MIN_DELTA \
			and lower_path_flat_distance <= LOWER_PATH_DROP_COMMIT_DISTANCE

static func should_force_direct_lower_target_drop(
		allow_hop: bool,
		target_climb: float,
		target_flat_distance: float) -> bool:
	return allow_hop \
			and target_climb < -STEP_MIN_DELTA \
			and target_flat_distance <= LOWER_TARGET_DIRECT_DROP_DISTANCE

func _direct_lower_target_drop_commit_dir(
		body: CharacterBody3D,
		to_target: Vector3,
		target_climb: float,
		target_flat_distance: float,
		allow_hop: bool) -> Vector3:
	if not should_force_direct_lower_target_drop(allow_hop, target_climb, target_flat_distance):
		return Vector3.ZERO
	var dir := _lower_target_commit_dir(body, to_target, target_climb)
	# FALL-SAFETY (max_pursuit_drop): the direct-drop shortcut runs BEFORE the partial/unreachable branches that probe
	# for a lethal drop, so it must probe too — else it leaps off cliffs the gate is meant to refuse. Only while grounded
	# at the rim; once airborne we've committed. NavLink descents are a SEPARATE path (_begin_link_descent) and stay free
	# to drop off big authored cliffs (that's their job) — this probe is pursuit-only.
	if dir.length_squared() > 0.0001 and body.is_on_floor() and _drop_ahead_unsafe(body, dir):
		return Vector3.ZERO
	return dir

func _lower_path_drop_commit_dir(body: CharacterBody3D, target_climb: float, allow_hop: bool) -> Vector3:
	if _nav == null:
		return Vector3.ZERO
	var path := _nav.get_current_navigation_path()
	if path.size() <= 0:
		return Vector3.ZERO
	var best_dir := Vector3.ZERO
	var best_flat := INF
	for point in path:
		# Only ballistic-commit off a REAL drop (a genuine island-gap rim, > link_climb_min ~0.4 m below us — the same
		# height the bake leaves disconnected). A merely descending path point (STEP_MIN_DELTA ~1.5 cm lower: a ramp, a
		# WALK-linked stair tread, gentle ground) is navmesh-connected and must be WALKED via to_next + step-down, not
		# leapt — else pursuing an off-mesh target made NPCs launch a 4.2 m/s hop down every downhill segment.
		if point.y >= body.global_position.y - link_climb_min:
			continue
		var flat := Vector3(point.x - body.global_position.x, 0.0, point.z - body.global_position.z)
		var flat_distance := flat.length()
		if flat_distance >= best_flat:
			continue
		if not should_force_lower_path_drop(allow_hop, target_climb, flat_distance):
			continue
		best_flat = flat_distance
		best_dir = link_descent_commit_dir(body.global_position, point, desired_velocity, body.velocity, body.global_basis.z)
	# FALL-SAFETY: never commit off a lethal drop (same probe the direct/partial branches use). Grounded-only.
	if best_dir.length_squared() > 0.0001 and body.is_on_floor() and _drop_ahead_unsafe(body, best_dir):
		return Vector3.ZERO
	return best_dir

func _lower_target_partial_path_commit_dir(body: CharacterBody3D, to_target: Vector3, target_climb: float) -> Vector3:
	if _nav == null:
		return Vector3.ZERO
	var path_end := _current_path_end_position()
	if path_end.is_empty():
		return Vector3.ZERO
	var end_pos: Vector3 = path_end["position"]
	var end_flat_distance := Vector2(end_pos.x - body.global_position.x, end_pos.z - body.global_position.z).length()
	var target_y := body.global_position.y + to_target.y
	var target_below_path_end := target_y < end_pos.y - STEP_MIN_DELTA
	if not should_commit_from_partial_path_to_lower_target(target_climb, end_flat_distance, _nav.is_target_reachable(), target_below_path_end):
		return Vector3.ZERO
	var dir := _lower_target_commit_dir(body, to_target, target_climb)
	if dir.length_squared() > 0.0001:
		return dir
	var to_end := Vector3(end_pos.x - body.global_position.x, 0.0, end_pos.z - body.global_position.z)
	return to_end.normalized() if to_end.length_squared() > 0.0001 else Vector3.ZERO

func _current_path_end_position() -> Dictionary:
	if _nav == null:
		return {}
	var path := _nav.get_current_navigation_path()
	if path.size() <= 0:
		return {}
	return { "position": path[path.size() - 1] }

## Direction to keep committing when the target is below us but nearly identical in X/Z. At a rim the direct target
## vector can flatten to zero, so preserve the chase's previous horizontal intent (or current momentum/facing) long
## enough for move_and_slide + gravity to carry the body off the lip.
func _lower_target_commit_dir(body: CharacterBody3D, to_target: Vector3, target_climb: float) -> Vector3:
	if target_climb >= -STEP_MIN_DELTA:
		return Vector3.ZERO
	var flat_target := Vector3(to_target.x, 0.0, to_target.z)
	if flat_target.length_squared() > 0.0001:
		return flat_target.normalized()
	var previous_intent := Vector3(desired_velocity.x, 0.0, desired_velocity.z)
	if previous_intent.length_squared() > 0.0001:
		return previous_intent.normalized()
	var momentum := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if momentum.length_squared() > 0.0001:
		return momentum.normalized()
	var facing := Vector3(body.global_basis.z.x, 0.0, body.global_basis.z.z)
	return facing.normalized() if facing.length_squared() > 0.0001 else Vector3.ZERO

## Vertical climb from our capsule bottom to the target's (a raised target -> positive). Mirrors npc._nav_hop_target_climb.
func _hop_target_climb(body: CharacterBody3D, target: Vector3, hop_target: Node3D) -> float:
	var target_floor: float = collision_bottom_y(hop_target, target.y) if is_instance_valid(hop_target) else target.y
	var self_floor: float = collision_bottom_y(body, body.global_position.y)
	return target_floor - self_floor

## Fall-safety probe for the off-ledge pursuit commit (see max_pursuit_drop). Would stepping off the ledge AHEAD (in
## the flattened `travel` direction) drop the body more than max_pursuit_drop? Casts a short down-ray just past the
## lip from the capsule's feet. TRUE = a deep / bottomless drop we must NOT charge off (hold at the rim rather than
## leap to our death); FALSE = safe (a modest ledge, a stair tread, or flat ground — the proven commit-and-charge
## descent proceeds). Returns FALSE (allow) whenever it can't probe — gate disabled, off-tree, or no physics space —
## so it never blocks the pre-existing behaviour it can't verify; it only ADDS a refusal on a positively-deep drop.
func _drop_ahead_unsafe(body: CharacterBody3D, travel: Vector3) -> bool:
	if max_pursuit_drop <= 0.0 or not body.is_inside_tree():
		return false
	var world := body.get_world_3d()
	if world == null or not world.space.is_valid():
		return false
	var flat := Vector3(travel.x, 0.0, travel.z)
	if flat.length_squared() < 0.0001:
		return false  # no clear horizontal heading -> nothing to step off
	flat = flat.normalized()
	var feet_y := collision_bottom_y(body, body.global_position.y)
	var ahead := body.global_position + flat * (agent_radius + LEDGE_PROBE_AHEAD)
	var from := Vector3(ahead.x, feet_y + 0.2, ahead.z)  # a hair above the feet so the ray never starts inside the floor
	var to := from + Vector3.DOWN * (max_pursuit_drop + LEDGE_PROBE_MARGIN)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [body]
	# No floor within the probe's reach -> the drop is deeper than max_pursuit_drop (or bottomless): unsafe to commit.
	return world.direct_space_state.intersect_ray(q).is_empty()

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
	_last_allow_hop = allow_hop
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
		_progress_seeded = false  # not genuinely trying to move -> don't accrue "went nowhere" toward the backstop
		_progress_fail_count = 0
		return
	# Anti-pacing BACKSTOP: track NET horizontal travel over PROGRESS_WINDOW, INDEPENDENT of the per-frame speed check
	# below. A wall-slide sidestep moves at full lateral speed (so that check reads "progress" and resets the give-up
	# timer), yet over a couple of seconds the body just oscillates back to near where it started. If a full window
	# elapses while still trying to move but net travel stayed under PROGRESS_MIN_TRAVEL, we're churning against a blocker
	# the path can't route around -> give up + hold + warn (the escape the flat-face pacing case otherwise never reaches).
	# Runs before the speed check precisely so a lateral slide can no longer suppress the give-up net.
	if not _progress_seeded:
		_progress_ref = body.global_position
		_progress_t = 0.0
		_progress_seeded = true
	_progress_t += delta
	if _progress_t >= PROGRESS_WINDOW:
		var net_travel := Vector2(body.global_position.x - _progress_ref.x, body.global_position.z - _progress_ref.z).length()
		_progress_ref = body.global_position
		_progress_t = 0.0
		if net_travel < PROGRESS_MIN_TRAVEL:
			_progress_fail_count += 1
			var chase_can_recover := _last_allow_hop and _host_jump_velocity(body) > 0.0
			# A hop-capable chaser gets a couple of recovery-hop windows against a tall blocker before we conclude it
			# can't be cleared and give up + hold + strand-warn. Without the count cap it pogos forever and _give_up (and
			# the STRANDED diagnostic) is NEVER reached in the exact pursuit state where prop/wall pacing happens — the
			# escape the backstop was built for. A recovery hop that can't even fire (off-floor / cooldown) gives up now.
			if chase_can_recover and _progress_fail_count < PROGRESS_FAIL_GIVEUP and _try_stuck_recovery_hop(body, intended, PROGRESS_WINDOW):
				return
			_give_up(body)  # moving but going nowhere: churning against a blocker the path can't route around
			return
		else:
			_progress_fail_count = 0  # a productive window resets the give-up count
	if Vector2(body.velocity.x, body.velocity.z).length() >= intended * STUCK_SPEED_FRAC:
		_stuck_t = 0.0
		_stuck_persist = 0.0
		# Do NOT reset _progress_fail_count here. Instantaneous SPEED is exactly the signal the net-displacement backstop
		# is built to distrust: a wall-slide sidestep keeps full lateral speed while netting ~zero progress, so resetting
		# the fail count every fast frame made the backstop unreachable (the count never survived a full window to reach
		# PROGRESS_FAIL_GIVEUP) and a hop-capable chaser pogo-paced a blocker forever. The count now clears ONLY on a
		# genuinely productive window (below), when we stop trying to move (top of this function), or on give-up.
		if body.has_method(&"_reset_stranded"):
			body.call(&"_reset_stranded")  # made progress -> host clears its _stranded_cycles / _stranded_warned
		return
	_stuck_persist += delta
	if _try_stuck_recovery_hop(body, intended, _stuck_persist):
		return
	var giveup_time := CHASE_STUCK_GIVEUP_TIME if _last_allow_hop else STUCK_GIVEUP_TIME
	if _stuck_persist >= giveup_time:
		_give_up(body)  # pressed-and-not-sliding path to the same hold as the net-progress backstop above
		return
	if not _nav.is_target_reachable() and not _last_allow_hop:
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

## Enter the give-up HOLD: stop shuffling, stand still for STUCK_HOLD_TIME, clear the stuck / unstick / progress timers,
## and fire the host STRANDED diagnostic. Reached two ways — the classic pressed-but-not-sliding path (_stuck_persist >=
## STUCK_GIVEUP_TIME) and the net-progress backstop (still moving but going nowhere) — so both share one escape and one
## diagnostic. host._note_stranded is duck-typed (a bare mob has none), so the STRANDED warning only fires on a real NPC.
func _give_up(body: CharacterBody3D) -> void:
	_stuck_persist = 0.0
	_stuck_t = 0.0
	_unstick_t = 0.0
	_stuck_hold_t = CHASE_STUCK_HOLD_TIME if _last_allow_hop else STUCK_HOLD_TIME
	_progress_seeded = false
	_progress_t = 0.0
	# _progress_fail_count is DELIBERATELY not cleared here. It is the only signal is_struggling() has that isn't just
	# is_holding(), and clearing it at give-up collapsed the two: a non-hop NPC falls straight through its first failed
	# window into _give_up, so the count was never observably > 0 and GoapActionSearch kept re-pinning the investigate
	# give-up clock every press phase (the exact bug its own comment claims to have fixed). It still decays on a
	# genuinely productive window (update_stuck) and on the not-trying early return, so a fresh pursuit re-arms it.
	if body.has_method(&"_note_stranded"):
		body.call(&"_note_stranded")  # host-side diagnostic (owns _stranded_cycles / display_name / global_position)

## When a hostile/searching NPC is blocked before the ordinary "near enough to hop" gate fires, pop a small recovery
## vault. This is deliberately tied to allow_hop, sustained low progress, floor contact, and jump cooldown so idle
## walkers do not bounce, while chasers stop waiting for the player to stand on one exact ledge/corner sweet spot.
func _try_stuck_recovery_hop(body: CharacterBody3D, intended_speed: float, stuck_time: float) -> bool:
	var hop_velocity: float = _host_jump_velocity(body)
	if not should_stuck_recovery_hop(_last_allow_hop, hop_velocity, body.is_on_floor(), _jump_cd, stuck_time, intended_speed):
		return false
	# Only vault a STATIC blocker (a wall / prop / crate we can hop over). If the only thing slowing us is another
	# agent's body — an ally or the player squeezing the same doorway — do NOT hop: RVO will route around them, and
	# hopping just pogos in place (or mounts their capsule). Without this, crowded chasers bunny-hop every ~0.8 s.
	if not _pressing_static_blocker(body):
		return false
	# CLAMPED, unlike the proximity-gated combat hop. This one fires from update_stuck with stuck_time = PROGRESS_WINDOW
	# (2.0 s, always past STUCK_HOP_TIME) and WITHOUT should_nav_hop's "target is within HOP_STEP_DISTANCE" gate, so
	# _last_target_climb here is the height of a target that may be far away and storeys up. Unclamped, maxf() let a
	# player standing 6 m above launch the NPC at ~11 m/s — onto a roof or a stranded island it can't get back off.
	# A recovery vault only ever needs to clear the blocker it is pressing into; reaching a high target is the
	# proximity-gated hop's job.
	var climb := clampf(_last_target_climb, HOP_MIN_CLIMB + HOP_HEIGHT_MARGIN, maxf(recovery_hop_max_climb, HOP_MIN_CLIMB + HOP_HEIGHT_MARGIN))
	body.velocity.y = jump_velocity_for_climb(climb, body.get_gravity().y, hop_velocity)
	_jump_cd = JUMP_COOLDOWN
	_hopping = true
	_hopped_this_frame = true
	_stuck_t = 0.0
	_unstick_t = 0.0
	return true

## True when a non-floor slide collision this frame is against a STATIC blocker — anything that ISN'T another agent
## (an NPC or a &"Player"-group body: the player + companions). Used to gate the recovery hop so a chaser vaults walls
## / props but never pogos off a teammate's or the player's body in a scrum. Slide collisions are fresh here because
## update_stuck runs after move_and_slide. get_collider() is the CollisionObject3D (the CharacterBody3D itself).
func _pressing_static_blocker(body: CharacterBody3D) -> bool:
	for i in body.get_slide_collision_count():
		var col := body.get_slide_collision(i)
		if absf(col.get_normal().y) >= 0.7:
			continue  # floor / ceiling, not a wall we'd vault
		var other := col.get_collider()
		if other is Node and ((other as Node).is_in_group(Groups.NPC) or (other as Node).is_in_group(Groups.PLAYER)):
			continue  # another agent's body — queue behind it (RVO), don't hop onto/over it
		return true
	return false

## Character.explosion_velocity length (a live blast) if the host has one, else 0. Duck-typed so a bare mob (no blast)
## reads neutral. `: Vector3` NOT `:=` — host.get returns Variant (INVARIANT 5).
func _host_blast_len(body: Node) -> float:
	var v: Variant = body.get(&"explosion_velocity")
	if v is Vector3:
		return (v as Vector3).length()
	return 0.0

## Auto-step a stair riser the body is pressing into — the NPC counterpart of the Player's step-up. Host calls this from
## its move step INSTEAD of move_and_slide when grounded + not rising. THIN wrapper over the SHARED host-agnostic core
## (compute_step_up) that the Player also drives, so the riser-climb algorithm lives in ONE place (a fix reaches both;
## the two used to be duplicated + had already micro-diverged). Returns true when it stepped (the caller then SKIPS
## move_and_slide — the step IS this frame's move). No camera easing (that's the Player's concern; NPCs don't own the view).
func try_step_up(body: CharacterBody3D, from_transform: Transform3D, pre_move_velocity: Vector3, delta: float) -> bool:
	last_step_rise = 0.0
	if not enable_step_up or step_up_height <= 0.0:
		return false
	var rise := compute_step_up(body, from_transform, pre_move_velocity, delta, step_up_height, step_down_snap)
	if rise < 0.0:
		return false
	last_step_rise = rise  # host reads this to visually ease the body's instant riser snap (NPC stair step-smoothing)
	return true

## SHARED, host-agnostic step-up KINEMATICS — the Player and the NPC Locomotor BOTH drive it (const-identical to the
## Player's former copy). Probes a lift straight up, then forward, then down onto the next tread; if a valid tread sits
## within max_step, SNAPS the body onto it (keeps horizontal velocity, zeroes vertical) and returns the vertical RISE it
## applied. Returns a NEGATIVE value when it did NOT step (no headroom / wall / gap / too-steep / RigidBody / out of
## range), so a caller (the Player) can gate camera easing on `>= 0`. Only CharacterBody3D primitives — no host state.
static func compute_step_up(body: CharacterBody3D, from_transform: Transform3D, pre_move_velocity: Vector3, delta: float, max_step: float, down_snap: float) -> float:
	if max_step <= 0.0 or delta <= 0.0:
		return -1.0
	var motion := _step_probe_motion(pre_move_velocity, delta)
	if motion.is_zero_approx():
		return -1.0  # not moving horizontally -> nothing to step over
	var margin: float = body.safe_margin
	var lift := max_step + STEP_UP_CLEARANCE
	# 1) Is there headroom to lift the body a full step? (A low ceiling / overhang -> can't step, just slide.)
	if body.test_move(from_transform, Vector3.UP * lift, null, margin):
		return -1.0
	for candidate_motion in _step_probe_candidates(body, from_transform, motion):
		var step_delta := _step_up_motion(body, from_transform, candidate_motion, lift, max_step, down_snap, pre_move_velocity)
		if step_delta >= 0.0:
			return step_delta
	return -1.0

static func _step_up_motion(
		body: CharacterBody3D,
		from_transform: Transform3D,
		horizontal_motion: Vector3,
		lift: float,
		max_step: float,
		down_snap: float,
		pre_move_velocity: Vector3) -> float:
	var margin: float = body.safe_margin
	# 2) From the raised pose, is the forward tread clear? A hit here = a real wall (taller than a step), not a riser.
	var raised := from_transform
	raised.origin += Vector3.UP * lift
	if body.test_move(raised, horizontal_motion, null, margin):
		return -1.0
	# 3) Drop back down onto the tread ahead; require an actual floor-angled surface (not a steep face or a RigidBody).
	var ahead := raised
	ahead.origin += horizontal_motion
	var down := KinematicCollision3D.new()
	if not body.test_move(ahead, Vector3.DOWN * (lift + down_snap), down, margin):
		return -1.0  # nothing to stand on ahead -> it's a gap/ledge, not a step
	if down.get_normal().dot(Vector3.UP) < cos(body.floor_max_angle):
		return -1.0  # too steep to stand on
	if down.get_collider() is RigidBody3D:
		return -1.0  # don't "climb" a dynamic body (a crate/ragdoll) — the physics push handles those
	var final_origin: Vector3 = ahead.origin + down.get_travel()
	var step_delta := final_origin.y - from_transform.origin.y
	if step_delta <= STEP_MIN_DELTA or step_delta > max_step + STEP_UP_CLEARANCE:
		return -1.0  # no meaningful rise, or taller than we can step (leave it to the combat hop / a NavLink)
	body.global_position = final_origin
	body.velocity.x = pre_move_velocity.x
	body.velocity.z = pre_move_velocity.z
	body.velocity.y = 0.0
	body.apply_floor_snap()
	return step_delta

## Extra step-up probe for diagonal approaches: if the first forward probe rubs along a stair edge, nudge into the riser.
static func _step_probe_candidates(body: CharacterBody3D, from_transform: Transform3D, horizontal_motion: Vector3) -> Array[Vector3]:
	var candidates: Array[Vector3] = [horizontal_motion]
	var into_riser := _step_riser_into_direction(body, from_transform, horizontal_motion)
	if into_riser.is_zero_approx():
		return candidates
	var current_into := maxf(0.0, horizontal_motion.dot(into_riser))
	var extra_into := clampf(
			STEP_MIN_FORWARD_PROBE - current_into,
			0.0,
			STEP_MAX_ANGLED_PROBE_EXTRA)
	if extra_into > STEP_MIN_DELTA:
		candidates.append(horizontal_motion + into_riser * extra_into)
	return candidates

static func _step_riser_into_direction(body: CharacterBody3D, from_transform: Transform3D, horizontal_motion: Vector3) -> Vector3:
	var collision := KinematicCollision3D.new()
	if not body.test_move(from_transform, horizontal_motion, collision, body.safe_margin):
		return Vector3.ZERO
	if collision.get_collider() is RigidBody3D:
		return Vector3.ZERO
	var normal := collision.get_normal()
	if absf(normal.y) > STEP_RISER_NORMAL_Y_MAX:
		return Vector3.ZERO
	var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
	var normal_length := horizontal_normal.length()
	if normal_length <= 0.001:
		return Vector3.ZERO
	var into_riser := -horizontal_normal / normal_length
	if horizontal_motion.normalized().dot(into_riser) <= STEP_MIN_RISER_DOT:
		return Vector3.ZERO
	return into_riser

static func _step_probe_motion(pre_move_velocity: Vector3, delta: float) -> Vector3:
	var horizontal := Vector3(pre_move_velocity.x, 0.0, pre_move_velocity.z)
	var speed := horizontal.length()
	if speed <= 0.0 or delta <= 0.0:
		return Vector3.ZERO
	return horizontal / speed * maxf(speed * delta, STEP_MIN_FORWARD_PROBE)

## Descending-tread catch: after a slide leaves the body airborne over a stair tread, snap it down and keep walking. Thin
## wrapper over the SHARED compute_step_down (the Player drives the same core).
func try_step_down(body: CharacterBody3D, pre_move_velocity: Vector3) -> bool:
	if not enable_step_up:
		return false
	return compute_step_down(body, pre_move_velocity, step_down_snap, STEP_DOWN_MIN_SPEED) < 0.0

## SHARED step-DOWN kinematics. Snaps the body down onto a tread within down_snap when it's airborne over one while moving
## (>= min_speed) and not rising. Returns the (NEGATIVE) vertical travel applied, or 0.0 when it did not step down.
static func compute_step_down(body: CharacterBody3D, pre_move_velocity: Vector3, down_snap: float, min_speed: float) -> float:
	if down_snap <= STEP_MIN_DELTA or body.is_on_floor():
		return 0.0
	if pre_move_velocity.y > STEP_UPWARD_VELOCITY_EPS:
		return 0.0  # already rising (hop/knockback) -> don't yank it back down
	if Vector2(pre_move_velocity.x, pre_move_velocity.z).length() < min_speed:
		return 0.0
	var down := KinematicCollision3D.new()
	if not body.test_move(body.global_transform, Vector3.DOWN * down_snap, down, body.safe_margin):
		return 0.0
	if down.get_normal().dot(Vector3.UP) < cos(body.floor_max_angle):
		return 0.0
	if down.get_collider() is RigidBody3D:
		return 0.0
	var travel := down.get_travel()
	var drop := -travel.y
	if drop <= STEP_MIN_DELTA or drop > down_snap + STEP_UP_CLEARANCE:
		return 0.0
	body.global_position += travel
	body.velocity.y = 0.0
	body.apply_floor_snap()
	return travel.y

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

## Stuck-recovery hop gate: unlike normal nav-hop, this does NOT require the target to be horizontally close, because
## the whole point is that a chaser is blocked before it reaches the perfect ledge/crate sweet spot. The sustained stuck
## timer + allow_hop + cooldown keep it scoped to active pursuit instead of idle/wander movement.
static func should_stuck_recovery_hop(allow_hop: bool, hop_velocity: float, on_floor: bool, jump_cooldown: float, stuck_time: float, intended_speed: float) -> bool:
	if not allow_hop or hop_velocity <= 0.0 or not on_floor or jump_cooldown > 0.0:
		return false
	return intended_speed >= 0.1 and stuck_time >= STUCK_HOP_TIME

## Continue a descending link by walking over the lip for a brief window. A down NavLink makes the target reachable, so
## the unreachable-target ledge-commit branch will not run; this is the reachable-link version of the same physical push.
func _consume_link_descent(body: CharacterBody3D, speed: float) -> Vector3:
	if _link_descent_dir.length_squared() <= 0.0001:
		_link_descent_t = 0.0
		return Vector3.ZERO
	_link_descent_t = maxf(0.0, _link_descent_t - body.get_physics_process_delta_time())
	_arrived = false
	_hopping = true
	var drive_mult := _link_drive_mult if _link_drive_mult > 0.0 else LEDGE_DROP_FORWARD_MULT
	return _link_descent_dir * speed * drive_mult

## An authored NavLink the agent just crossed. link_reached fires DURING get_next_path_position() — which _compute_desired
## calls every non-finished frame — so this handler runs on the SAME call stack in DRIVEN mode too (verified headless).
## UP links inject a ballistic launch; DOWN links inject a short horizontal commit so the body physically steps off the
## ledge. NavigationServer bridges the PATH but never MOVES the CharacterBody, so both directions need body-side help.
## NOT gated on allow_hop: that decoupling is the whole fix.
##
## Reuses the proven hop latches (_jump_cd anti machine-gun, _hopping so update_stuck reads traversal as "trying" not
## stuck, _hopped_this_frame so drive_move_to reports "still travelling"). The down-link timer is reset in
## reset_for_reuse/stop. An undershot launch simply re-fires on the next link re-entry once _jump_cd lapses, and the
## combat hop can't double-fire (whichever sets _jump_cd first suppresses the other this frame).
func _on_link_reached(details: Dictionary) -> void:
	var body := get_parent() as CharacterBody3D
	if body == null:
		return
	# WALK-mode link (a staircase): suppress the ballistic launch. The agent routes THROUGH the link, so the normal
	# path-follow already steers the body horizontally toward the link exit (top landing); our step-up (enable_step_up)
	# climbs the real stair geometry underneath, so the flight WALKS instead of leaping. Duck-typed (walk_traversal()) so
	# the Locomotor keeps zero compile dependency on the NavLink class. LAUNCH-mode ledges/crates fall through and pop.
	var owner_obj := details.get("owner") as Object  # `as Object` safe-casts (null if the payload ever gives an id int, not the node)
	var walk_requested := false
	if owner_obj != null and owner_obj.has_method(&"walk_traversal"):
		walk_requested = owner_obj.call(&"walk_traversal") == true
	var entry: Vector3 = details.get("position", body.global_position)
	var exit := _link_exit_position(details, entry)
	if exit.is_empty():
		return
	var exit_pos: Vector3 = exit["position"]
	var climb := exit_pos.y - entry.y
	var run := Vector2(exit_pos.x - entry.x, exit_pos.z - entry.z).length()
	if should_descend_link(climb):
		if walk_requested and enable_step_up:
			_begin_link_walk(body, entry, exit_pos)
			return
		_begin_link_descent(body, entry, exit_pos)
		return
	if should_walk_link_as_stairs(walk_requested, enable_step_up, climb, run, step_up_height):
		_begin_link_walk(body, entry, exit_pos)
		return
	if link_climb_velocity <= 0.0:
		return  # link ascent disabled for this host
	if not should_climb_link(climb, body.is_on_floor(), _jump_cd, link_climb_min):
		if not body.is_on_floor():
			_begin_link_walk(body, entry, exit_pos)
		return
	_begin_link_ascent(body, entry, exit_pos, climb)

func _begin_link_descent(body: CharacterBody3D, entry: Vector3, exit_pos: Vector3) -> void:
	var dir := link_descent_commit_dir(entry, exit_pos, desired_velocity, body.velocity, body.global_basis.z)
	_begin_drop_commit(body, dir, true)

func _begin_link_walk(body: CharacterBody3D, entry: Vector3, exit_pos: Vector3) -> void:
	var dir := link_descent_commit_dir(entry, exit_pos, desired_velocity, body.velocity, body.global_basis.z)
	_begin_link_commit(dir, link_commit_time_for_run(entry, exit_pos, _host_move_speed(body)), LINK_ASCENT_FORWARD_MULT)

func _begin_link_ascent(body: CharacterBody3D, entry: Vector3, exit_pos: Vector3, climb: float) -> void:
	body.velocity.y = jump_velocity_for_climb(climb, body.get_gravity().y, link_climb_velocity)
	_jump_cd = JUMP_COOLDOWN
	_hopped_this_frame = true
	var dir := link_descent_commit_dir(entry, exit_pos, desired_velocity, body.velocity, body.global_basis.z)
	_begin_link_commit(dir, link_commit_time_for_run(entry, exit_pos, _host_move_speed(body)), LINK_ASCENT_FORWARD_MULT)

func _begin_link_commit(dir: Vector3, seconds: float, drive_mult: float) -> void:
	if dir.length_squared() <= 0.0001:
		return
	_link_descent_dir = dir.normalized()
	_link_descent_t = maxf(_link_descent_t, seconds)
	_link_drive_mult = maxf(drive_mult, 0.0)
	_hopping = true

func _begin_drop_commit(body: CharacterBody3D, dir: Vector3, with_hop: bool) -> void:
	if dir.length_squared() <= 0.0001:
		return
	_link_descent_dir = dir.normalized()
	_link_descent_t = LINK_DESCENT_COMMIT_TIME
	_link_drive_mult = LEDGE_DROP_FORWARD_MULT
	if with_hop and body.is_on_floor():
		body.velocity.y = maxf(body.velocity.y, LEDGE_DROP_HOP_VELOCITY)
	_hopping = true
	_hopped_this_frame = true

## Exit endpoint of the link the agent just entered, as {"position": Vector3} — {} on a stale/invalid RID.
## Godot 4.6's link_reached `details` is {position(=ENTRY), type, rid, owner} — there is NO entry/exit position key
## (verified headless), so read the link's two endpoints from its RID (world space) and take the one FARTHER from the
## entry as the exit. Callers derive the climb themselves (`exit.y - entry.y`; positive = the exit is above us).
func _link_exit_position(details: Dictionary, entry: Vector3) -> Dictionary:
	var rid: RID = details.get("rid", RID())
	if not rid.is_valid():
		return {}
	var a := NavigationServer3D.link_get_start_position(rid)
	var b := NavigationServer3D.link_get_end_position(rid)
	var exit_pos := b if entry.distance_to(a) < entry.distance_to(b) else a
	return { "position": exit_pos }

static func should_descend_link(climb: float) -> bool:
	return climb < -STEP_MIN_DELTA

static func should_walk_link_as_stairs(walk_requested: bool, step_enabled: bool, climb: float, _run: float, step_height: float) -> bool:
	if climb <= STEP_MIN_DELTA:
		return walk_requested
	if walk_requested:
		return true
	return step_enabled and climb <= maxf(0.0, step_height) + STEP_UP_CLEARANCE

static func link_commit_time_for_run(entry: Vector3, exit_pos: Vector3, speed: float, drive_mult: float = LINK_ASCENT_FORWARD_MULT) -> float:
	var run := Vector2(exit_pos.x - entry.x, exit_pos.z - entry.z).length()
	var commit_speed := maxf(speed * maxf(drive_mult, 0.1), 0.1)
	return clampf((run / commit_speed) + 0.2, LINK_DESCENT_COMMIT_TIME, LINK_ASCENT_COMMIT_MAX_TIME)

static func link_descent_commit_dir(
		entry: Vector3,
		exit_pos: Vector3,
		previous_intent: Vector3,
		momentum: Vector3,
		facing: Vector3) -> Vector3:
	var flat_link := Vector3(exit_pos.x - entry.x, 0.0, exit_pos.z - entry.z)
	if flat_link.length_squared() > 0.0001:
		return flat_link.normalized()
	var flat_intent := Vector3(previous_intent.x, 0.0, previous_intent.z)
	if flat_intent.length_squared() > 0.0001:
		return flat_intent.normalized()
	var flat_momentum := Vector3(momentum.x, 0.0, momentum.z)
	if flat_momentum.length_squared() > 0.0001:
		return flat_momentum.normalized()
	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	return flat_facing.normalized() if flat_facing.length_squared() > 0.0001 else Vector3.ZERO

## Pure link-ascent gate — mirrors should_nav_hop but WITHOUT the combat allow_hop gate (an authored link is an explicit
## "traverse here", so idle NPCs climb it). True for a real upward span, grounded, off cooldown. Unit-testable off-tree.
static func should_climb_link(climb: float, on_floor: bool, jump_cooldown: float, climb_min: float) -> bool:
	return on_floor and jump_cooldown <= 0.0 and climb > climb_min

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
