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
const MAJOR_ISLAND_FRAC := 0.2  ## an island with >= this share of the largest island's area counts as "major"

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
	report["settings"] = {
		"agent_max_climb": navmesh.agent_max_climb,
		"agent_max_slope": navmesh.agent_max_slope,
		"agent_radius": navmesh.agent_radius,
		"agent_height": navmesh.agent_height,
		"cell_size": navmesh.cell_size,
		"cell_height": navmesh.cell_height,
		"parsed_geometry_type": navmesh.geometry_parsed_geometry_type,
	}
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

	# Floor = the LOWEST *major* island, not merely the largest. On a multi-storey scene (or one whose ground baked
	# into fragments) the single biggest contiguous surface is often an upper floor/roof — taking it as the floor
	# would make the real ground read as "below floor" and miss every elevated platform. So among islands with a
	# meaningful share of the largest island's area, use the minimum centroid height.
	var max_area: float = islands[0].area
	var floor_y: float = islands[0].centroid.y
	for isl in islands:
		if isl.area >= MAJOR_ISLAND_FRAC * max_area:
			floor_y = minf(floor_y, isl.centroid.y)
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
		report.warnings.append("%d polygon(s) baked >%.1fm above the floor (walkable prop/car roofs)." % [elevated.size(), ROOF_HEIGHT])
		report.warnings.append("  TUNE: agent_max_climb=%.2f (lower toward ~0.4 to stop the bake stepping onto curbs/props), agent_max_slope=%.0f deg (lower if car hoods/ramps bake walkable), or drop a NavBlocker(CARVE) on those props — then re-bake." % [navmesh.agent_max_climb, navmesh.agent_max_slope])
	# PARSE MODE: this project authors walkability as COLLISION (floor StaticBody colliders, CSG use_collision, NavBlocker
	# CARVE), so the bake must parse STATIC COLLIDERS only. The engine default is BOTH (2), which also parses VISUAL
	# MeshInstance3D geometry — so decorative meshes with NO collider (or whose collider differs from the mesh) get baked
	# into the navmesh, and NPCs then path onto/around "meshes, not just collision" and grind. Flag anything but Colliders.
	if navmesh.geometry_parsed_geometry_type != NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS:
		var mode_name := "Both (meshes + colliders)" if navmesh.geometry_parsed_geometry_type == NavigationMesh.PARSED_GEOMETRY_BOTH else "Mesh Instances"
		report.warnings.append("navmesh bakes from '%s', not Static Colliders — walkable polys get baked onto VISUAL meshes that may have no collision, so NPCs stick on mesh-only geometry. Set NavigationMesh > Geometry > Parsed Geometry Type to 'Static Colliders' and re-bake." % mode_name)
	report.ok = report.warnings.is_empty()
	return report

