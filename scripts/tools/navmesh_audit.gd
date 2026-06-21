class_name NavMeshAudit
extends RefCounted

## Analyzes a baked NavigationMesh and reports the two bake problems that wreck NPC pathing:
##   1. DISCONNECTED ISLANDS — an NPC standing on one island cannot path to another (no shared edge between them).
##   2. ELEVATED POLYGONS — walkable polys baked on TOP of cars/props (the classic "NPC stuck on a car roof"):
##      a poly whose centroid sits well above the main floor.
## Pure + static so it's unit-tested off-tree (no transforms touched — see [[gut-engine-errors-fail...]]); the
## editor entry point is scripts/tools/audit_navmesh.gd (File -> Run).

const EDGE_SNAP := 0.05       ## verts within 5 cm are treated as the same point when matching shared edges
const ROOF_HEIGHT := 0.6      ## a poly this far above the main floor = suspected roof/prop top
const TINY_ISLAND_MAX := 8    ## islands with <= this many polys are called out individually as fragments

## Returns: {
##   ok: bool, poly_count: int, vertex_count: int, total_area: float, floor_y: float,
##   islands: [ {polys:int, area:float, y_min:float, y_max:float, centroid:Vector3} ... ] (largest area first),
##   elevated: [ {y:float, height:float, pos:Vector3} ... ] (tallest first),
##   warnings: [String...] }
static func analyze(navmesh: NavigationMesh) -> Dictionary:
	var report := {
		"ok": true, "poly_count": 0, "vertex_count": 0, "total_area": 0.0,
		"floor_y": 0.0, "islands": [], "elevated": [], "warnings": [],
	}
	if navmesh == null:
		report.ok = false
		report.warnings.append("No NavigationMesh assigned to the region.")
		return report
	var verts := navmesh.get_vertices()
	var n := navmesh.get_polygon_count()
	report.vertex_count = verts.size()
	report.poly_count = n
	if n == 0:
		report.ok = false
		report.warnings.append("navmesh has 0 polygons — not baked. Select the NavigationRegion3D and click Bake NavigationMesh.")
		return report

	# Per-poly centroid + area, plus an edge -> polys map (edges matched by snapped endpoint positions, so recast's
	# duplicated coincident vertices still register as shared).
	var centroids: Array[Vector3] = []
	var areas: Array[float] = []
	var edge_map := {}
	for i in n:
		var poly := navmesh.get_polygon(i)
		var cnt := poly.size()
		var c := Vector3.ZERO
		for k in cnt:
			c += verts[poly[k]]
		if cnt > 0:
			c /= float(cnt)
		var area := 0.0
		for k in range(1, cnt - 1):
			var v0 := verts[poly[0]]
			var v1 := verts[poly[k]]
			var v2 := verts[poly[k + 1]]
			area += (v1 - v0).cross(v2 - v0).length() * 0.5
		centroids.append(c)
		areas.append(area)
		report.total_area += area
		for k in cnt:
			var key := _edge_key(verts[poly[k]], verts[poly[(k + 1) % cnt]])
			if not edge_map.has(key):
				edge_map[key] = []
			edge_map[key].append(i)

	# Union-find over shared edges -> connected components (islands).
	var parent := []
	parent.resize(n)
	for i in n:
		parent[i] = i
	for key in edge_map:
		var ps: Array = edge_map[key]
		for j in range(1, ps.size()):
			_union(parent, ps[0], ps[j])
	var groups := {}
	for i in n:
		var r := _find(parent, i)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(i)

	var islands := []
	for r in groups:
		var members: Array = groups[r]
		var y_min := INF
		var y_max := -INF
		var area_sum := 0.0
		var cen := Vector3.ZERO
		for i in members:
			var cy: float = centroids[i].y
			y_min = minf(y_min, cy)
			y_max = maxf(y_max, cy)
			area_sum += areas[i]
			cen += centroids[i]
		cen /= float(members.size())
		islands.append({"polys": members.size(), "area": area_sum, "y_min": y_min, "y_max": y_max, "centroid": cen})
	islands.sort_custom(func(a, b): return a.area > b.area)
	report.islands = islands

	# The largest island is the real floor; measure everything else against its height.
	var floor_y: float = islands[0].centroid.y
	report.floor_y = floor_y
	var elevated := []
	for i in n:
		var h: float = centroids[i].y - floor_y
		if h > ROOF_HEIGHT:
			elevated.append({"y": centroids[i].y, "height": h, "pos": centroids[i]})
	elevated.sort_custom(func(a, b): return a.height > b.height)
	report.elevated = elevated

	if islands.size() > 1:
		report.warnings.append("%d disconnected navmesh islands — an NPC on one CANNOT path to another. Bridge the gaps or remove the stray walkable surfaces, then re-bake." % islands.size())
		for idx in range(1, islands.size()):
			var isl: Dictionary = islands[idx]
			if isl.polys <= TINY_ISLAND_MAX:
				report.warnings.append("  fragment of %d poly(s) at y~%.1f, center (%.1f, %.1f) — likely a prop/car roof; an NPC there gets stranded." % [isl.polys, isl.centroid.y, isl.centroid.x, isl.centroid.z])
	if elevated.size() > 0:
		report.warnings.append("%d polygon(s) baked >%.1fm above the floor (walkable prop/car roofs). Lower the region's agent_max_climb or drop a NavBlocker(CARVE) on those props, then re-bake." % [elevated.size(), ROOF_HEIGHT])
	report.ok = report.warnings.is_empty()
	return report

static func _pkey(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x / EDGE_SNAP), roundi(v.y / EDGE_SNAP), roundi(v.z / EDGE_SNAP)]

static func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := _pkey(a)
	var kb := _pkey(b)
	return (ka + "|" + kb) if ka <= kb else (kb + "|" + ka)

static func _find(parent: Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]  # path halving
		x = parent[x]
	return x

static func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb
