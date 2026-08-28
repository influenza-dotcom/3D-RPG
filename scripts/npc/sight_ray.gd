class_name SightRay
extends RefCounted

## The shared caster for every "can this NPC SEE / HEAR past that?" ray, and the one place that answers "does
## this collider stop a shot?". It is a thin wrapper around `intersect_ray` with ONE extra rule: a hit on
## SEE-THROUGH geometry does not stop the ray. The cast resumes just past that hit and keeps going, so what comes
## back is always the first genuinely OPAQUE thing in the way.
##
## WHY: a chain-link fence, a wire mesh, a shop window and a foliage card are all drawn with an alpha-scissored
## texture but built as ordinary solid brushes/boxes. Physics knows nothing about the texture, so before this an
## NPC standing behind a fence was as blind as one standing behind concrete — you could walk up to a guard in
## plain view and never be noticed, and neither of you could shoot through the wire.
##
## SIGHT **AND** FIRE pass through. The three consumers:
##   * PERCEPTION — `Perception.can_see` / `can_see_node` / `_wall_between`, `NpcSenses._corpse_occluded`,
##     `NpcHomeReturn._occluded`, all via `cast()` below;
##   * HITSCAN — `DamageTrace.run_pellet` skips see-through hits inside its own pierce walk (it needs the segment
##     bookkeeping, so it calls `is_see_through_hit` rather than `cast`);
##   * LIVE ROUNDS — `Projectile._ready` adds a physics collision exception with every body in the group, which
##     is why see-through geometry must live in its OWN body (see `SeeThroughBrushes`): a flying round collides
##     with a BODY, so there is no way to let it through one shape of a body and stop it on the next.
##
## Still BLOCKED by a fence, deliberately: walking into it, thrown/dropped props bouncing off it, the player's
## look-at interaction ray ("press F" cannot reach through the wire), the grapple hook, and the navmesh bake.
##
## HOW GEOMETRY IS MARKED: the collider is in `Groups.SEE_THROUGH`. One channel, whole bodies only — the
## `SeeThrough` drop-in tags a prop's bodies, and `SeeThroughBrushes` splits a func_godot map's fence brushes out
## into their own body so they can be tagged the same way.
##
## The caller still owns the query: build `PhysicsRayQueryParameters3D` exactly as before (mask, exclude, from/to)
## and swap `state.intersect_ray(query)` for `SightRay.cast(world, query)`. `query.from` is walked forward during
## the passes and RESTORED before returning, so a caller that reuses or re-reads its query sees no difference.


## How many see-through surfaces one ray may punch through before it gives up and reports "blocked". A fence is
## two faces (front and back) and you can easily line up two fences plus a window, so the budget is generous;
## it exists only so a degenerate case (a zero-thickness shape the skin step cannot clear) can never spin.
const MAX_PASS_THROUGH := 8

## How far past a see-through hit the next pass starts, in metres. Must be big enough to clear the hit surface
## (otherwise the same face is hit forever) and small enough that nothing real hides inside it.
const SKIN := 0.01


## Cast `query` and return the first OPAQUE hit — the same Dictionary `intersect_ray` returns, `{}` for a clear
## line. See-through hits are stepped past rather than reported. Returns `{}` (never throws) for a null/dead
## world, matching the world-guard every caller already had.
static func cast(world: World3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	if world == null or not world.space.is_valid() or query == null:
		return {}
	var state := world.direct_space_state
	if state == null:
		return {}
	var origin := query.from
	var offset := query.to - origin
	var length := offset.length()
	if length < 0.0001:
		return state.intersect_ray(query)  # degenerate ray: nothing to step past, answer as-is
	var dir := offset / length
	var hit := {}
	for _pass in MAX_PASS_THROUGH + 1:
		var next: Dictionary = state.intersect_ray(query)
		if next.is_empty():
			hit = {}  # nothing left in the way: a genuinely clear line
			break
		hit = next
		if not is_see_through_hit(hit):
			break  # the first opaque thing — this is the answer
		# Resume just past the see-through face. Once the resume point is at/behind the endpoint the remaining
		# ray is empty, and the next intersect_ray reports the clear line we want anyway. If the budget runs
		# out first we FALL OUT of the loop still holding this see-through hit, so the answer is "blocked" —
		# fail closed, because the untested remainder of the ray could have a wall in it.
		query.from = (hit["position"] as Vector3) + dir * SKIN
	query.from = origin  # leave the caller's query exactly as they built it
	return hit


## Is this ray hit on geometry sight and gunfire pass through? Pure (Dictionary in, bool out) so the marking
## contract is unit-testable without a physics space, and so `DamageTrace`'s pierce walk can reuse the rule
## without reusing the whole cast. One group lookup — the answer for every ordinary collider in the game.
static func is_see_through_hit(hit: Dictionary) -> bool:
	var node := hit.get("collider") as Node
	if node == null or not is_instance_valid(node):
		return false
	return node.is_in_group(Groups.SEE_THROUGH)
