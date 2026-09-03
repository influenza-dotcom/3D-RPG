@tool
extends EditorScript

## AUTO-GENERATE NavLink bridges — in the editor, open a level, then File > Run this (Ctrl/Cmd+Shift+X). It scans the
## open scene's baked NavigationRegion3D for DISCONNECTED navmesh islands within a jump/drop budget and creates a
## `NavLink` for each real ledge gap, so you don't hand-place them. Reuses the same island detection as the navmesh
## audit (NavLinkPlanner mirrors NavMeshAudit).
##
## DESTRUCTIVE BY DEFAULT: this ships **APPLY = true**, so File > Run WRITES the nodes immediately — there is no
## preview step to walk you up to it. For a print-only pass (prints what it WOULD create, writes nothing) you must
## edit the const to `false` yourself and re-run. After a real run, **Ctrl+S to save**. Regeneration is idempotent by
## DELETION: it FREES the whole tagged `GeneratedNavLinks` container and rebuilds it, so a NavLink you hand-placed
## **inside** that container is DESTROYED — the live trenchboom_test_level has ten such hand-added
## `_NavigationLink3D_492xx` links parked in there. Only links parented ELSEWHERE survive; keep hand-authored links
## out of the container. Re-run after any RE-BAKE (the islands change).
##
## NOTES / LIMITATIONS:
## - THE EDITOR FREEZES WHILE IT RUNS, and shows nothing until it finishes. File > Run blocks the main thread, so the
##   Output panel cannot repaint mid-scan -- on the live map (trenchboom_test_level: 10 222 navmesh polys, 10 082
##   island rims, 359 links) planning takes ~7 s, during which Windows may even paint the editor "Not Responding".
##   That is the tool working, not the tool hanging: wait for the "planned in N s" line. Measured 2026-08-26 headless,
##   median of 5 runs: 7.2 s (21.7 s before that day's optimization pass, ~58 s before the 2026-08-24 one). If it ever
##   takes minutes again, the scan has gone super-linear -- see the spatial-bucket, conservative-pre-reject and
##   deferred-stair-probe notes in NavLinkPlanner.plan, plus the reused ray query / early-out / probe memo below.
##   Those are what keep it linear in the rim count; none of them may change which links are emitted.
## - Bake FIRST. A missing / stale bake yields wrong islands. Run scripts/tools/audit_navmesh.gd to sanity-check.
## - Every generated link is TRAVERSAL = LAUNCH (a ballistic hop). A link that lands over a real STAIRCASE should be
##   flipped to WALK by hand — the planner can't tell a stair from a bare ledge from navmesh geometry alone.
## - This is a convenience, not a guarantee: eyeball the result in the viewport (NavigationLink3D draws its own gizmo)
##   and delete/adjust any link that bridges somewhere it shouldn't.

## Preloaded (not the `NavLinkPlanner` global) so this runs even before the editor has registered the new class.
const Planner := preload("res://scripts/tools/nav_link_planner.gd")

const APPLY := true    ## SHIPS TRUE — every run WRITES (and frees the container first). Flip to false for a print-only pass.
const CONTAINER := "GeneratedNavLinks"   ## all generated links live under this one tagged child of the region

## Budget override (empty {} = NavLinkPlanner.DEFAULT_BUDGET). Tune here if links are too sparse/dense or reach too far.
## Keys: max_gap_h, max_climb, max_drop, min_sep, link_spacing.
const BUDGET := {}

func _run() -> void:
	var scene := get_scene()
	if scene == null:
		print("[GenNavLinks] No scene open. Open a level scene, then File > Run this.")
		return
	var regions: Array[NavigationRegion3D] = []
	_collect(scene, regions)
	if regions.is_empty():
		print("[GenNavLinks] No NavigationRegion3D in the open scene.")
		return
	print_rich("[b]-- Generate NavLinks (%s) --[/b]" % ("APPLY — writing nodes" if APPLY else "PREVIEW — nothing written"))
	var total := 0
	for region in regions:
		total += _process_region(scene, region)
	if total == 0:
		print("[GenNavLinks] No disconnected-island gaps within budget — nothing to bridge (a clean 1-island bake is ideal).")
	elif APPLY:
		print_rich("[color=lime]Created %d NavLink(s). Ctrl+S to save.[/color] Eyeball them in the viewport; flip any staircase link to WALK." % total)
	else:
		print_rich("[color=yellow]Would create %d NavLink(s).[/color] Set APPLY = true and re-run to insert them." % total)

