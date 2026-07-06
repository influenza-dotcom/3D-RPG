# Locomotor Phase B — staged migration (npc.gd nav brain → locomotor.gd)

> **STATUS: STAGED / NOT APPLIED — PLAYTEST-GATED.** This is a ready-to-apply, adversarially-reviewed migration
> drafted 2026-07-04 by a workflow (4 recon agents → draft → 4 skeptic lenses). It moves npc.gd's in-line nav
> brain onto the existing standalone drop-in `scripts/components/locomotor.gd` (DRIVEN mode). **It is NOT applied
> to the live files** — movement can't be GUT-verified, so it must be applied by hand and PLAYTESTED. Apply the
> §1–§3 patch below **together with the "CORRECTIONS FROM ADVERSARIAL REVIEW" section at the very end**, then run
> the playtest checklist there.

## Review verdict (4 lenses)

| Lens | Verdict | Notes |
|---|---|---|
| **Frame-order** | ✅ PATCH-SOUND | The 10-step `apply_velocity` order is reproduced statement-for-statement; `apply_velocity` stays the SOLE `move_and_slide()` writer (Locomotor's own is dead in driven mode via `drive_body=false` + a `_physics_process` early-return); `update_stuck` is still LAST; the hop's `velocity.y` write keeps its pre-`gravity`/pre-`apply_velocity` slot. |
| **Caller-signatures** | ✅ PATCH-SOUND | All 10 `host._move_toward(...)` call sites bind to the verbatim shell (incl. the `allow_hop: bool`/`hop_target: Node3D` overload + `bool` return); `_face_*`/`_snap_to_navmesh`/`_height_above_floor` untouched; CompanionFollow's `host._nav` survives via **agent injection** (`external_nav`). |
| **Equivalence** | ⚠️ NEEDS-FIX | `_compute_desired` was NOT byte-equivalent as drafted — see CORRECTION 1 (the `or _hopping` bool bug) and CORRECTION 2 (nav-map-ready gating). All other blocks (apply_velocity shell, update_stuck lift, static/const aliases) are equivalent. |
| **Test-and-cache** | ⚠️ NEEDS-FIX | Corroborates the `or _hopping` bug. No compile-kill, no `:=`-off-Variant trap, no new class_name/autoload/scene edit, no `NPC._ready` in a test. Only ONE test changes (`test_npc.gd:124-135`); `test_enemies.gd`/`test_locomotor.gd` stay green. |

**Defect-7 (the load-bearing "must-verify"): RESOLVED.** The equivalence lens flagged that every "returns false with ZERO
desired" equivalence hinges on npc.gd `_physics_process` zeroing `_desired_velocity` each frame before the movers run.
Confirmed against the live file: **npc.gd:1696** `_desired_velocity = Vector3.ZERO` runs at the top of the AI tick
(after the cutscene/talk early-returns, before `_executor.tick`/combat). So the false-return paths that leave
`_desired_velocity` untouched keep it ZERO — equivalent to the draft copying ZERO. Not a blocker.

## Seam decisions (why it's shaped this way)

- **`_nav` ownership STAYS on npc.gd**; the NPC **injects** its agent into Locomotor via a new optional `external_nav`
  field. One agent on the body → no double RVO; `host._nav` still resolves for CompanionFollow / soak harness / tests.
  Locomotor stays a portable drop-in (a bare mob still builds its own agent when `external_nav == null`).
- **NPC's Locomotor is built `drive_body = false, face_travel = false`.** `drive_body=false` keeps `apply_velocity` the
  sole `move_and_slide` writer; `face_travel=false` stops Locomotor's `_face` (a different turn curve) from fighting
  npc.gd's `_face_yaw` over `body.rotation` (a live collision the recon caught).
- **Speed term = `host._current_move_speed()`** (duck-typed `has_method`+`call`), NOT the flat `move_speed` export —
  preserves stance×limb×encumbrance×agility×status scaling.
- **Pure nav-hop statics move to Locomotor; npc.gd keeps forwarding shells** (`const X := Locomotor.X` aliases) →
  ZERO static-test churn (14 asserts stay green, `NPC.<static>` still resolves).
- **`_stranded_cycles`/`_tick_stranded`/`_note_stranded` STAY on npc.gd** (soak harness reads `host._stranded_cycles`,
  `test_ranged_behavior` pins `_tick_stranded`); Locomotor drives them via `body.call(...)`.

---

# Locomotor Phase B — integrated migration patch (STAGED, not applied)

All line numbers verified against the live files this session (npc.gd = 2795 lines; locomotor.gd = 178).
TABS in all code. Apply by hand, then `--import`, then run GUT, then playtest movement.

---

## 0. The seam decisions (with justification — these drive every edit below)

| Question | Decision | Why (lowest-risk) |
|---|---|---|
| Who owns the `NavigationAgent3D`? | **npc.gd keeps `_build_nav`/`_nav`/`_on_avoidance_velocity`. The NPC INJECTS its `_nav` into Locomotor via a new optional `external_nav` field.** Locomotor uses the injected agent instead of building its own. | CompanionFollow reads `host._nav` at 4 sites (companion_follow.gd:83,99,126,127); soak_harness + tests bind to the NPC. Two live agents on one body = double RVO registration + a second `velocity_computed` fighting the first. Injection = ONE agent, `host._nav` still resolves verbatim, and Locomotor stays a portable drop-in (external_nav is optional; a bare mob still builds its own). |
| Where does the nav-hop write `velocity.y`? | **Inside Locomotor's driven compute, which already receives `body`.** It writes `body.velocity.y` directly (same as npc.gd does today) + sets host `_jump_cd`/`_hopping` through the host. | The hop is host physics state. `_compute_desired(body)` already has the body handle; letting it punch `body.velocity.y` reproduces npc.gd:2035 exactly. Purity is sacrificed knowingly — documented at the seam. |
| Speed term? | **Locomotor calls `host._current_move_speed()` (duck-typed Variant → annotated float), NOT the flat `move_speed` export.** | `_current_move_speed()` (npc.gd:2540) is stance×limb×encumbrance×agility×status. A flat `move_speed` read would silently drop all of it. |
| `_stranded_cycles` / `_tick_stranded`? | **STAY on npc.gd.** Locomotor writes them back through the host (`host._tick_stranded(pos)` / `host._stranded_cycles`). | soak_harness.gd:150 does `n.get(&"_stranded_cycles")` (silent 0 if moved → soft regression GUT won't catch); test_ranged_behavior.gd:43-46 calls `e._tick_stranded(...)` on the NPC. |
| Pure statics (`jump_velocity_for_climb`, `should_nav_hop`, `collision_bottom_y`, `_collision_shape_bottom_y`, `wall_slide_dir`)? | **Bodies MOVE to Locomotor. npc.gd keeps thin `static` FORWARDING shells that call `Locomotor.<x>`.** | 14 test asserts call `NPC.<static>` (test_enemies.gd 11, test_npc.gd 2, + `NPC.STUCK_TIME` consts). Forwarding shells = ZERO test churn and no risk of a mis-typed re-point. The consts also stay on npc.gd (tests read `NPC.STUCK_TIME` etc.); Locomotor reads them via `NPC.<CONST>`? NO — Locomotor must not depend on the NPC type. Locomotor gets its OWN copies of the hop/stuck consts (they are behaviour tuning, portable), and npc.gd keeps its consts for the tests. See §1 note. |
| `face_travel` on the NPC's Locomotor? | **`false`.** | npc.gd owns facing via `_face_yaw`'s FR-independent `1.0-exp(-turn*delta)` curve (npc.gd:2262). Locomotor's `_face` uses a different `lerp_angle(...,turn*delta)` curve (locomotor.gd:162). With `face_travel=true` in driven mode, `_face` (locomotor.gd:108-109) STILL runs and would fight `body.rotation`. Off = npc.gd stays the sole facer. |
| `drive_body` on the NPC's Locomotor? | **`false`** (driven). npc.gd's `apply_velocity` stays the sole `move_and_slide` writer. | INVARIANT 1. |

**Const-duplication note:** `STUCK_TIME`, `UNSTICK_TIME`, `STUCK_SPEED_FRAC`, `STUCK_GIVEUP_TIME`, `STUCK_HOLD_TIME`, `OFF_MESH_RECOVER_DIST`, `JUMP_COOLDOWN`, `HOP_MIN_CLIMB`, `HOP_STEP_DISTANCE`, `HOP_HEIGHT_MARGIN` end up defined on BOTH scripts. npc.gd keeps them because `test_npc.gd:102-107` reads `NPC.STUCK_TIME`/`UNSTICK_TIME`/`STUCK_SPEED_FRAC` and the forwarding static `wall_slide_dir` etc. need nothing but the values live in Locomotor's bodies. To avoid a genuine two-sources-of-truth drift, npc.gd's copies are declared as `const STUCK_TIME := Locomotor.STUCK_TIME` (alias — single source is Locomotor). That keeps `NPC.STUCK_TIME` resolving for the tests while Locomotor is the authority. (GDScript allows a const initialised from another class's const.)

---

## 1. `scripts/components/locomotor.gd` — absorb hop + anti-stuck + off-mesh recovery

### 1a. Add the injected-agent field + the portable tuning consts + host-state seams

**BEFORE** (locomotor.gd:43-56):
```gdscript
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
```

**AFTER**:
```gdscript
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

# --- Anti-stuck / nav-hop STATE (lifted from npc.gd). In DRIVEN mode the host consumes _unstick_t / _unstick_dir
# in its apply_velocity, and calls update_stuck() as the LAST move step. _stranded_cycles is NOT here — it stays on
# the host (soak_harness reads host._stranded_cycles); we call host._tick_stranded(pos) which owns that counter.
var _stuck_t: float = 0.0
var _unstick_t: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO
var _stuck_persist: float = 0.0
var _stuck_hold_t: float = 0.0
var _jump_cd: float = 0.0
var _hopping: bool = false
```

### 1b. Use the injected agent in `_ready()`

**BEFORE** (locomotor.gd:58-75):
```gdscript
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
```

**AFTER**:
```gdscript
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
```

### 1c. Rewrite `_compute_desired` to be the full NPC nav brain (driven mode)

This is the heart of the lift. It absorbs: give-up hold gate, off-mesh recovery, the straight-line-through-unreachable
charge, and the nav-hop (writing `body.velocity.y`). It calls `host._current_move_speed()` for the speed term.

**BEFORE** (locomotor.gd:110-134):
```gdscript
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
```

**AFTER**:
```gdscript
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
	# Wait for the nav map's first sync before trusting the path — querying earlier ERRORS (nav-map-query-before-sync).
	if not NavigationUtils.is_nav_map_ready(_nav.get_navigation_map()):
		return Vector3.ZERO
	var target: Vector3 = _nav.target_position
	var self_pos := body.global_position
	var to_target := target - self_pos
	var target_flat_distance := Vector2(to_target.x, to_target.z).length()
	var target_climb := _hop_target_climb(body, target, hop_target)
	# Off-navmesh RECOVERY: once clearly struggling (_stuck_persist), if we've ended up OFF the baked mesh (knocked off
	# a ledge / walked off chasing), steer for the nearest ON-mesh point so we walk back onto walkable floor. Gated on
	# _stuck_persist so healthy NPCs never run the query.
	if _stuck_persist > 0.5:
		var nav_map := _nav.get_navigation_map()
		var nearest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, self_pos)
		var off := nearest - self_pos
		if off.length() > OFF_MESH_RECOVER_DIST:
			var flat := Vector3(off.x, 0.0, off.z)
			if flat.length() > 0.1:
				_arrived = false
				return flat.normalized() * speed
	if _nav.is_navigation_finished():
		# Genuinely arrived (or the hop got us there): try one last hop if a raised target sits right on top of us,
		# else stop + fire reached_target once.
		if _try_hop(body, target_climb, target_flat_distance, allow_hop):
			return Vector3.ZERO  # hop consumed this frame; horizontal handled next frame
		if not _arrived:
			_arrived = true
			reached_target.emit()
		return Vector3.ZERO
	var to_next: Vector3
	if not _nav.is_target_reachable():
		# No navmesh path (you dropped off a ledge / onto a disconnected island): COMMIT and charge straight at the
		# target, walking off the edge if pursuit demands it. This is the combat charge — Locomotor's old give-up
		# (path_blocked + ZERO) is REPLACED here so pursuit never stalls. Fire path_blocked once as a diagnostic.
		if not _blocked_notified:
			_blocked_notified = true
			path_blocked.emit()
		to_next = to_target
		if target_flat_distance < 0.5 and not _try_hop(body, target_climb, target_flat_distance, allow_hop):
			_arrived = true
			return Vector3.ZERO
	else:
		to_next = _nav.get_next_path_position() - self_pos
		if Vector2(to_next.x, to_next.z).length() < 0.05:
			# Path won't advance (missing/floating/disconnected navmesh under us): head straight so pursuit still works.
			to_next = to_target
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
	if to_next.length() < 0.05:
		_arrived = true
		return Vector3.ZERO
	return to_next.normalized() * speed
```

### 1d. Add the hop helpers, the driven-mode entry point, the anti-stuck machine, and the pure statics

Insert these AFTER `_compute_desired` (after the new AFTER-block from 1c) and BEFORE `_drive`.

**INSERT (new methods)**:
```gdscript
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
	var speed: float = _host_move_speed(body)
	desired_velocity = _compute_desired(body, speed, allow_hop, hop_target)
	# "Still travelling?" = we produced steering OR we're mid-hop. Arrived / held -> false so the caller re-picks/holds.
	return desired_velocity.length_squared() > 0.0001 or _hopping

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
```

### 1e. `_physics_process` must NOT run the driven brain autonomously

In driven mode the host calls `drive_move_to` + `update_stuck`; Locomotor's own `_physics_process` must not ALSO
compute (it would double-run the hop and reset `_arrived`). The existing autonomous path calls `_compute_desired(body)`
with the OLD 1-arg signature — now that the signature changed, autonomous mode must call the new one with defaults.

**BEFORE** (locomotor.gd:99-109):
```gdscript
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
```

**AFTER**:
```gdscript
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
```

> Note: autonomous mode now gets the give-up/off-mesh/hop logic too. That is a behaviour ENRICHMENT for bare mobs, not a
> regression (they previously had none). Off-mesh recovery + `update_stuck` are only reached in autonomous mode if
> something calls `update_stuck`; a bare mob's `_drive` does NOT call it, so `_stuck_persist`/`_unstick_t` stay 0 and the
> new branches are inert for autonomous hosts — behaviour there is unchanged except the hop, which is gated on
> `allow_hop=false` → `should_nav_hop` returns false → never fires. **Autonomous behaviour is preserved.**

---

## 2. `scripts/npc/npc.gd` — shells that delegate; keep every signature + the sole move_and_slide

### 2a. Const aliases (single source of truth = Locomotor) — replace the 10 literal consts

**BEFORE** (npc.gd:368-377):
```gdscript
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
```

**AFTER**:
```gdscript
# Anti-stuck / nav-hop tuning now LIVES on Locomotor (the nav brain migrated there in Phase B). These aliases keep
# NPC.STUCK_TIME etc. resolving to the SAME values for the tests (test_npc reads NPC.STUCK_TIME/UNSTICK_TIME/
# STUCK_SPEED_FRAC) with Locomotor as the single source of truth — no drift.
const STUCK_SPEED_FRAC := Locomotor.STUCK_SPEED_FRAC
const STUCK_TIME := Locomotor.STUCK_TIME
const UNSTICK_TIME := Locomotor.UNSTICK_TIME
const STUCK_GIVEUP_TIME := Locomotor.STUCK_GIVEUP_TIME
const STUCK_HOLD_TIME := Locomotor.STUCK_HOLD_TIME
const OFF_MESH_RECOVER_DIST := Locomotor.OFF_MESH_RECOVER_DIST
const JUMP_COOLDOWN := Locomotor.JUMP_COOLDOWN
const HOP_MIN_CLIMB := Locomotor.HOP_MIN_CLIMB
const HOP_STEP_DISTANCE := Locomotor.HOP_STEP_DISTANCE
const HOP_HEIGHT_MARGIN := Locomotor.HOP_HEIGHT_MARGIN
```

> INVARIANT-5 / class-cache caution: `Locomotor` must be in the global class cache before npc.gd parses this. It already
> is (`class_name Locomotor`, and npc.gd will reference it in `_build_components`). If a stale cache throws "Could not
> find type Locomotor", run `--import` once (memory: new-classname-not-registered-cascade).

### 2b. Add a Locomotor handle + retire the local nav-hop state that MOVED

npc.gd's `_stuck_t/_unstick_t/_unstick_dir/_stuck_persist/_stuck_hold_t/_jump_cd/_hopping` now live on Locomotor.
BUT `apply_velocity` reads `_unstick_t`/`_unstick_dir`, and the shells need to reach Locomotor's copies. Keep npc.gd
FREE of those seven vars (delete them) and route through `_locomotor`. KEEP `_stranded_cycles/_last_giveup_pos/
_stranded_warned` (soak + test pin them).

**BEFORE** (npc.gd:378-387):
```gdscript
var _stuck_t: float = 0.0
var _unstick_t: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO
var _stuck_persist: float = 0.0  ## cumulative time wanting-to-move but blocked — drives the give-up (vs _stuck_t which the side-step resets)
var _stuck_hold_t: float = 0.0   ## >0 while "given up": _move_toward returns false (wanderers re-pick; pursuers hold) so the NPC stands instead of pacing
var _jump_cd: float = 0.0        ## counts down between nav-driven hops (see JUMP_COOLDOWN) so a climb can't bounce
var _hopping: bool = false       ## true from a nav-hop firing until we next touch the floor — _update_stuck counts these airborne frames as "still trying" so a futile pogo gives up (NOT _jump_cd: flight 0.92s > cooldown 0.8s)
var _stranded_cycles: int = 0    ## consecutive give-ups in the SAME spot — a run of these = stranded on a bad-bake island
var _last_giveup_pos: Vector3 = Vector3.ZERO  ## where we last gave up, to tell "same spot" from "moved on"
var _stranded_warned: bool = false  ## one stranded-warning per episode (cleared when we make real progress)
```

**AFTER**:
```gdscript
# Anti-stuck / nav-hop timers + latches MIGRATED to Locomotor (Phase B); apply_velocity + the _move_toward shell reach
# them via _locomotor. Only the STRANDED diagnostic counter stays here — soak_harness reads host._stranded_cycles and
# test_ranged_behavior calls host._tick_stranded, so the counter + its warn latch are HOST-owned; Locomotor calls back
# into _note_stranded() / _reset_stranded() to drive them.
var _locomotor: Locomotor = null  ## the nav brain (built DRIVEN in _build_components); owns pathing/hop/anti-stuck
var _stranded_cycles: int = 0    ## consecutive give-ups in the SAME spot — a run of these = stranded on a bad-bake island
var _last_giveup_pos: Vector3 = Vector3.ZERO  ## where we last gave up, to tell "same spot" from "moved on"
var _stranded_warned: bool = false  ## one stranded-warning per episode (cleared when we make real progress)
```

> `_nav` (npc.gd:354), `_avoid_velocity`, `_avoid_ready` (355-356) STAY — CompanionFollow reads `host._nav`, and
> `_on_avoidance_velocity` still fills `_avoid_velocity` which `apply_velocity` still adopts.

### 2c. Build + wire the Locomotor in DRIVEN mode, inject `_nav`

`_build_nav` (npc.gd:1645-1659) builds `_nav`. It is called at npc.gd:437, AFTER `_build_components` (432). We build the
Locomotor in `_build_components` but must inject `_nav` — which doesn't exist until 437. Cleanest: build the Locomotor
node in `_build_components` (so it's a child like every other component) but set `external_nav` + add it as a child
AFTER `_build_nav`, OR build `_nav` first. **Lowest-risk: move the Locomotor construction to right after `_build_nav`**
so `_nav` exists to inject. Add it at the `_ready` call site, not in `_build_components`, to guarantee ordering.

**BEFORE** (npc.gd:436-437):
```gdscript
	_build_perception()
	_build_nav()
```

**AFTER**:
```gdscript
	_build_perception()
	_build_nav()
	_build_locomotor()  # DRIVEN nav brain; injected with _nav (built just above) so there's ONE agent on the body
```

**INSERT a new method** — put it immediately AFTER `_build_nav` (after npc.gd:1659, before the `_on_avoidance_velocity`
doc-comment at 1661):
```gdscript

## Build the Locomotor drop-in in DRIVEN mode and hand it OUR NavigationAgent3D (built by _build_nav just before this),
## so path queries + RVO run on the single agent CompanionFollow / soak read as host._nav — never a second agent. Driven
## (drive_body=false) => Locomotor only COMPUTES; apply_velocity stays the sole move_and_slide writer. face_travel=false
## => npc.gd's _face_yaw stays the sole facer (Locomotor's _face uses a different curve and would fight body.rotation).
func _build_locomotor() -> void:
	_locomotor = Locomotor.new()
	_locomotor.external_nav = _nav
	_locomotor.drive_body = false
	_locomotor.face_travel = false
	add_child(_locomotor)
```

### 2d. `_move_toward` shell — delegate to Locomotor, KEEP the exact signature

The 9 external callers + `_tick_cutscene_movement` branch on the returned bool. The signature MUST stay
`_move_toward(target: Vector3, allow_hop := false, hop_target: Node3D = null) -> bool`.

**BEFORE** (npc.gd:1972-2041, the whole body):
```gdscript
func _move_toward(target: Vector3, allow_hop: bool = false, hop_target: Node3D = null) -> bool:
	if not _nav:
		return false
	# Given up (we've been blocked too long — see _update_stuck): report "can't get there" so a wanderer re-picks
	# and a pursuer holds. _desired_velocity stays ZERO this frame (reset in _physics_process), so the NPC stands
	# still instead of grinding/pacing into the blockage.
	if _stuck_hold_t > 0.0:
		return false
	var to_target := target - global_position
	var target_flat_distance := Vector2(to_target.x, to_target.z).length()
	var target_climb := _nav_hop_target_climb(target, hop_target)
	# Off-navmesh RECOVERY: once we're clearly struggling (stuck for a beat), check whether we've ended up OFF the
	# baked mesh entirely (knocked off a ledge, walked off an edge chasing, spawned a hair off). If so, steer for
	# the nearest point ON the mesh so we walk back onto walkable floor instead of being stranded. Gated on
	# _stuck_persist so healthy NPCs never run the query. (Won't rescue an NPC standing ON a stray walkable poly —
	# that's a bad-bake problem, not an off-mesh one — but it recovers genuinely off-mesh NPCs.)
	if _stuck_persist > 0.5 and is_inside_tree():
		var nav_map := _nav.get_navigation_map()
		if NavigationUtils.is_nav_map_ready(nav_map):  # skip until the map has synced
			var nearest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, global_position)
			var off := nearest - global_position
			if off.length() > OFF_MESH_RECOVER_DIST:
				var flat := Vector3(off.x, 0.0, off.z)
				if flat.length() > 0.1:
					_desired_velocity = flat.normalized() * _current_move_speed()
					return true
	_nav.target_position = target
	var to_next: Vector3
	if not _nav.is_navigation_finished():
		# Normal: follow the baked navmesh path (routes around walls + obstacles).
		to_next = _nav.get_next_path_position() - global_position
		if Vector2(to_next.x, to_next.z).length() < 0.05:
			# Path won't advance — navmesh is missing/floating/disconnected under us, so the
			# agent can't route. Head straight at the target so pursuit still works. (Fix the
			# bake for proper wall-avoidance + verticality.)
			to_next = to_target
	elif not _nav.is_target_reachable():
		# No navmesh path to you (you dropped off a ledge / off the mesh): commit and head
		# straight for you, walking off the edge if pursuit demands it. Gravity does the fall.
		to_next = to_target
		if target_flat_distance < 0.5 and not _try_nav_hop(target_climb, target_flat_distance, allow_hop):
			return false
	else:
		if _try_nav_hop(target_climb, target_flat_distance, allow_hop):
			return true
		return false  # genuinely arrived
	var climb := to_next.y
	to_next.y = 0.0
	var hop_climb := climb
	var hop_horizontal := to_next.length()
	if target_flat_distance < HOP_STEP_DISTANCE and target_climb > hop_climb:
		hop_climb = target_climb
		hop_horizontal = target_flat_distance
	# Hop up toward a higher target the navmesh can't route us onto — chiefly YOU on a crate/ledge/balcony (the
	# straight-line fallback), or a baked ledge / up navigation-link if a level provides one. The launch SCALES to the
	# target's height (jump_velocity_for_climb): jump_velocity is the floor, and a higher target gets a stronger upward
	# impulse so the NPC actually reaches your feet rather than falling short under you — no fixed pop, no out-of-reach
	# cap. Gated to threatening pursuit (allow_hop) so only a chasing/searching/escorting NPC hops, never a civilian;
	# is_on_floor + JUMP_COOLDOWN + horizontal-proximity (< 1.5 m, AT the step) stop one climb machine-gunning. A
	# genuinely unreachable perch (you far overhead, no landing) just means the hop can't mount — _update_stuck counts
	# our own airborne hop frames as still-trying, so it converts to "give up and hold + fire" instead of pogoing
	# forever. jump_velocity = 0 disables hopping for this NPC.
	if should_nav_hop(allow_hop, jump_velocity, is_on_floor(), _jump_cd, hop_climb, hop_horizontal):
		velocity.y = jump_velocity_for_climb(hop_climb, get_gravity().y, jump_velocity)
		_jump_cd = JUMP_COOLDOWN
		_hopping = true  # cleared on the next floor contact (see _update_stuck) — marks our own airborne hop as "trying"
	if to_next.length() < 0.05:
		return false
	_desired_velocity = to_next.normalized() * _current_move_speed()
	return true

func _try_nav_hop(climb: float, horizontal_distance: float, allow_hop: bool) -> bool:
	if not should_nav_hop(allow_hop, jump_velocity, is_on_floor(), _jump_cd, climb, horizontal_distance):
		return false
	velocity.y = jump_velocity_for_climb(climb, get_gravity().y, jump_velocity)
	_jump_cd = JUMP_COOLDOWN
	_hopping = true
	return true
```

**AFTER**:
```gdscript
func _move_toward(target: Vector3, allow_hop: bool = false, hop_target: Node3D = null) -> bool:
	# SHELL onto the Locomotor nav brain (Phase B). Locomotor owns the path-stepping, off-mesh recovery, straight-line
	# charge through an unreachable target, and the combat nav-hop (it writes body.velocity.y + arms its own _jump_cd/
	# _hopping). It writes THIS frame's steering into its desired_velocity, which we copy into _desired_velocity so
	# apply_velocity (the sole move_and_slide writer) consumes it exactly as before. Returns the same bool the 9 callers
	# branch on: true = still travelling, false = arrived / given-up-hold. Off-tree / pre-build -> false (unchanged).
	if _locomotor == null:
		return false
	var moving := _locomotor.drive_move_to(target, allow_hop, hop_target)
	_desired_velocity = _locomotor.desired_velocity
	return moving
```

> `_try_nav_hop` is DELETED (its body moved to `Locomotor._try_hop`). It had no external callers (grep: internal only).
> `_nav_hop_target_climb` is DELETED (moved to `Locomotor._hop_target_climb`); it was internal-only too. Confirm with a
> pre-apply grep (see §5 checklist). The pure statics `should_nav_hop`/`jump_velocity_for_climb`/`collision_bottom_y`/
> `_collision_shape_bottom_y`/`wall_slide_dir` are REPLACED by forwarding shells — see 2h.

### 2e. `apply_velocity` shell — same 10 steps, read `_locomotor._unstick_*`, call `_locomotor.update_stuck` last

**BEFORE** (npc.gd:2115-2150):
```gdscript
func apply_velocity() -> void:
	# move_and_slide needs a live physics space; bail when we're not in one (e.g. a unit
	# test instantiates the NPC outside a World3D yet still ticks _physics_process).
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return
	# Anti-stuck: while escaping a blocker (flagged by _update_stuck last frame), steer ALONG it instead of
	# pressing straight at the path point. Only overrides when we're actually trying to move somewhere.
	if _unstick_t > 0.0 and _unstick_dir.length_squared() > 0.0001 and Vector2(_desired_velocity.x, _desired_velocity.z).length() > 0.1:
		_desired_velocity = _unstick_dir * _current_move_speed()
	var horizontal := Vector2(velocity.x, velocity.z)
	var desired_h := Vector2(_desired_velocity.x, _desired_velocity.z)
	# RVO avoidance: steer around other agents + dynamic obstacles. ONLY while actively moving and NOT mid
	# anti-stuck side-step — so idle/clustered NPCs report stationary (others route around them) without nudging
	# each other into a jitter, and the wall-slide isn't fought. Uses the previous frame's collision-free velocity
	# (1-frame lag; ≈ the request in the open, so it's a no-op with nothing nearby).
	if _nav != null and _nav.avoidance_enabled:
		if desired_h.length() > 0.3 and _unstick_t <= 0.0:
			_nav.velocity = Vector3(desired_h.x, 0.0, desired_h.y)
			if _avoid_ready:
				desired_h = Vector2(_avoid_velocity.x, _avoid_velocity.z)
		else:
			_nav.velocity = Vector3.ZERO  # idle/stuck -> report stationary; don't nudge neighbors (kills the idle shimmy)
	var rate := move_accel if is_on_floor() else air_accel
	horizontal = horizontal.move_toward(desired_h, rate * get_physics_process_delta_time())
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	var was_grounded := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_grounded:
		_apply_fall_damage(-pre_move_velocity.y)
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor
	_update_stuck(get_physics_process_delta_time())
```

**AFTER**:
```gdscript
func apply_velocity() -> void:
	# move_and_slide needs a live physics space; bail when we're not in one (e.g. a unit
	# test instantiates the NPC outside a World3D yet still ticks _physics_process).
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return
	# Anti-stuck override (state now on the Locomotor): while escaping a blocker (flagged by Locomotor.update_stuck
	# last frame), steer ALONG it instead of pressing straight at the path point. Only when actually trying to move.
	var unstick_t: float = _locomotor._unstick_t if _locomotor != null else 0.0
	var unstick_dir: Vector3 = _locomotor._unstick_dir if _locomotor != null else Vector3.ZERO
	if unstick_t > 0.0 and unstick_dir.length_squared() > 0.0001 and Vector2(_desired_velocity.x, _desired_velocity.z).length() > 0.1:
		_desired_velocity = unstick_dir * _current_move_speed()
	var horizontal := Vector2(velocity.x, velocity.z)
	var desired_h := Vector2(_desired_velocity.x, _desired_velocity.z)
	# RVO avoidance: steer around other agents + dynamic obstacles. ONLY while actively moving and NOT mid
	# anti-stuck side-step — so idle/clustered NPCs report stationary (others route around them) without nudging
	# each other into a jitter, and the wall-slide isn't fought. Uses the previous frame's collision-free velocity
	# (1-frame lag; ≈ the request in the open, so it's a no-op with nothing nearby).
	if _nav != null and _nav.avoidance_enabled:
		if desired_h.length() > 0.3 and unstick_t <= 0.0:
			_nav.velocity = Vector3(desired_h.x, 0.0, desired_h.y)
			if _avoid_ready:
				desired_h = Vector2(_avoid_velocity.x, _avoid_velocity.z)
		else:
			_nav.velocity = Vector3.ZERO  # idle/stuck -> report stationary; don't nudge neighbors (kills the idle shimmy)
	var rate := move_accel if is_on_floor() else air_accel
	horizontal = horizontal.move_toward(desired_h, rate * get_physics_process_delta_time())
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	var was_grounded := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_grounded:
		_apply_fall_damage(-pre_move_velocity.y)
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor
	# Anti-stuck bookkeeping LAST — after move_and_slide (fresh slide-collision normals + is_on_floor) and after the
	# blast decay (so a still-live blast bails). Now on the Locomotor; it writes _unstick_t/_unstick_dir for next frame
	# and calls back into _note_stranded / _reset_stranded (which own our _stranded_cycles). No-op off-tree / pre-build.
	if _locomotor != null:
		_locomotor.update_stuck(self, get_physics_process_delta_time())
```

### 2f. `_update_stuck` DELETED; add `_note_stranded` host callback + a `_reset_stranded` host callback

`_update_stuck` (npc.gd:2160-2222) is DELETED — its body is now `Locomotor.update_stuck`. `wall_slide_dir` becomes a
forwarding shell (2h). `_note_stranded` STAYS (it owns `_stranded_cycles` via `_tick_stranded`), but Locomotor now
calls it via `body.call(&"_note_stranded")`. Add `_reset_stranded` for the progress-reset path (Locomotor calls it
where npc.gd used to inline `_stranded_cycles = 0; _stranded_warned = false`).

**BEFORE** (npc.gd:2152-2251) — the doc-comment block + `_update_stuck` + `wall_slide_dir` + `_note_stranded` +
`_tick_stranded`:
```gdscript
## Anti-stuck: when the NPC WANTS to move but a WALL is eating its velocity (it's pressed against a near-
## vertical surface AND its actual speed is well below the intended), veer ALONG that wall toward the goal
## for UNSTICK_TIME so it slips around instead of grinding in place. apply_velocity applies the resulting
## _unstick_dir while _unstick_t is live; two NPCs pressing on each other get opposite contact normals, so
## they steer apart. CRITICAL: the floor a grounded NPC stands on is a slide collision too, so we ignore
## floor/ramp contacts (near-vertical normals only) — otherwise every grounded NPC reads as "stuck" and
## side-steps forever, which on a knocked-back NPC compounds with the blast and flings it away. Likewise we
## bail while a blast is still live so anti-stuck never fights knockback.
func _update_stuck(delta: float) -> void:
	if _unstick_t > 0.0:
		_unstick_t -= delta
	if _jump_cd > 0.0:
		_jump_cd -= delta  # cooling down between nav-driven hops so a climb can't bounce
	if _stuck_hold_t > 0.0:
		_stuck_hold_t -= delta  # counting down a "given up — holding still" pause
	if is_on_floor():
		_hopping = false  # back on the ground — the self-hop latch only spans OUR airborne arc, never a later blast/fall
	var intended := Vector2(_desired_velocity.x, _desired_velocity.z).length()
	# Not trying to move, airborne, or still being knocked back -> not "stuck" (don't fight a blast). EXCEPTION:
	# the airborne frames of our OWN nav-hop (_hopping, set at hop-fire, cleared above on landing) still count as
	# "trying" — otherwise a hop that keeps failing to mount a too-tall/edge crate would reset the give-up clock
	# every flight and pogo forever. (We can't use _jump_cd here: flight time ~0.92 s > JUMP_COOLDOWN 0.8 s, so the
	# cooldown lapses mid-air and the tail frames would reset.) Counting our hop lets _stuck_persist accumulate, so a
	# futile pogo converts to "give up and hold" (then it stands + fires). A blast still bails: it sets
	# explosion_velocity (the third term) and is airborne with _hopping false, so it never counts as "trying".
	if intended < 0.1 or (not is_on_floor() and not _hopping) or explosion_velocity.length() > 1.0:
		_stuck_t = 0.0
		_stuck_persist = 0.0
		return
	if Vector2(velocity.x, velocity.z).length() >= intended * STUCK_SPEED_FRAC:
		_stuck_t = 0.0
		_stuck_persist = 0.0
		_stranded_cycles = 0       # made real progress -> not stranded; re-arm the warning for a future episode
		_stranded_warned = false
		return  # moving along fine — still making progress
	# We WANT to move but aren't. Accumulate the give-up clock: after STUCK_GIVEUP_TIME of trying (side-stepping and
	# STILL not getting anywhere), STOP and just HOLD for STUCK_HOLD_TIME instead of shuffling back and forth
	# forever. _move_toward returns false while holding, so a wanderer re-picks a spot and a pursuer holds + fires;
	# then we retry. This is the anti-"walking back and forth in place" — it fails softly on a bad/cluttered navmesh.
	_stuck_persist += delta
	if _stuck_persist >= STUCK_GIVEUP_TIME:
		_stuck_persist = 0.0
		_stuck_t = 0.0
		_unstick_t = 0.0
		_stuck_hold_t = STUCK_HOLD_TIME
		_note_stranded()  # diagnostic only: warn once if we keep giving up in the SAME spot (likely a bad-bake island)
		return
	# Graceful-fail: if there's genuinely NO navmesh path to the goal (the player's on a disconnected island, or
	# we're wedged on clutter), side-stepping can't find one — it only produces the back-and-forth "shuffle". Skip
	# the unstick so the NPC just holds + keeps facing/firing instead of grinding. A REACHABLE target still
	# side-steps around the wall as before. (A bad/fragmented navmesh is the root cause — this only fails softly.)
	if _nav != null and not _nav.is_target_reachable():
		_stuck_t = 0.0
		return
	# Find a WALL we're jammed against (near-horizontal contact normal); skip the floor/ramp we stand on.
	var wall_normal := Vector3.ZERO
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) < 0.7:
			wall_normal = n
			break
	if wall_normal == Vector3.ZERO:
		_stuck_t = 0.0
		return  # only touching the floor — not pressed against a wall
	_stuck_t += delta
	if _stuck_t < STUCK_TIME:
		return
	_stuck_t = 0.0
	var want := Vector3(_desired_velocity.x, 0.0, _desired_velocity.z).normalized()
	_unstick_dir = wall_slide_dir(wall_normal, want)  # steer along the wall, toward the goal
	_unstick_t = UNSTICK_TIME

## Pure steering math: given the contact normal of the WALL we're jammed against and the direction we WANT to
## head, return the unit horizontal direction ALONG that wall toward the goal — the wall tangent on the side
## with a non-negative dot to `want`. Split out static so _update_stuck's side-selection is unit-testable (the
## rest of _update_stuck is in-tree physics state — playtested).
static func wall_slide_dir(wall_normal: Vector3, want: Vector3) -> Vector3:
	var tangent := Vector3(-wall_normal.z, 0.0, wall_normal.x).normalized()
	return tangent if tangent.dot(want) >= 0.0 else -tangent

## Diagnostic only (NO behaviour change): when we keep hitting the give-up hold in the SAME spot, we're probably
## STRANDED on an unreachable navmesh island — a prop/car roof the bake shouldn't have made walkable. Warn ONCE,
## with the NPC name + position, so a playtest pinpoints which prop to carve. In-tree only (global_position).
func _note_stranded() -> void:
	if not is_inside_tree():
		return
	var pos := global_position
	if _tick_stranded(pos) and not _stranded_warned:
		_stranded_warned = true
		push_warning("NPC '%s' looks STRANDED at (%.1f, %.1f, %.1f) — repeatedly stuck in one spot. Likely an unreachable navmesh island (a prop/car roof the bake made walkable). Carve that prop with a NavBlocker(CARVE) + re-bake, or File -> Run audit_navmesh.gd to locate it." % [display_name, pos.x, pos.y, pos.z])

## Pure counter (testable off-tree): same-spot give-ups accumulate; one far from the last resets the run. Returns
## true once the run of same-spot give-ups crosses the stranded threshold (3 ~= 10 s wedged in place).
func _tick_stranded(pos: Vector3) -> bool:
	if pos.distance_to(_last_giveup_pos) < 1.5:
		_stranded_cycles += 1
	else:
		_stranded_cycles = 1
	_last_giveup_pos = pos
	return _stranded_cycles >= 3
```

**AFTER**:
```gdscript
## Anti-stuck / wall-slide + the give-up state machine MIGRATED to Locomotor (Phase B) — see Locomotor.update_stuck,
## called LAST from apply_velocity. wall_slide_dir is a forwarding shell (below) so NPC.wall_slide_dir still resolves
## for the tests. These two host callbacks let Locomotor drive the STRANDED diagnostic, whose counter (_stranded_cycles)
## stays here because soak_harness reads host._stranded_cycles and test_ranged_behavior calls host._tick_stranded.

## Diagnostic only (NO behaviour change): when we keep hitting the give-up hold in the SAME spot, we're probably
## STRANDED on an unreachable navmesh island — a prop/car roof the bake shouldn't have made walkable. Warn ONCE,
## with the NPC name + position, so a playtest pinpoints which prop to carve. In-tree only (global_position).
## Called by Locomotor.update_stuck at the give-up point (body.call(&"_note_stranded")).
func _note_stranded() -> void:
	if not is_inside_tree():
		return
	var pos := global_position
	if _tick_stranded(pos) and not _stranded_warned:
		_stranded_warned = true
		push_warning("NPC '%s' looks STRANDED at (%.1f, %.1f, %.1f) — repeatedly stuck in one spot. Likely an unreachable navmesh island (a prop/car roof the bake made walkable). Carve that prop with a NavBlocker(CARVE) + re-bake, or File -> Run audit_navmesh.gd to locate it." % [display_name, pos.x, pos.y, pos.z])

## Made real progress -> not stranded; re-arm the one-shot warning for a future episode. Called by Locomotor.update_stuck
## on the progress path (body.call(&"_reset_stranded")). Replaces the inline `_stranded_cycles = 0; _stranded_warned = false`.
func _reset_stranded() -> void:
	_stranded_cycles = 0
	_stranded_warned = false

## Pure counter (testable off-tree): same-spot give-ups accumulate; one far from the last resets the run. Returns
## true once the run of same-spot give-ups crosses the stranded threshold (3 ~= 10 s wedged in place).
func _tick_stranded(pos: Vector3) -> bool:
	if pos.distance_to(_last_giveup_pos) < 1.5:
		_stranded_cycles += 1
	else:
		_stranded_cycles = 1
	_last_giveup_pos = pos
	return _stranded_cycles >= 3
```

### 2g. `_build_nav` — unchanged (keeps building `_nav`; injected into Locomotor). No edit.

`_build_nav` (npc.gd:1645-1659) and `_on_avoidance_velocity` (1663-1665) STAY VERBATIM. `_nav` is still the single
agent; Locomotor uses it via `external_nav`. `_on_avoidance_velocity` still fills `_avoid_velocity`/`_avoid_ready`
that `apply_velocity` adopts. **No edit to these two.**

### 2h. Pure-static forwarding shells — replace the 4 static bodies + the helper

The static BODIES moved to Locomotor. npc.gd keeps forwarding shells so all `NPC.<static>` test asserts stay green
with zero test churn. Replace the 5 statics (`jump_velocity_for_climb`, `should_nav_hop`, `collision_bottom_y`,
`_collision_shape_bottom_y`, `wall_slide_dir`) with shells.

**BEFORE** (npc.gd:1922-1959):
```gdscript
static func jump_velocity_for_climb(climb: float, grav: float, base_velocity: float) -> float:
	var base := maxf(base_velocity, 0.0)
	var g := absf(grav)
	if climb <= 0.0 or g <= 0.0:
		return base
	return maxf(base, sqrt(2.0 * g * (climb + HOP_HEIGHT_MARGIN)))
```
...through `_collision_shape_bottom_y` at 1955-1959 (all four consecutive statics + helper).

**AFTER** (forwarding shells — same signatures, delegate to Locomotor):
```gdscript
static func jump_velocity_for_climb(climb: float, grav: float, base_velocity: float) -> float:
	return Locomotor.jump_velocity_for_climb(climb, grav, base_velocity)

static func should_nav_hop(allow_hop: bool, hop_velocity: float, on_floor: bool, jump_cooldown: float, climb: float, horizontal_distance: float) -> bool:
	return Locomotor.should_nav_hop(allow_hop, hop_velocity, on_floor, jump_cooldown, climb, horizontal_distance)

static func collision_bottom_y(node: Node3D, fallback_y: float) -> float:
	return Locomotor.collision_bottom_y(node, fallback_y)

static func _collision_shape_bottom_y(col: CollisionShape3D, fallback_y: float) -> float:
	return Locomotor._collision_shape_bottom_y(col, fallback_y)
```

And REPLACE `wall_slide_dir` (npc.gd:2228-2230) with a shell:

**BEFORE**:
```gdscript
static func wall_slide_dir(wall_normal: Vector3, want: Vector3) -> Vector3:
	var tangent := Vector3(-wall_normal.z, 0.0, wall_normal.x).normalized()
	return tangent if tangent.dot(want) >= 0.0 else -tangent
```

**AFTER**:
```gdscript
static func wall_slide_dir(wall_normal: Vector3, want: Vector3) -> Vector3:
	return Locomotor.wall_slide_dir(wall_normal, want)
```

> Keep the doc-comments above each; only the bodies change. `_nav_hop_target_climb` (1961-1964) and `_try_nav_hop`
> (2043-2049) are DELETED entirely (moved to Locomotor, internal-only).

### 2i. `_face_travel` / `_face_point` / `_face_yaw` — NO CHANGE, they STAY

RECON confirmed: `_face_yaw` uses the FR-independent `1.0 - exp(-turn_speed * delta)` curve; Locomotor's `_face` uses a
different one. The 8+ callers pass explicit targets/yaws. **These three methods stay verbatim on npc.gd** (npc.gd:2051,
2254, 2261). Locomotor's `face_travel=false` means Locomotor never touches `body.rotation`. **No edit.**

---

## 3. Tests

**No re-pointing needed for the static tests** — the forwarding shells (2h) keep `NPC.jump_velocity_for_climb`,
`NPC.should_nav_hop`, `NPC.collision_bottom_y`, `NPC.wall_slide_dir` resolving with identical behaviour. `NPC.STUCK_TIME`
/ `UNSTICK_TIME` / `STUCK_SPEED_FRAC` still resolve (const aliases, 2a). `test_ranged_behavior` calls
`e._tick_stranded(...)` — STAYS on npc.gd, unchanged.

**ONE test MUST change:** `test_npc.gd:124-135` (`test_npc_anti_stuck_unstick_timer_counts_down_and_is_off_tree_safe`)
writes `n._unstick_t` and calls `n._update_stuck(0.1)` on the NPC instance. `_update_stuck` and `_unstick_t` are GONE
from npc.gd (moved to Locomotor). This test must be re-pointed to the Locomotor, OR (cleaner for an off-tree test) to
`Locomotor.update_stuck` directly.

**BEFORE** (test_npc.gd:124-135):
```gdscript
func test_npc_anti_stuck_unstick_timer_counts_down_and_is_off_tree_safe() -> void:
	# _update_stuck runs each physics frame after move_and_slide. Off-tree (no add_child) is_on_floor() is
	# false so it early-returns, but it must still tick the unstick timer DOWN (so the steer expires and the
	# NPC resumes normal pathing) and never crash on the missing physics state.
	var n = load(NPC_PATH).new()
	n._unstick_t = NPC.UNSTICK_TIME
	n._update_stuck(0.1)
	assert_almost_eq(n._unstick_t, NPC.UNSTICK_TIME - 0.1, 0.0001,
		"the unstick steer timer counts down each tick so the NPC stops wall-following after UNSTICK_TIME")
	assert_eq(n._stuck_t, 0.0,
		"off-tree (not on the floor) _update_stuck resets the stuck timer and bails — no false 'stuck' without ground contact")
	n.free()
```

**AFTER** (re-point to the Locomotor, driving it off-tree with a bare CharacterBody3D host — mirrors how the NPC calls
it, `update_stuck(self, delta)`; off-tree `is_on_floor()` is false so it early-returns after ticking the timer):
```gdscript
func test_locomotor_unstick_timer_counts_down_and_is_off_tree_safe() -> void:
	# The anti-stuck timers migrated from npc._update_stuck to Locomotor.update_stuck (Phase B). Off-tree (a bare body,
	# not on the floor) it early-returns, but must still tick the unstick timer DOWN so the steer expires, and never
	# crash on the missing physics state. Drive it the way the NPC does: loco.update_stuck(body, delta).
	var body := CharacterBody3D.new()
	var loco := Locomotor.new()
	body.add_child(loco)
	loco._unstick_t = Locomotor.UNSTICK_TIME
	loco.update_stuck(body, 0.1)
	assert_almost_eq(loco._unstick_t, Locomotor.UNSTICK_TIME - 0.1, 0.0001,
		"the unstick steer timer counts down each tick so the NPC stops wall-following after UNSTICK_TIME")
	assert_eq(loco._stuck_t, 0.0,
		"off-tree (not on the floor) update_stuck resets the stuck timer and bails — no false 'stuck' without ground contact")
	body.free()  # frees loco too (child)
```

> `Locomotor.update_stuck` off-tree: `body.is_on_floor()` is false, `desired_velocity` is ZERO so `intended < 0.1` →
> the `if intended < 0.1 or ...` branch resets `_stuck_t=0`, `_stuck_persist=0`, returns — AFTER the three timer
> decrements at the top ran. So `_unstick_t` ticks to `UNSTICK_TIME - 0.1` and `_stuck_t` is 0. Same assertion values
> as the old test. `_host_blast_len(body)` reads `body.get(&"explosion_velocity")` → a bare CharacterBody3D has no such
> property → `null` → not a Vector3 → returns 0.0 (safe, no crash). GOOD.
>
> `NPC_PATH` may be unused after this if no other test uses it — grep before deleting the const (leave it if other tests
> reference it; harmless if unused-but-referenced-elsewhere).

**Optional new coverage (recommended, not required):** an off-tree test that `Locomotor.drive_move_to` on a bare body
with no target returns false and leaves `desired_velocity` ZERO — pins the driven-mode entry contract. Off-tree
`_nav == null` (never `_ready`'d without a tree) → `drive_move_to` returns false immediately. Cheap and safe.

---

## (a) BEHAVIOR-EQUIVALENCE ARGUMENT — frame-by-frame

The claim: for an in-tree NPC, the drafted `apply_velocity` produces the **same `velocity` after `move_and_slide` and
the same post-frame state** as today, and `_move_toward` returns the **same bool** with the **same `_desired_velocity`**.

**Setup (unchanged):** `Character._physics_process` runs `gravity(delta)` → `apply_blast()` → `apply_velocity()`
(character.gd:790-793). NPC's brain writes `_desired_velocity` earlier in the same frame (via a `_move_toward` shell
call from a behaviour), then `super._physics_process` reaches `apply_velocity`. Gravity is already in `velocity.y`;
`explosion_velocity` is already armed. **None of that ordering moved.**

**`_move_toward` frame:** Today, npc.gd `_move_toward` sets `_desired_velocity` and may punch `velocity.y` (hop). After:
the shell calls `_locomotor.drive_move_to(target, allow_hop, hop_target)`, which:
1. `move_to(target)` sets `_nav.target_position = target` — **same as npc.gd:1998 `_nav.target_position = target`**,
   on the **same `_nav`** (injected). NOTE: `move_to` also re-arms `_arrived=false`/`_blocked_notified=false` each call.
   That is benign: the NPC calls `_move_toward` every frame it wants to move, so re-arming per-frame matches npc.gd,
   which had no `_arrived` latch at all (it recomputed from scratch each frame). `reached_target`/`path_blocked` signals
   are new emissions but **nothing is connected to them on the NPC** (the NPC never wired those signals; they're for
   autonomous drop-in users) — so they're inert. Verify no connection exists (grep: none).
2. `_compute_desired(body, speed, allow_hop, hop_target)` reproduces npc.gd `_move_toward`'s branch tree:
   - `_stuck_hold_t > 0` → ZERO + `_arrived=true` → `drive_move_to` returns `false`. **Matches npc.gd:1978-1979
     `return false`.** (`_desired_velocity` copied = ZERO; npc.gd left it ZERO from the per-frame reset — SAME.)
   - nav-map not ready → ZERO. npc.gd's off-mesh block was gated on `is_nav_map_ready`; its MAIN path
     (`_nav.target_position=…; is_navigation_finished()`) did NOT gate on map-ready and would query anyway. **Minor
     divergence:** before first sync, npc.gd would still call `is_navigation_finished()` (returns true on an unsynced
     agent → treated as arrived → ZERO, returns false). After: we return ZERO earlier (same ZERO, returns false). Net
     `_desired_velocity` = ZERO both ways in the pre-sync window; bool = false both ways. **Equivalent.** (This is
     strictly SAFER — it removes a pre-sync query, aligning with the nav-map-query-before-sync memory note.)
   - off-mesh recovery: identical condition (`_stuck_persist > 0.5`, `map_get_closest_point`, `> OFF_MESH_RECOVER_DIST`,
     `flat.length() > 0.1`) → `flat.normalized() * speed`, returns true. `speed = host._current_move_speed()` = npc.gd's
     `_current_move_speed()`. **Identical vector, identical true.** (npc.gd also gated on `is_inside_tree()`; in driven
     mode we're only called in-tree from apply_velocity's frame, and `_nav != null` guaranteed — equivalent.)
   - reachable normal path: `get_next_path_position() - self_pos`, `< 0.05 → to_target`. **Identical to npc.gd:2000-2007.**
   - unreachable: `to_next = to_target`; `< 0.5 and not hop → arrived/ZERO/false`. **Identical to npc.gd:2008-2013**
     (npc.gd returned false; we set `_arrived=true` + ZERO → `drive_move_to` returns false). The `path_blocked.emit()`
     is the only addition — inert (unconnected).
   - hop: same `hop_climb`/`hop_horizontal` selection (`target_flat_distance < HOP_STEP_DISTANCE and target_climb >
     hop_climb`), same `should_nav_hop(...)` gate with `hop_velocity = host.jump_velocity`, same
     `body.velocity.y = jump_velocity_for_climb(...)`, same `_jump_cd`/`_hopping` set — **but on the Locomotor's
     `_jump_cd`/`_hopping`.** Since `should_nav_hop`/`update_stuck` also now read the Locomotor's copies, the hop
     cooldown/latch loop is internally consistent. `body.velocity.y` write hits the **same host `velocity.y`**.
     **Identical vertical impulse.**
   - final: `to_next.normalized() * speed`, returns true. **Identical to npc.gd:2038-2041.**
3. `drive_move_to` returns `desired_velocity.length_squared() > 0.0001 or _hopping`. npc.gd returned `true` exactly when
   it set a non-zero `_desired_velocity` OR (in the arrived-but-hopped branch, npc.gd:2015-2016) when a hop fired with
   `_desired_velocity` left ZERO. Our `or _hopping` reproduces that arrived-hop `return true`. **Bool identical.**
   The shell then copies `_locomotor.desired_velocity` → `_desired_velocity`. **Same value the NPC had before.**

**`apply_velocity` frame (steps, post-`_move_toward`):**
- Step 0 world guard — **verbatim.**
- Step 1 unstick override — reads `_locomotor._unstick_t`/`_unstick_dir` instead of local `_unstick_t`/`_unstick_dir`.
  These are the SAME values (the state simply lives on the Locomotor now; `update_stuck` writes them, this reads them
  next frame — the cross-frame handoff is preserved because both writer and reader use `_locomotor.*`). Guard + formula
  `_desired_velocity = unstick_dir * _current_move_speed()` — **identical.**
- Step 2 RVO — `_nav` is the SAME agent; gate `desired_h.length() > 0.3 and unstick_t <= 0.0` with `unstick_t` =
  `_locomotor._unstick_t` — **identical to the old `_unstick_t <= 0.0`.** `_avoid_ready`/`_avoid_velocity` still filled
  by the SAME `_on_avoidance_velocity` on the SAME agent. **Identical.**
- Steps 3-9 (`rate`/`move_toward`/x/z, `+= explosion_velocity`, capture, `move_and_slide`, fall-damage, push, decay) —
  **verbatim, untouched.**
- Step 10 — `_locomotor.update_stuck(self, dt)` instead of `_update_stuck(dt)`. The body is byte-identical (lifted),
  reading `body.velocity`/`body.is_on_floor()`/`body.get_slide_collision*`/`body.get(&"explosion_velocity")` =
  `self.*` = the SAME post-slide state. It writes `_locomotor._unstick_t`/`_unstick_dir` that step 1 reads next frame,
  and calls `self._note_stranded()`/`self._reset_stranded()` driving the SAME `_stranded_cycles`. **Identical effect.**

**Conclusion:** every velocity-affecting term is either byte-identical or reads/writes the SAME host state through a
relocated-but-equivalent member. The only new observable events (`reached_target`/`path_blocked` emissions) are
unconnected on the NPC and thus inert. **Velocity output is equivalent frame-for-frame.**

---

## (b) npc.gd MEMBERS: DEAD/REMOVABLE vs MUST-STAY (with the pin)

**REMOVED (moved to Locomotor; no external reader):**
| Member | Was | Now |
|---|---|---|
| `_stuck_t`, `_unstick_t`, `_unstick_dir`, `_stuck_persist`, `_stuck_hold_t`, `_jump_cd`, `_hopping` (378-384) | local state | on `Locomotor`; apply_velocity reads `_locomotor._unstick_t/_unstick_dir` |
| `_update_stuck` (2160-2222) | method | `Locomotor.update_stuck` |
| `_try_nav_hop` (2043-2049) | internal method | `Locomotor._try_hop` (internal-only; grep-confirm no external caller) |
| `_nav_hop_target_climb` (1961-1964) | internal method | `Locomotor._hop_target_climb` (internal-only) |
| Bodies of `jump_velocity_for_climb`/`should_nav_hop`/`collision_bottom_y`/`_collision_shape_bottom_y`/`wall_slide_dir` | full bodies | forwarding shells to `Locomotor.<x>` |
| 10 anti-stuck/hop const literals | literals | `const … := Locomotor.<X>` aliases |

**MUST STAY (external reader pins each):**
| Member | Pinned by |
|---|---|
| `_nav` (354) + `_build_nav` (1645) | `companion_follow.gd:83,99,126,127` read `host._nav` |
| `_on_avoidance_velocity` (1663) + `_avoid_velocity`/`_avoid_ready` (355-356) | `apply_velocity` step 2 adopts `_avoid_velocity`; wired to `_nav.velocity_computed` |
| `apply_velocity` (2115) | INVARIANT 1 — sole `move_and_slide` writer; Character virtual override |
| `_move_toward` (signature) | 9 caller files + `_tick_cutscene_movement` (npc.gd:2291) |
| `_face_travel`/`_face_point`/`_face_yaw` (2051/2254/2261) | 8+ callers via `host._face_*`; `_face_yaw`'s FR-independent curve |
| `_snap_to_navmesh` (2081) | `npc_locomotion.gd:57,125`; internal `_pick_wander_point` |
| `_pick_wander_point` (2070) | INVARIANT 3; `test_ranged_behavior` |
| `_height_above_floor` (2095) | `companion_follow.gd:112` |
| `_stranded_cycles` (385) | `soak_harness.gd:150` `n.get(&"_stranded_cycles")` |
| `_tick_stranded` (2245) | `test_ranged_behavior.gd:43-46` `e._tick_stranded(...)` |
| `_note_stranded` (2235) | now also `Locomotor.update_stuck` via `body.call(&"_note_stranded")` |
| `_last_giveup_pos`/`_stranded_warned` (386-387) | used by `_tick_stranded`/`_note_stranded` (host-owned) |
| statics `jump_velocity_for_climb`/`should_nav_hop`/`collision_bottom_y`/`wall_slide_dir` (as SHELLS) | `test_enemies.gd:311-362`, `test_npc.gd:111,118` call `NPC.<static>` |
| consts `STUCK_TIME`/`UNSTICK_TIME`/`STUCK_SPEED_FRAC` (as aliases) | `test_npc.gd:102-107` read `NPC.<CONST>` |
| `_current_move_speed` (2540) | apply_velocity step 1; Locomotor reads it via `host._current_move_speed()` |
| NEW `_reset_stranded` | called by `Locomotor.update_stuck` on the progress path |

---

## (c) RESIDUAL RISK — `:=` / dispatch / caller-signature

1. **`:=`-off-Variant (INVARIANT 5):** every moved host read in Locomotor is EXPLICITLY annotated, never `:=`:
   `_host_move_speed` → `var v: Variant = body.call(...)`; `_host_blast_len` → `var v: Variant = body.get(...)` then
   `(v as Vector3)`; `_hop_target_climb` → `var target_floor: float = …`, `var self_floor: float = …`;
   `_try_hop`/`_compute_desired` → `var hop_velocity: float = _host_jump_velocity(body)`. Inside `update_stuck`,
   `var blast_len: float = _host_blast_len(body)` (annotated), and `var intended := Vector2(desired_velocity...)` /
   `var want := Vector3(desired_velocity...)` infer off Locomotor's OWN typed `desired_velocity: Vector3` (NOT a host
   Variant) → `:=` is SAFE there. `for i in body.get_slide_collision_count()` and `var n := body.get_slide_collision(i)
   .get_normal()` — `get_slide_collision_count()`/`get_slide_collision()` are real typed `CharacterBody3D` methods
   (`body` is typed `CharacterBody3D`), so `:=` infers `int`/`Vector3` correctly. **No `:=` trap remains.**
   - In npc.gd's `apply_velocity` shell: `var unstick_t: float = _locomotor._unstick_t if _locomotor != null else 0.0`
     and `var unstick_dir: Vector3 = _locomotor._unstick_dir if …` — `_locomotor` is typed `Locomotor`, so `._unstick_t`
     is a known `float` and `._unstick_dir` a known `Vector3`; annotated anyway for clarity. Safe either way.

2. **Dispatch-by-name:** `apply_velocity` is a plain polymorphic override (NOT string dispatch — RECON corrected the
   CONTEXT). It stays the override on npc.gd; `Character._physics_process` still calls `apply_velocity()` polymorphically.
   No dispatch risk. Locomotor→host callbacks use `body.call(&"_note_stranded")`/`&"_reset_stranded"`/`&"_current_move_speed"`
   guarded by `has_method` — a bare-mob host without them degrades neutrally (no crash), an NPC host resolves them.

3. **Caller signatures:** `_move_toward(target: Vector3, allow_hop := false, hop_target: Node3D = null) -> bool` is kept
   VERBATIM (note: the shell uses `allow_hop := false` inferred-default form — the SAME as the original; do not switch
   to `allow_hop: bool = false`, both compile identically but keep the original token to minimise diff surface). All 13
   call sites (9 external files + cutscene internal) pass positional args that still bind. `_face_*`, `_snap_to_navmesh`,
   `_height_above_floor`, `_nav`, `_tick_stranded`, `_stranded_cycles` unchanged. **No caller breaks.**

4. **Class-cache / parse-order:** npc.gd now references `Locomotor` at parse time (const aliases + shells + typed var).
   `Locomotor` has `class_name`, so it's in the global cache — but a STALE cache after adding `external_nav`/the new
   consts can throw "Could not find type Locomotor" cascading Nil-autoload GUT failures (memory:
   new-classname-not-registered-cascade). MITIGATION: `godot --headless --import` once before running GUT/playtest.
   No `class_name↔preload` cycle risk: npc.gd references `Locomotor` by class_name only (no `preload` of a scene that
   type-refs NPC), and Locomotor never references `NPC` (duck-typed). **No cyclic reference.**

5. **`external_nav` timing:** `_build_locomotor()` runs at npc.gd:437 (after `_build_nav` at line—now—438-adjacent),
   sets `external_nav` BEFORE `add_child(_locomotor)` → Locomotor's `_ready` sees the injected agent. If a future
   refactor moves the Locomotor build into `_build_components` (before `_build_nav`), `external_nav` would be null and
   Locomotor would build a SECOND agent — the double-RVO regression. Guard against it: keep `_build_locomotor` AFTER
   `_build_nav` (the inserted call site enforces this). Flagged as an ordering invariant in the method's doc-comment.

6. **`move_to` per-frame re-arm:** `drive_move_to` calls `move_to` every frame, which resets `_arrived`/`_blocked_notified`.
   This means `reached_target`/`path_blocked` COULD re-fire each frame if something connected them. Nothing on the NPC
   does (verified: no `_locomotor.reached_target.connect`). If a future feature wires them, it must debounce. Flagged.

7. **Autonomous-mode enrichment:** bare-mob Locomotor now runs the give-up/off-mesh/hop code in `_compute_desired`. With
   `allow_hop=false` the hop never fires; `_stuck_persist`/`_stuck_hold_t` stay 0 unless something calls `update_stuck`
   (autonomous `_drive` does NOT), so off-mesh recovery + give-up are inert for autonomous hosts. **Autonomous behaviour
   unchanged.** If a future autonomous user wants anti-stuck, they'd call `update_stuck` from a post-move hook — not in
   scope here.

**DOCS IMPACT:** `scripts/npc/README.md` (facade list: `_move_toward`/`_face_*`/`_desired_velocity`/`_nav` now note
Locomotor delegation) and `scripts/components/README.md` (Locomotor now carries hop/anti-stuck/off-mesh + driven-mode
`drive_move_to`/`update_stuck`/`external_nav`) must be updated in the same apply. The locomotor.gd module docstring
(lines 19-21, "DELIBERATELY NOT in this baseline…") must be rewritten since those features now ARE in it.

---

# CORRECTIONS FROM ADVERSARIAL REVIEW (apply these ON TOP of the §1–§3 patch)

The 4-lens review found the patch ~95% sound but flagged one real bug plus equivalence/doc nits. Apply all of these
to the drafted patch **before** applying it to the live files. Line numbers refer to `locomotor_phase_b_patch.md`
(this document's §1–§3), verified against the drafted blocks.

## CORRECTION 1 — the real bug: `drive_move_to`'s `or _hopping` diverges from live's bool contract

**Found by BOTH the equivalence and test-and-cache lenses.** The drafted `drive_move_to` (patch line 303) returns
`desired_velocity.length_squared() > 0.0001 or _hopping`. The `_hopping` latch is the *persistent airborne* flag —
it stays true across a whole hop arc. Live `_move_toward` returns `true` only when it produced steering **or an
arrived-branch hop fired THIS frame** (never off a lingering airborne latch). So the draft reports "still travelling"
where live reported "arrived / given-up hold" in two cases:
- **give-up-hold while still airborne from a futile pogo** (`_stuck_hold_t > 0`, `_hopping` still true): live returned
  `false` (npc.gd:1978-1979), draft returns `true` → a wanderer that should re-pick keeps its stale "moving" flag.
- **arrived within 0.5 m of an unreachable target while mid-hop** (no new hop this frame): live returned `false`
  (npc.gd:2013), draft returns `true`.

**Fix — replace the persistent latch with a per-frame "hopped this frame" flag** (subsumes both cases):

1. Add state alongside the other lifted anti-stuck vars (patch §1b, near `_hopping`):
   ```gdscript
   var _hopped_this_frame: bool = false  ## true only on the tick a hop actually fires — the "still travelling" bool
                                         ## uses THIS, not the persistent airborne _hopping latch (give-up-hold + arrived
                                         ## frames must read "not travelling" even while _hopping is still latched).
   ```
2. In `_try_hop` (patch ~280-287), set it where the hop fires — insert before `return true` (after `_hopping = true`):
   ```gdscript
   	_hopped_this_frame = true
   	return true
   ```
3. In the `_compute_desired` INLINE hop (patch ~256-259), after `_hopping = true`:
   ```gdscript
   		_jump_cd = JUMP_COOLDOWN
   		_hopping = true
   		_hopped_this_frame = true
   ```
4. In `drive_move_to` (patch ~293-303), clear it at entry and use it in the return:
   ```gdscript
   func drive_move_to(target: Vector3, allow_hop: bool, hop_target: Node3D) -> bool:
   	if _nav == null:
   		return false
   	move_to(target)
   	var body := get_parent() as CharacterBody3D
   	if body == null:
   		return false
   	_hopped_this_frame = false  # a hop that fires this call re-sets it in _compute_desired/_try_hop
   	var speed: float = _host_move_speed(body)
   	desired_velocity = _compute_desired(body, speed, allow_hop, hop_target)
   	# "Still travelling?" = we produced steering OR a hop fired THIS frame. Arrived / given-up-hold -> false so the
   	# caller re-picks / holds, even while the airborne _hopping latch is still set from a prior tick.
   	return desired_velocity.length_squared() > 0.0001 or _hopped_this_frame
   ```

## CORRECTION 2 — nav-map-ready gating: restore live structure so the pre-first-sync frame is truly equivalent

The drafted `_compute_desired` (patch lines 197-199) blanket-returns `Vector3.ZERO` when `not is_nav_map_ready`. Live
gates ONLY the off-mesh recovery block on map-ready and lets the MAIN path run before first sync (npc.gd:1988-1990 +
the unconditional 1998-2041). The blanket return changes the pre-sync frame from "charge straight at target" (live)
to "hold" (draft). The only call that actually ERRORS before sync is `NavigationServer3D.map_get_closest_point` in the
off-mesh block — `_nav.is_navigation_finished()`/`get_next_path_position()` do not. So restore the live structure:

1. **Delete** the blanket early-return (patch 197-199):
   ```gdscript
   	# (DELETE) if not NavigationUtils.is_nav_map_ready(_nav.get_navigation_map()): return Vector3.ZERO
   ```
2. **Gate the off-mesh block locally** (patch line 208) — matches live npc.gd:1988-1990:
   ```gdscript
   	if _stuck_persist > 0.5 and body.is_inside_tree() and NavigationUtils.is_nav_map_ready(_nav.get_navigation_map()):
   		var nav_map := _nav.get_navigation_map()
   		...
   ```
This keeps the `map_get_closest_point`-before-sync guard LOCAL and edit-proof, and lets the main pursuit path run
pre-sync exactly as live does. (Frame-order lens judged the blanket return "sufficient / no crash"; this correction
makes it byte-equivalent, so the "equivalent" claim is honest. If you'd rather keep the blanket hold, that's a
deliberate, playtest-gated behavior change — label it as such, don't call it equivalent.)

## CORRECTION 3 — same-apply doc edits + acknowledgements (no code behavior)

- **Update the stale header comment** `scripts/npc/npc_locomotion.gd:10-13` (currently "`DELIBERATELY NOT here:
  apply_velocity / _update_stuck / wall_slide_dir … all stay on npc.gd`"). After the migration, `_update_stuck` /
  `wall_slide_dir` **bodies move to Locomotor**; reword to: npc.gd keeps the `apply_velocity` shell + the forwarding
  static shells, and the anti-stuck state machine now lives on `Locomotor.update_stuck`. **Apply this WITH the
  migration, not before** — the comment is accurate on the CURRENT (un-migrated) code.
- **`tests/test_locomotor.gd` stays green** (verified): it exercises only `move_to`/`stop`/`is_moving`/signals/
  `_get_configuration_warnings` + the `_ready` `external_nav == null` path, all unchanged. Re-run it after applying;
  it is a *verified survivor*, not an unexamined one. (The patch §3 originally named only `test_npc.gd`.)
- **Cosmetic:** the patch prose at its own line ~1176 mis-describes the shell as using the `allow_hop := false`
  inferred-default form; the shell correctly uses `allow_hop: bool = false` (matching the original). Ignore the prose;
  keep the code.

---

# PRE-APPLY + PLAYTEST CHECKLIST

Do this in a session with the **editor closed** (so `--import` can refresh the class cache) and the game runnable:

1. **Apply** the §1–§3 patch + CORRECTIONS 1–3 above (TABS, not spaces).
2. **`godot --headless --import`** once (pass the ABSOLUTE project path — the spaced path silently fails on a bare
   `.`) so the class cache registers the widened `Locomotor` API. Then run GUT:
   `& "C:\Users\dalla\bin\godot.cmd" --headless --path . -s addons/gut/gut_cmdln.gd -gexit`
   Expect green, incl. the re-pointed `test_npc.gd` anti-stuck test + the unchanged `test_enemies.gd`/`test_locomotor.gd`
   static/API tests. Optionally run the opt-in soak (`tests_soak/`) + `combat_smoke_harness`.
3. **Playtest the movement seams** (the whole point — GUT can't cover `move_and_slide`/nav):
   - **RVO clustering** — several NPCs converging on you don't pile up / jitter (RVO feed + `_avoid_velocity` adopt).
   - **Combat nav-hop** — an armed NPC pursuing you onto a crate / low ledge hops up to reach you (not machine-gun
     pogo; a futile pogo converts to give-up + HOLD, doesn't pace).
   - **Anti-stuck / wall-slide** — an NPC pressed into a wall/prop/another NPC veers along it, then gives up and holds
     (no infinite shuffle); `update_stuck` reads this-frame contacts (it runs LAST in `apply_velocity`).
   - **Off-mesh recovery** — knock an NPC off the navmesh (explosion/ledge); it steers back onto walkable floor.
   - **Companion follow** — a recruited companion still tails + hidden-teleports (reads `host._nav` / `_height_above_floor`).
   - **Facing** — bodies still turn to face travel/aim smoothly, with NO twitch/fight (confirms `face_travel=false` on
     the NPC's Locomotor; npc.gd's `_face_yaw` stays the sole facer).
   - **Give-up bool** — a wanderer blocked at a wander point re-picks (doesn't freeze reporting "still moving");
     a pursuer at an unreachable target holds (CORRECTION 1).
4. **Docs to ship with it:** `scripts/components/locomotor.gd` docstring (lines 19-21 "DELIBERATELY NOT…" now false —
   nav-hop/anti-stuck/off-mesh now DO live here), `scripts/components/README.md` (the Locomotor "extraction target"
   note + new driven `drive_move_to`/`update_stuck` API), `scripts/npc/README.md` facade table, and the
   `npc_locomotion.gd:10-13` comment (CORRECTION 3).
