class_name MovementHelpers
extends RefCounted

## Stateless movement math lifted off the Player coordinator — pure functions (like HostilityHelpers /
## TalkHelpers) that read no state of their own, so they're trivially unit-testable and shared without
## a node. Currently the Quake-style edge-friction probe plus the pure INTENT GATE in front of it
## (edge_intent_scale — deliberate gap-ward steering disarms the brake, so edge friction only ever
## fights momentum, never input); player.gd keeps a thin _edge_friction_t wrapper that forwards into
## here, and the EDGE_MIN_SPEED gate stays on the root (its _physics_process reads it before deciding
## whether to probe at all).
##
## NEVER instantiated — a namespace for the statics. extra_brake_t takes the body + raw directions
## rather than reading the Player, so it works for any CharacterBody3D and has no Player dependency.

## How far ahead of the body (m, along gap-ward velocity) to sample for a floor.
const EDGE_PROBE_AHEAD: float = 0.45
## Down-ray length (m) to LOCATE the floor under us — must exceed the body origin->feet gap.
const EDGE_FLOOR_PROBE: float = 2.0
## An ahead floor more than this far below our standing floor reads as a real drop-off (an edge).
const EDGE_DROP_TOLERANCE: float = 0.5
## Extra friction multiplier on the gap-ward velocity when near an edge (Quake ≈ 2).
const EDGE_FRICTION_MULT: float = 3.0
## Wish·gap dot at/above which the edge brake is skipped entirely — steering within a ~60° cone of the gap direction is deliberate.
const EDGE_INTENT_DOT_FULL: float = 0.5
## Dot at/below which the brake stays FULL (no input, sideways, or fighting the slide).
const EDGE_INTENT_DOT_START: float = 0.0
## Below this squared length the wish direction counts as NO input (deadzoned stick / menu-zeroed input).
const EDGE_WISH_EPSILON: float = 0.000001

## The INTENT GATE in front of the edge brake — PURE (no body, no physics space), so it's unit-testable
## off-tree (tests/test_movement_helpers.gd) unlike the raycasting shell around it. Returns 1.0 = full
## brake … 0.0 = no brake, blending LINEARLY across the wish·gap dot band EDGE_INTENT_DOT_START →
## EDGE_INTENT_DOT_FULL — a hard on/off threshold would flicker the brake as velocity/wish jitter around
## one dot value (the same 'wall' feel in a new costume); the blend is C0-continuous and pins to exact
## endpoints for the tests. A ZERO wish returns 1.0: input-less sliding (bhop landing, blast shove, menu
## open) keeps the FULL protective brake — the design half of the gate that must never lose. The wish is
## flattened before the dot so a vertical component can't dilute horizontal intent (vertical-only wish =
## no intent = full brake), and dot < 0 (fighting the slide) clamps to 1.0 — full brake PLUS the player's
## own counter-accel, both helping. Deliberately NO crouch/slow-walk coupling: the gate reads only wish
## vs gap direction, so a crouched stealth walk-off is intent like any other (and its halved speed means
## less momentum for the brake to matter anyway).
static func edge_intent_scale(gap_dir: Vector3, wish_dir: Vector3) -> float:
	if wish_dir.length_squared() < EDGE_WISH_EPSILON:
		return 1.0  # input-less sliding: the protective case keeps the FULL brake
	var flat := Vector3(wish_dir.x, 0.0, wish_dir.z)
	if flat.length_squared() < EDGE_WISH_EPSILON:
		return 1.0  # vertical-only wish is no horizontal intent
	var d := flat.normalized().dot(gap_dir)
	return clampf((EDGE_INTENT_DOT_FULL - d) / (EDGE_INTENT_DOT_FULL - EDGE_INTENT_DOT_START), 0.0, 1.0)

## Quake-style edge friction — makes it harder to slide off a ledge. While grounded the caller probes
## straight DOWN a touch ahead of the feet (along the gap-ward horizontal velocity `gap_dir`); if that
## probe finds no floor within a step height, the body is hanging over an edge in that direction, so we
## return the EXTRA friction lerp applied to the gap-ward velocity component this frame; 0.0 when not
## near an edge (caller then leaves movement unchanged). The brake only fights MOMENTUM, never intent:
## `wish_dir` (the body's own steering direction, optional) scales the result via edge_intent_scale, so
## steering gap-ward within the EDGE_INTENT_DOT_FULL cone skips the brake — and BOTH raycasts — entirely,
## and mid-band drift earns a proportionally weaker brake. That mirrors real `sv_edgefriction`, which
## only RAISES friction and lets acceleration win; an omitted wish (Vector3.ZERO) reads as no input and
## keeps the old unconditional-brake contract for any caller with no intent signal. Off the edge of a
## surface, the normal (centred) ground probe still hits floor, so non-edge movement is untouched.
## Casts its down-rays (floor-locate, then a step ahead of the feet) via `body`'s own physics space.
static func extra_brake_t(body: CharacterBody3D, gap_dir: Vector3, t_ground: float, wish_dir: Vector3 = Vector3.ZERO) -> float:
	var intent := edge_intent_scale(gap_dir, wish_dir)
	if intent <= 0.0:
		return 0.0  # deliberate gap-ward steering: no brake — and no raycast work at all (perf: both rays skipped every frame the player runs at an edge on purpose)
	var world := body.get_world_3d()
	if world == null or not world.space.is_valid():
		return 0.0
	var space_state := world.direct_space_state
	var origin := body.global_position
	# First LOCATE the floor under us: the body ORIGIN sits well above the feet, so a fixed short probe
	# from it always missed on flat ground — that read as "edge everywhere" and crawled us. Find the real
	# floor depth, then judge "is there ground a step ahead" RELATIVE to it.
	var ref_q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * EDGE_FLOOR_PROBE)
	ref_q.exclude = [body]
	var ref_hit := space_state.intersect_ray(ref_q)
	if ref_hit.is_empty():
		return 0.0  # couldn't find our own floor (rare) — don't brake, so we never falsely crawl
	var floor_dist: float = origin.y - (ref_hit.position as Vector3).y
	# A floor within (our floor depth + a step) a touch ahead = solid ground; nothing in range = a drop.
	var ahead := origin + gap_dir * EDGE_PROBE_AHEAD
	var ahead_q := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * (floor_dist + EDGE_DROP_TOLERANCE))
	ahead_q.exclude = [body]
	if space_state.intersect_ray(ahead_q).is_empty():
		# Scale the lerp weight by intent: mid-band dots get a proportionally weaker brake (full brake
		# only when the wish carries no gap-ward intent at all — see edge_intent_scale).
		return clampf(t_ground * EDGE_FRICTION_MULT, 0.0, 1.0) * intent
	return 0.0