func _process_region(scene: Node, region: NavigationRegion3D) -> int:
	var mesh := region.navigation_mesh
	if mesh == null or mesh.get_polygon_count() == 0:
		print("   %s: no baked NavigationMesh — bake it first." % region.name)
		return 0
	# STAIR probe: a self-built physics space over the scene's colliders so plan() can tell a walkable staircase/ramp
	# from a void (raycast down between the two island rims). Self-built (not the editor world) so it works in File->Run.
	var probe_ctx := _build_probe(scene)
	var t0 := Time.get_ticks_msec()
	var specs := Planner.plan(mesh, BUDGET, probe_ctx.probe)
	var elapsed := Time.get_ticks_msec() - t0
	_free_probe(probe_ctx)
	# Report the SIZE of the job next to the time. File > Run blocks the editor's main thread, so nothing below can
	# reach the Output panel until plan() returns -- on a big bake the tool looks like it did nothing at all while it
	# works. Printing polys + seconds is how you tell "there was nothing to bridge" apart from "it is still thinking".
	print("   %s: planned in %.1f s over %d navmesh polys." % [region.name, elapsed / 1000.0, mesh.get_polygon_count()])

	var down := 0
	var walk := 0
	for s in specs:
		if s.get("walk", false):
			walk += 1
		elif s.one_way_down:
			down += 1
	print("   %s: %d gap(s) to bridge (%d walk/stairs, %d two-way jump, %d one-way-down):" % [
		region.name, specs.size(), walk, specs.size() - walk - down, down])
	for s in specs:
		print("      %-5s %s  climb %.1f m, run %.1f m  (%s)" % [
			("WALK" if s.get("walk", false) else ("DROP" if s.one_way_down else "JUMP")), s.key, s.climb, s.gap,
			"%s -> %s" % [_fmt(s.a), _fmt(s.b)]])
	if not APPLY or specs.is_empty():
		return specs.size()

	# Idempotent: replace ONLY our tagged container; hand-placed NavLinks elsewhere are never touched.
	var old := region.get_node_or_null(CONTAINER)
	if old != null:
		region.remove_child(old)
		old.free()
	var container := Node3D.new()
	container.name = CONTAINER
	region.add_child(container)
	container.owner = scene   # so it serializes into the .tscn on save
	var LinkScript: GDScript = load("res://scripts/components/nav_link.gd")
	for s in specs:
		var link: Node = LinkScript.new()
		# Positions are region-LOCAL; the container sits at the region origin (identity), so a link at the container
		# origin reads start/end in region-local space — exactly what the planner returns.
		link.start_position = s.a               # set BEFORE direction so _apply orients a one-way link correctly
		link.end_position = s.b
		link.direction = 1 if s.one_way_down else 0   # ONE_WAY_DOWN : TWO_WAY (enum ints — no NavLink type dependency here)
		link.traversal = 1 if s.get("walk", false) else 0  # WALK for a detected staircase/ramp; LAUNCH otherwise
		link.name = "Link_%s" % s.key
		container.add_child(link)
		link.owner = scene
		print("      + %s" % link.get_path())
	return specs.size()

## Build a physics `probe` Callable(low, high) -> {grounded, max_step} over the scene's static colliders, in a FRESH
## PhysicsServer3D space we own (works in File->Run without relying on the editor's edit-mode physics world). Returns
## {probe, space, bodies}; pass to _free_probe when done. Shape RIDs belong to the resources — we reference, never free them.
func _build_probe(scene: Node) -> Dictionary:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var bodies: Array = []
	var cols: Array = []
	_collect_shapes(scene, cols)
	for cs in cols:
		var shp: Shape3D = cs.shape
		if shp == null:
			continue
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_add_shape(body, shp.get_rid(), cs.global_transform)
		bodies.append(body)
	var dss := PhysicsServer3D.space_get_direct_state(space)
	# Fall back to the PLANNER's default, never a hardcoded copy of it. This value now drives _cast_ground's early
	# bail, and the bail is only exact while the probe's threshold is >= the one _resolve_stairs compares against.
	# Hardcoding 0.6 here meant raising DEFAULT_BUDGET.step_walk_max (the obvious edit if Locomotor.step_up_height
	# ever moves) would silently bail at the stale 0.6 and hand the planner a partial max it would then ACCEPT --
	# WALK links over risers taller than the budget allows.
	var step_walk_max: float = float(BUDGET.get("step_walk_max", Planner.DEFAULT_BUDGET.step_walk_max))
	# ONE ray-query object, reused for every ray of every probe (the live map fires ~0.25 M of them). The old code
	# built a fresh `PhysicsRayQueryParameters3D.create(...)` per ray -- a RefCounted allocation each time. `.new()`
	# carries the IDENTICAL defaults `create()` would set (collision_mask 0xFFFFFFFF, collide_with_bodies on,
	# collide_with_areas off, hit_back_faces on, hit_from_inside off, empty exclude -- verified at runtime on 4.7),
	# and only `from`/`to` ever change between rays, so every query asks byte-for-byte the same question as before.
	# The lambda captures the object REFERENCE, so both it and the memo below live as long as the probe Callable.
	var query := PhysicsRayQueryParameters3D.new()
	# MEMO of probe verdicts, keyed low -> high (see _probe_ground). The planner asks the SAME rim-point pair more
	# than once -- 33 420 of the live map's 65 201 probes (51 %) are exact repeats, because different rim-edge pairs
	# between the same two islands collapse onto the same closest-point pair (a shared vertex, a shared riser).
	var memo := {}
	var probe := func(low: Vector3, high: Vector3) -> Dictionary:
		return _probe_ground(dss, query, memo, low, high, step_walk_max)
	return {"probe": probe, "space": space, "bodies": bodies}

