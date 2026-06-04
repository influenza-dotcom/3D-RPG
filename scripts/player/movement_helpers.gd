class_name MovementHelpers
extends RefCounted

## Stateless movement math lifted off the Player coordinator — pure functions (like HostilityHelpers /
## TalkHelpers) that read no state of their own, so they're trivially unit-testable and shared without
## a node. Currently just the Quake-style edge-friction probe; player.gd keeps a thin _edge_friction_t
## wrapper that forwards into here, and the EDGE_MIN_SPEED gate stays on the root (its _physics_process
## reads it before deciding whether to probe at all).
##
## NEVER instantiated — a namespace for the statics. extra_brake_t takes the body + raw direction
## rather than reading the Player, so it works for any CharacterBody3D and has no Player dependency.

## How far ahead of the body (m, along gap-ward velocity) to sample for a floor.
const EDGE_PROBE_AHEAD: float = 0.45
## Down-ray length (m) to LOCATE the floor under us — must exceed the body origin->feet gap.
const EDGE_FLOOR_PROBE: float = 2.0
## An ahead floor more than this far below our standing floor reads as a real drop-off (an edge).
const EDGE_DROP_TOLERANCE: float = 0.5
## Extra friction multiplier on the gap-ward velocity when near an edge (Quake ≈ 2).
const EDGE_FRICTION_MULT: float = 3.0

## Quake-style edge friction — makes it harder to slide off a ledge. While grounded the caller probes
## straight DOWN a touch ahead of the feet (along the gap-ward horizontal velocity `gap_dir`); if that
## probe finds no floor within a step height, the body is hanging over an edge in that direction, so we
## return the EXTRA friction lerp applied to the gap-ward velocity component this frame; 0.0 when not
## near an edge (caller then leaves movement unchanged). Mirrors Quake's `sv_edgefriction`. Off the edge
## of a surface, the normal (centred) ground probe still hits floor, so non-edge movement is untouched.
## Casts a single down-ray a step ahead of the feet via `body`'s own physics space.
static func extra_brake_t(body: CharacterBody3D, gap_dir: Vector3, t_ground: float) -> float:
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
		return clampf(t_ground * EDGE_FRICTION_MULT, 0.0, 1.0)
	return 0.0