## --- NavLink-aware REACHABILITY ----------------------------------------------------------------------------------
## analyze() reports the RAW geometric islands (it knows nothing about NavLinks), so on a level whose islands are
## DELIBERATELY fragmented and bridged by NavigationLink3D (e.g. this project's brush stairs), it always warns
## "N disconnected islands" even though A* routes fine across the links — a permanent false-positive that means the
## nav-health gate can never actually CERTIFY a link-bridged level. reachability() closes that gap: given the same
## navmesh PLUS the level's links (endpoints already in navmesh-LOCAL space — the caller applies the region/link
## transforms), it reports whether the links truly knit the islands into one reachable network. It catches the two
## ways a link silently fails — an endpoint that lands OFF the mesh (binds to nothing; the very failure NavLink's
## `auto_project` guards against but nothing verifies) and an island NO link reaches — plus one-way-only strandings.
## Pure + static (plain Vector3 data, no tree / no transforms) so it unit-tests off-tree exactly like analyze().
##
## links: Array of { a: Vector3, b: Vector3, bidirectional: bool } — endpoints in navmesh-LOCAL coords, ENABLED links
##   only (the caller drops disabled ones). connect_radius: how near an endpoint must sit to a navmesh polygon to bind
##   to it — mirror the links' `project_radius` / the map's link_connection_radius (default 1.0 m).
## Returns { raw_islands:int, effective_islands:int, ok:bool, dangling:Array, redundant:Array, unreachable:Array,
##   one_way_only:Array, warnings:Array[String] }. effective_islands = count AFTER bridging by valid links (1 = one
##   reachable network). dangling = links with an off-mesh endpoint. redundant = both endpoints on the SAME island
##   (bridges nothing). unreachable = islands no valid link joins to the main network. one_way_only = islands a link
##   reaches in only ONE direction (a ONE_WAY_DOWN drop), so an NPC there can't return / can't be reached.
static func reachability(navmesh: NavigationMesh, links: Array, connect_radius: float = 1.0) -> Dictionary:
	var report := {
		"raw_islands": 0, "effective_islands": 0, "ok": true,
		"dangling": [], "redundant": [], "unreachable": [], "one_way_only": [], "warnings": [],
	}
	if navmesh == null or navmesh.get_polygon_count() == 0:
		report.ok = false
		report.warnings.append("No baked navmesh — can't certify NavLinks against it.")
		return report

	var verts := navmesh.get_vertices()
	var n := navmesh.get_polygon_count()

	# Island union-find (mirrors analyze()'s edge-snap merge) + per-poly centroid & bounding radius for the
	# endpoint prefilter, + per-poly area so islands index by size (island 0 = the main floor, matching analyze()).
	var parent: Array = []
	parent.resize(n)
	for i in n:
		parent[i] = i
	var centroids: Array[Vector3] = []
	var radii := PackedFloat32Array()
	radii.resize(n)
	var areas := PackedFloat32Array()
	areas.resize(n)
	var edge_map := {}
	for i in n:
		var poly := navmesh.get_polygon(i)
		var cnt := poly.size()
		var c := Vector3.ZERO
		for k in cnt:
			c += verts[poly[k]]
		if cnt > 0:
			c /= float(cnt)
		centroids.append(c)
		var rad := 0.0
		for k in cnt:
			rad = maxf(rad, c.distance_to(verts[poly[k]]))
		radii[i] = rad
		var area := 0.0
		for k in range(1, cnt - 1):
			area += (verts[poly[k]] - verts[poly[0]]).cross(verts[poly[k + 1]] - verts[poly[0]]).length() * 0.5
		areas[i] = area
		for k in cnt:
			var key := _edge_key(verts[poly[k]], verts[poly[(k + 1) % cnt]])
			if not edge_map.has(key):
				edge_map[key] = []
			edge_map[key].append(i)
	for key in edge_map:
		var ps: Array = edge_map[key]
		for j in range(1, ps.size()):
			_union(parent, ps[0], ps[j])

	# Compact island indices, ordered by area DESC so island 0 is the largest (the "main" network).
	var root_area := {}
	for i in n:
		var r := _find(parent, i)
		root_area[r] = float(root_area.get(r, 0.0)) + areas[i]
	var roots: Array = root_area.keys()
	roots.sort_custom(func(a, b): return root_area[a] > root_area[b])
	var root_index := {}
	for idx in roots.size():
		root_index[roots[idx]] = idx
	var poly_island := PackedInt32Array()
	poly_island.resize(n)
	for i in n:
		poly_island[i] = root_index[_find(parent, i)]
	var island_count: int = roots.size()
	report.raw_islands = island_count

	# Bind each enabled link's endpoints to their nearest island (or -1 = off-mesh). A valid link (both ends on the
	# mesh, different islands) UNIONS the two islands (undirected -> the "one network?" count) and adds a DIRECTED
	# edge start->end (+end->start when bidirectional) for the one-way-trap check. NavLink orients start = the HIGHER
	# end for ONE_WAY_DOWN, so a non-bidirectional link means "you may drop from a's island to b's island only".
	var iparent: Array = []
	iparent.resize(island_count)
	for i in island_count:
		iparent[i] = i
	var adj := {}
	var radj := {}
	for li in links.size():
		var lk: Dictionary = links[li]
		var ia := _island_at(lk.a, navmesh, verts, n, centroids, radii, poly_island, connect_radius)
		var ib := _island_at(lk.b, navmesh, verts, n, centroids, radii, poly_island, connect_radius)
		if ia == -1 or ib == -1:
			report.dangling.append({"index": li, "a": lk.a, "b": lk.b, "a_on_mesh": ia != -1, "b_on_mesh": ib != -1})
			continue
		if ia == ib:
			report.redundant.append({"index": li, "island": ia})
			continue
		_union(iparent, ia, ib)
		_dir_add(adj, ia, ib)
		_dir_add(radj, ib, ia)
		if bool(lk.get("bidirectional", true)):
			_dir_add(adj, ib, ia)
			_dir_add(radj, ia, ib)

	var comp := {}
	for i in island_count:
		comp[_find(iparent, i)] = true
	report.effective_islands = comp.size()

	# Directed reachability from the main island (0): forward = who main can reach, backward = who can reach main.
	var fwd := _bfs(adj, 0, island_count)
	var bwd := _bfs(radj, 0, island_count)
	for i in range(1, island_count):
		if _find(iparent, i) != _find(iparent, 0):
			report.unreachable.append(i)  # not bridged to the main network at all
		elif not fwd.has(i) or not bwd.has(i):
			report.one_way_only.append(i)  # bridged, but a one-way link breaks the round-trip

	if report.effective_islands > 1:
		report.warnings.append("%d navmesh islands are NOT bridged into one network (%d island(s) unreachable even with links) — add a NavLink across the gap or fix the bake." % [report.effective_islands, report.unreachable.size()])
	if not report.dangling.is_empty():
		report.warnings.append("%d NavLink endpoint(s) land OFF the navmesh (> %.1f m) — those links silently bridge nothing. Nudge the handle onto a walkable surface (auto_project only rescues near-misses)." % [report.dangling.size(), connect_radius])
	if not report.one_way_only.is_empty():
		report.warnings.append("%d island(s) are reachable only ONE way (a ONE_WAY_DOWN link) — an NPC there can't get back. Add a TWO_WAY / ramp return if unintended." % report.one_way_only.size())
	report.ok = report.warnings.is_empty()
	return report