func _free_probe(ctx: Dictionary) -> void:
	for body in ctx.get("bodies", []):
		PhysicsServer3D.free_rid(body)
	if ctx.has("space"):
		PhysicsServer3D.free_rid(ctx.space)

## MEMOIZED front door to _cast_ground: {grounded, max_step} for the straight line low->high (see below).
##
## The probe is a PURE function of (low, high): the space is built once, holds only static bodies, and nothing steps
## physics while plan() runs -- so the same pair always yields the same verdict and caching it is exact, not an
## approximation. It pays because the planner repeats itself: `NavLinkPlanner._resolve_stairs` walks the rim-pair
## records of an island pair, and many DIFFERENT rim-edge pairs collapse onto the SAME closest-point pair, so the
## same question arrives again and again. On the live map 33 420 of 65 201 probes are exact repeats.
##
## The cache stores scalars in an Array -- NOT a Vector2, whose components are float32. `max_step` is a float64, and
## narrowing it rounds UP at the threshold: the double 0.6 stores as 0.60000002384185791, so a flight whose largest
## riser is exactly step_walk_max answered `walk` on the first (uncached) call and `not walk` on every memoized call
## after -- a verdict that depended on cache-hit order. An Array keeps both fields at full width. Never the returned
## Dictionary, so every caller still
## gets a fresh Dictionary it may do what it likes with -- no shared mutable state leaks out of here. It is created
## per _build_probe and dies with the probe Callable; it would be WRONG to keep across bakes or to move a body.
func _probe_ground(dss: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D, memo: Dictionary,
		low: Vector3, high: Vector3, step_walk_max: float) -> Dictionary:
	if dss == null:
		return {"grounded": false, "max_step": 999.0}
	var seen: Dictionary = memo.get(low, {})
	if seen.has(high):
		var v: Array = seen[high]
		return {"grounded": bool(v[0]), "max_step": float(v[1])}
	var res := _cast_ground(dss, q, low, high, step_walk_max)
	seen[high] = [bool(res.grounded), float(res.max_step)]
	memo[low] = seen
	return res

## Sample the straight line low->high and raycast DOWN at each point: {grounded = every sample hit ground, max_step =
## largest vertical increment between consecutive hits}. Continuous ground with small increments = a staircase/ramp.
##
## BAILS EARLY once `max_step` passes `step_walk_max`, and that is EXACT, not an approximation. `max_step` is a RUNNING
## MAX, so it can never come back down; and the probe's only consumer (NavLinkPlanner._resolve_stairs, both call sites)
## asks exactly `grounded and max_step <= step_walk_max`. Once that conjunction is pinned false the remaining rays
## cannot change the verdict, whatever they would have found -- including a later void that would have flipped
## `grounded` to false, since the answer is already false. It pays because most probed gaps are NOT stairs: on the live
## map 39 481 of 65 201 probes are grounded-but-too-tall, and the bail takes the run from 808 k rays to 558 k.
## CAVEAT for a future caller: after a bail `max_step` is a LOWER BOUND, not the flight's true largest riser. Anyone
## who wants the real maximum (say, to rank flights by steepness) must pass step_walk_max = INF.
func _cast_ground(dss: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D,
		low: Vector3, high: Vector3, step_walk_max: float) -> Dictionary:
	var samples := 12
	var top := maxf(low.y, high.y) + 2.0
	var bot := minf(low.y, high.y) - 2.0
	var last := low.y
	var max_step := 0.0
	for i in samples + 1:
		var p := low.lerp(high, float(i) / float(samples))
		q.from = Vector3(p.x, top, p.z)
		q.to = Vector3(p.x, bot, p.z)
		var hit := dss.intersect_ray(q)
		if hit.is_empty():
			return {"grounded": false, "max_step": 999.0}  # a void under this sample -> not a walkable staircase
		var h: float = hit.position.y
		if i > 0:
			max_step = maxf(max_step, absf(h - last))
			if max_step > step_walk_max:
				return {"grounded": true, "max_step": max_step}  # already too tall to be stairs -> stop raycasting
		last = h
	return {"grounded": true, "max_step": max_step}

func _collect_shapes(node: Node, out: Array) -> void:
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		out.append(node)
	for c in node.get_children():
		_collect_shapes(c, out)

func _collect(node: Node, out: Array[NavigationRegion3D]) -> void:
	if node is NavigationRegion3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)

func _fmt(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
