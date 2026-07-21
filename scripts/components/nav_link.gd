@tool
class_name NavLink
extends NavigationLink3D

## Drop-in LEDGE / DROP TRAVERSAL for NPCs. A baked NavigationRegion3D bakes any surface more than
## `agent_max_climb` (~0.4 m) above/below its neighbour as a SEPARATE, disconnected navmesh island, so A* can never
## route an NPC across a ledge — up OR down. This node is the canonical Godot bridge: `NavigationServer3D`
## auto-routes every agent's path THROUGH an enabled link with no per-agent wiring, so dropping one across a ledge
## makes NPCs path over it. The upward LAUNCH that carries the body onto a higher island comes from the Locomotor's
## link-ascent driver (locomotor.gd `_on_link_reached`), which is decoupled from the combat hop so IDLE NPCs climb.
##
## Unlike NavBlocker(CARVE) — a BAKE input that needs a re-bake — a link is a RUNTIME routing edge: drop it, save,
## done. No re-bake.
##
## SETUP: add it as a child of the level (near the ledge). Drag the two endpoint handles (NavigationLink3D's built-in
## gizmo) onto the LOWER and UPPER walkable surfaces — a metre or so in from each rim so `auto_project` can snap them
## onto the baked mesh. Pick `direction`:
##   - TWO_WAY: NPCs may climb up AND drop down (a low ledge / crate / short step-up).
##   - ONE_WAY_DOWN: NPCs may only DROP (a cliff / balcony they can leave but not scale). The node auto-orients so the
##     higher endpoint is the start (the only legal travel direction is start -> end = downward).
##
## Extends NavigationLink3D directly (the NavBlocker-extends-NavigationObstacle3D idiom): inherited `start_position`
## /`end_position`/`enabled`/`navigation_layers` stay authorable, and we only add the drop-in conveniences.

enum Direction {
	TWO_WAY,       ## climb up + drop down (bidirectional). For low ledges / crates / short step-ups.
	ONE_WAY_DOWN,  ## drop only — NPCs leave but can't scale it (a cliff / balcony). Auto-orients start = higher.
}

## How an NPC physically CROSSES this link's climb (independent of Direction, which is only about which way A* may route).
enum Traversal {
	LAUNCH,  ## the Locomotor injects a ballistic hop onto the higher island. For a bare LEDGE / crate / single tall step
	##          with no walkable geometry between the two surfaces — the body must jump the gap.
	WALK,    ## no launch: the NPC steers along the link and its step-up (Locomotor.enable_step_up) climbs the real STAIR
	##          treads underneath. Use for a STAIRCASE so it reads as walking up, not a leap. (Only affects UP crossings.)
}

## Which way NPCs may traverse. TWO_WAY = climb + drop; ONE_WAY_DOWN = drop only (auto-orients so start is the higher end).
@export var direction: Direction = Direction.TWO_WAY:
	set(value):
		direction = value
		_apply()
## How NPCs cross the climb: LAUNCH = ballistic hop (a bare ledge/crate); WALK = walk the stairs underneath via step-up.
## Set WALK for a link laid over a STAIRCASE so NPCs walk up instead of leaping; the Locomotor reads this via walk_traversal().
@export var traversal: Traversal = Traversal.LAUNCH
## A* penalty for USING this link (written to the inherited `enter_cost`). Kept > 0 so pathing prefers a real ramp /
## stair when one exists and only jumps the link when it must — raise it if NPCs jump a ledge that has a nearby ramp.
@export var traverse_cost: float = 2.0:
	set(value):
		traverse_cost = value
		_apply()
## Snap each endpoint onto the nearest baked navmesh point at load, so eyeballed placement still connects (an endpoint
## that lands even slightly off the mesh silently won't link). Off = use the authored positions verbatim.
@export var auto_project: bool = true
## Max metres a snap may move an endpoint (mirrors `_snap_to_navmesh` max_drift): only near-misses snap, so a stray
## endpoint is never yanked onto the wrong island. Keep it under the map's link_connection_radius.
@export var project_radius: float = 1.0
## Config-warning threshold only: a TWO_WAY span taller than this warns "NPCs can't jump that high — use ONE_WAY_DOWN".
@export var climb_warn_budget: float = 3.0

func _ready() -> void:
	_apply()  # authoritative pass once positions exist (after .tscn load)
	# The nav map isn't synced at _ready (query-before-sync errors), so defer endpoint projection to a ready frame.
	set_physics_process(auto_project and not Engine.is_editor_hint())

## Configure the underlying NavigationLink3D for the chosen direction + cost. Pure property writes, so it's safe from
## the setters live in the editor AND off-tree in a unit test (no tree / map access here). Idempotent (re-running never
## re-swaps an already-oriented one-way link).
func _apply() -> void:
	enabled = true
	enter_cost = maxf(0.0, traverse_cost)
	if direction == Direction.ONE_WAY_DOWN:
		bidirectional = false
		# The one legal travel direction is start -> end, which must be DOWNWARD, so the start is the HIGHER endpoint.
		if end_position.y > start_position.y:
			var higher := end_position
			end_position = start_position
			start_position = higher
	else:
		bidirectional = true

## True when this link should be WALKED (step-up over stairs), not launched. The Locomotor's _on_link_reached calls this
## (duck-typed, via has_method) to decide whether to suppress the ballistic ascent launch — so a staircase link walks.
func walk_traversal() -> bool:
	return traversal == Traversal.WALK

## Once the nav map has synced, snap both endpoints onto the nearest baked mesh point (near-misses only), then stop —
## a one-shot. Gated on is_nav_map_ready because map_get_closest_point ERRORS before the first sync (nav-map-query-before-sync).
func _physics_process(_delta: float) -> void:
	var map := get_navigation_map()
	if not NavigationUtils.is_nav_map_ready(map):
		return
	start_position = _project(map, start_position)
	end_position = _project(map, end_position)
	# Dev backstop: if an endpoint STILL sits off the mesh after projection (drifted farther than project_radius — e.g.
	# a re-bake shifted the floor out from under it), this link binds to NOTHING and silently won't route NPCs. The
	# editor reachability audit (NavMeshAudit.reachability) flags it at edit time; this surfaces the SAME failure at
	# RUNTIME so a broken link isn't invisible in play. Debug builds only; fires at most once per endpoint (one-shot).
	if OS.is_debug_build():
		_warn_off_mesh(map, start_position, &"start")
		_warn_off_mesh(map, end_position, &"end")
	set_physics_process(false)

## Warn if `local_pt` (our local space) is still farther than project_radius from the nearest baked navmesh point — i.e.
## auto_project couldn't snap it on, so the link doesn't actually connect there. Pure query + push_warning, no state change.
func _warn_off_mesh(map: RID, local_pt: Vector3, which: StringName) -> void:
	var world := global_transform * local_pt
	var drift := world.distance_to(NavigationServer3D.map_get_closest_point(map, world))
	if drift > project_radius:
		push_warning("NavLink '%s' %s endpoint is %.2f m off the navmesh (> project_radius %.2f) — it bridges nothing; NPCs won't route across it. Nudge the handle onto walkable floor or re-bake." % [name, String(which), drift, project_radius])

## Snap one endpoint (in OUR local space) onto the nearest navmesh point, but only if that's within project_radius (so a
## stray endpoint degrades to its authored spot rather than teleporting onto a wrong island). Nav-map queries are
## world-space, so round-trip through our global_transform.
func _project(map: RID, local_pt: Vector3) -> Vector3:
	var world := global_transform * local_pt
	var nearest := NavigationServer3D.map_get_closest_point(map, world)
	return (global_transform.affine_inverse() * nearest) if world.distance_to(nearest) <= project_radius else local_pt

## EDITOR: catch the authoring mistakes that make a link silently fail — coincident handles, a "climb" the bake already
## bridges (redundant), or a TWO_WAY span too tall for an NPC to jump. Delegates to a pure static so it's unit-testable.
func _get_configuration_warnings() -> PackedStringArray:
	# Unqualified static call (not `NavLink.warnings_for`): a class must not reference its own class_name as a global
	# identifier, which fails until the editor has registered the new class in the global script class cache.
	return warnings_for(start_position, end_position, direction, climb_warn_budget, traversal)

## Pure authoring-warning logic (no node/tree access) so a test can assert the truth table off-tree. `traversal` defaults
## to LAUNCH so existing 4-arg callers (and the truth-table tests) are unaffected.
static func warnings_for(s: Vector3, e: Vector3, dir: Direction, budget: float, traversal_mode := Traversal.LAUNCH) -> PackedStringArray:
	var w := PackedStringArray()
	var span := s.distance_to(e)
	var climb := absf(e.y - s.y)
	var run := Vector2(e.x - s.x, e.z - s.z).length()
	if span < 0.1:
		w.append("NavLink endpoints coincide — drag the two handles onto the lower and upper walkable surfaces.")
	elif climb < 0.4:
		w.append("Vertical span < ~0.4 m — agent_max_climb already connects these surfaces; this link is probably redundant.")
	if traversal_mode == Traversal.WALK:
		# A WALK link is WALKED (step-up climbs the real treads), not jumped — so the jump-height ceiling doesn't apply.
		# Instead it needs a horizontal RUN to walk along: a near-vertical WALK link has no shallow stair under it for
		# step-up to climb, and the body would just press into a wall.
		if climb > 0.4 and run < climb:
			w.append("WALK link is steeper than 45° (climb %.1f m over %.1f m run) — there's no shallow stair under it for step-up to climb. Lay it along the staircase footprint, or use LAUNCH." % [climb, run])
	elif dir == Direction.TWO_WAY and climb > budget:
		w.append("TWO_WAY span %.1f m is taller than NPCs can jump (~%.1f m) — they'll path here and stall. Use ONE_WAY_DOWN, a WALK link over stairs, or a ramp." % [climb, budget])
	return w