## Nearest island to a point, or -1 if no polygon is within connect_radius (an off-mesh link endpoint). Prefilters by
## centroid distance minus the poly's bounding radius so only nearby polys get the exact point->polygon test.
static func _island_at(p: Vector3, navmesh: NavigationMesh, verts: PackedVector3Array, n: int, centroids: Array[Vector3], radii: PackedFloat32Array, poly_island: PackedInt32Array, connect_radius: float) -> int:
	var best_d := INF
	var best := -1
	for i in n:
		if p.distance_to(centroids[i]) - radii[i] > connect_radius:
			continue
		var d := _point_poly_dist(p, navmesh.get_polygon(i), verts)
		if d < best_d:
			best_d = d
			best = poly_island[i]
			if best_d <= 0.0001:
				break
	return best if best_d <= connect_radius else -1

## Distance from p to a (convex) navmesh polygon, via the min over its triangle fan.
static func _point_poly_dist(p: Vector3, poly: PackedInt32Array, verts: PackedVector3Array) -> float:
	var cnt := poly.size()
	if cnt < 3:
		var d := INF
		for k in cnt:
			d = minf(d, p.distance_to(verts[poly[k]]))
		return d
	var best := INF
	for k in range(1, cnt - 1):
		best = minf(best, _closest_pt_tri(p, verts[poly[0]], verts[poly[k]], verts[poly[k + 1]]))
	return best

## Distance from point p to triangle abc (Ericson, Real-Time Collision Detection — voronoi-region closest point).
static func _closest_pt_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return p.distance_to(a)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return p.distance_to(b)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return p.distance_to(a + ab * (d1 / (d1 - d3)))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return p.distance_to(c)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return p.distance_to(a + ac * (d2 / (d2 - d6)))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return p.distance_to(b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))))
	var denom := 1.0 / (va + vb + vc)
	return p.distance_to(a + ab * (vb * denom) + ac * (vc * denom))

## Add a directed edge a->b to an adjacency map (dedup), for the island reachability BFS.
static func _dir_add(g: Dictionary, a: int, b: int) -> void:
	if not g.has(a):
		g[a] = []
	if not (b in g[a]):
		g[a].append(b)

## Breadth-first set of islands reachable from `start` over adjacency `g` (returned as a Dictionary set).
static func _bfs(g: Dictionary, start: int, _count: int) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var x: int = q.pop_back()
		for y in g.get(x, []):
			if not seen.has(y):
				seen[y] = true
				q.append(y)
	return seen

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
