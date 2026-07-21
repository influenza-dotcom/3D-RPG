@tool
extends EditorScript

## AUTO-GENERATE NavLink bridges — in the editor, open a level, then File > Run this (Ctrl/Cmd+Shift+X). It scans the
## open scene's baked NavigationRegion3D for DISCONNECTED navmesh islands within a jump/drop budget and creates a
## `NavLink` for each real ledge gap, so you don't hand-place them. Reuses the same island detection as the navmesh
## audit (NavLinkPlanner mirrors NavMeshAudit).
##
## SAFE BY DEFAULT: APPLY = false only PREVIEWS (prints what it WOULD create; writes nothing). Set APPLY = true to
## actually insert the nodes, then **Ctrl+S to save**. Regeneration is idempotent — it replaces only the tagged
## `GeneratedNavLinks` container it owns, so any NavLink you hand-placed elsewhere is left untouched. Re-run after any
## RE-BAKE (the islands change).
##
## NOTES / LIMITATIONS:
## - Bake FIRST. A missing / stale bake yields wrong islands. Run scripts/tools/audit_navmesh.gd to sanity-check.
## - Every generated link is TRAVERSAL = LAUNCH (a ballistic hop). A link that lands over a real STAIRCASE should be
##   flipped to WALK by hand — the planner can't tell a stair from a bare ledge from navmesh geometry alone.
## - This is a convenience, not a guarantee: eyeball the result in the viewport (NavigationLink3D draws its own gizmo)
##   and delete/adjust any link that bridges somewhere it shouldn't.

## Preloaded (not the `NavLinkPlanner` global) so this runs even before the editor has registered the new class.
const Planner := preload("res://scripts/tools/nav_link_planner.gd")

const APPLY := true   ## false = PREVIEW ONLY (print, write nothing). Flip to true to insert nodes, then Ctrl+S.
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
	var specs := Planner.plan(mesh, BUDGET, probe_ctx.probe)
	_free_probe(probe_ctx)

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
	var step_walk_max: float = float(BUDGET.get("step_walk_max", 0.6))
	var probe := func(low: Vector3, high: Vector3) -> Dictionary:
		return _probe_ground(dss, low, high, step_walk_max)
	return {"probe": probe, "space": space, "bodies": bodies}

func _free_probe(ctx: Dictionary) -> void:
	for body in ctx.get("bodies", []):
		PhysicsServer3D.free_rid(body)
	if ctx.has("space"):
		PhysicsServer3D.free_rid(ctx.space)

## Sample the straight line low->high and raycast DOWN at each point: {grounded = every sample hit ground, max_step =
## largest vertical increment between consecutive hits}. Continuous ground with small increments = a staircase/ramp.
func _probe_ground(dss: PhysicsDirectSpaceState3D, low: Vector3, high: Vector3, _step_walk_max: float) -> Dictionary:
	if dss == null:
		return {"grounded": false, "max_step": 999.0}
	var samples := 12
	var top := maxf(low.y, high.y) + 2.0
	var bot := minf(low.y, high.y) - 2.0
	var last := low.y
	var max_step := 0.0
	for i in samples + 1:
		var p := low.lerp(high, float(i) / float(samples))
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, bot, p.z))
		var hit := dss.intersect_ray(q)
		if hit.is_empty():
			return {"grounded": false, "max_step": 999.0}  # a void under this sample -> not a walkable staircase
		var h: float = hit.position.y
		if i > 0:
			max_step = maxf(max_step, absf(h - last))
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
