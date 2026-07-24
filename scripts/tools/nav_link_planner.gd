class_name NavLinkPlanner
extends RefCounted

## Plans where to auto-generate NavLink bridges. Given a BAKED NavigationMesh, it finds the DISCONNECTED-island
## boundary edges that sit within a jump/drop budget of each other and returns one link SPEC per real ledge gap —
## bidirectional where the height is climbable, one-way-DOWN where it's a cliff you can drop off but not scale. The
## File -> Run generator (scripts/tools/generate_nav_links.gd) turns each spec into an actual NavLink node.
##
## Pure + static (mesh-LOCAL coords, no transforms / no tree), so it's unit-tested off-tree exactly like NavMeshAudit —
## which it deliberately MIRRORS (same edge-snap union-find over shared edges to find islands + boundary edges). It's
## self-contained rather than reaching into NavMeshAudit's privates so that hardened, test-pinned analyzer stays untouched.
##
## LIMITATION (be honest, it's in the docs too): auto-links are only as good as the BAKE. A messy multi-island bake
## yields spurious or missing bridges, and every generated link defaults to LAUNCH traversal — a link laid over a real
## STAIRCASE should be flipped to WALK by hand (the planner can't tell a stair from a bare ledge from navmesh alone).

const EDGE_SNAP := 0.05   ## verts within 5 cm are the same point when matching shared edges (matches NavMeshAudit)

## Tunable budget (the generator passes these; the defaults here are the single source of truth). Mirrors the Locomotor
## reach: MAX_CLIMB ~ a jumpable ledge, MAX_DROP ~ Locomotor.max_pursuit_drop (won't path an NPC off a lethal cliff).
const DEFAULT_BUDGET := {
	"max_gap_h": 2.0,      ## max horizontal gap (m) a JUMP/DROP link may span — a jumpable chasm / the footprint of a wall
	"max_climb": 3.0,      ## height delta (m) at/below which a JUMP link is CLIMBABLE -> bidirectional (matches climb_warn_budget)
	"max_drop": 4.0,       ## delta (m) above max_climb still worth a one-way-DOWN link; beyond = no link (matches max_pursuit_drop)
	"min_sep": 0.15,       ## below this in BOTH axes the rims are coincident (a bake-split, not a real gap) -> skip
	"link_spacing": 2.5,   ## dedup: at most one link per this-sized cell along a rim (a long ledge gets a few, not hundreds)
	# STAIR detection (only when a `probe` Callable is supplied): a gap the probe finds is bridged by CONTINUOUS ground
	# rising in small steps (a staircase / ramp) becomes a WALK link and may span a longer run than a jump.
	"stair_run_max": 8.0,     ## max horizontal run (m) for a WALK/stair link (a flight is longer than a jumpable gap)
	"stair_climb_max": 6.0,   ## max total rise (m) a stair link may cover
	"step_walk_max": 0.6,     ## max per-step vertical increment counted as walkable stairs (= Locomotor.step_up_height)
}

## Returns Array[Dictionary]: { a: Vector3(low), b: Vector3(high), one_way_down: bool, walk: bool, climb: float,
## gap: float, key: String }. a/b are mesh-LOCAL (the generator adds the region transform). Deterministic order (sorted
## by key) so a re-run reproduces the same links / node names -> idempotent regeneration.
##
## `probe` (optional) is `Callable(low: Vector3, high: Vector3) -> Dictionary{grounded: bool, max_step: float}` — the
## generator supplies one backed by a physics raycast between the two rim points; when it reports continuous ground
## rising in <= step_walk_max increments, the gap is a STAIRCASE / ramp and becomes a `walk: true` (WALK-mode) link that
## may span a longer run than a jump. Without a probe, only jump/drop links are planned (no stair detection).
static func plan(navmesh: NavigationMesh, budget: Dictionary = {}, probe: Callable = Callable()) -> Array:
	var b := DEFAULT_BUDGET.duplicate()
	for k in budget:
		b[k] = budget[k]
	var out: Array = []
	if navmesh == null or navmesh.get_polygon_count() == 0:
		return out

	var verts := navmesh.get_vertices()
	var n := navmesh.get_polygon_count()

	# --- Islands (union-find over shared edges) + boundary edges (an edge used by exactly ONE polygon = an open rim). ---
	var parent: Array = []
	parent.resize(n)
	for i in n:
		parent[i] = i
	var edge_map := {}   # edge-key -> Array of poly indices touching it
	for i in n:
		var poly := navmesh.get_polygon(i)
		var cnt := poly.size()
		for k in cnt:
			var key := _edge_key(verts[poly[k]], verts[poly[(k + 1) % cnt]])
			if not edge_map.has(key):
				edge_map[key] = {"polys": [], "a": verts[poly[k]], "bpt": verts[poly[(k + 1) % cnt]]}
			edge_map[key].polys.append(i)
	for key in edge_map:
		var ps: Array = edge_map[key].polys
		for j in range(1, ps.size()):
			_union(parent, ps[0], ps[j])

	# Boundary edges only (size-1), tagged with their island root.
	var boundaries: Array = []   # each: {island:int, a:Vector3, b:Vector3, mid:Vector3}
	for key in edge_map:
		var e: Dictionary = edge_map[key]
		if e.polys.size() != 1:
			continue
		var island: int = _find(parent, e.polys[0])
		boundaries.append({"island": island, "a": e.a, "b": e.bpt, "mid": (e.a + e.bpt) * 0.5})

	# --- Candidate links: closest points between boundary edges of DIFFERENT islands, within the budget. ---
	var max_gap_h: float = b.max_gap_h
	var max_climb: float = b.max_climb
	var max_drop: float = b.max_drop
	var min_sep: float = b.min_sep
	var stair_run_max: float = b.stair_run_max
	var stair_climb_max: float = b.stair_climb_max
	var step_walk_max: float = b.step_walk_max
	var has_probe := probe.is_valid()
	# Widen the coarse reject to the STAIR run when a probe can classify long gaps; else just the jump gap.
	var coarse := maxf(max_gap_h, stair_run_max if has_probe else 0.0) + 6.0
	var candidates: Array = []
	for i in range(boundaries.size()):
		var ei: Dictionary = boundaries[i]
		for j in range(i + 1, boundaries.size()):
			var ej: Dictionary = boundaries[j]
			if ei.island == ej.island:
				continue
			if Vector2(ei.mid.x - ej.mid.x, ei.mid.z - ej.mid.z).length() > coarse:
				continue
			var cp := _closest_points(ei.a, ei.b, ej.a, ej.b)
			var pa: Vector3 = cp[0]
			var pb: Vector3 = cp[1]
			var dh := Vector2(pb.x - pa.x, pb.z - pa.z).length()
			var dy: float = pb.y - pa.y
			var climb := absf(dy)
			if dh < min_sep and climb < min_sep:
				continue  # coincident rims: a bake-split, not a real gap -> fixing the bake, not a link
			var low_is_a := pa.y <= pb.y  # pa is on edge i (island ei), pb on edge j (island ej)
			var low: Vector3 = pa if low_is_a else pb
			var high: Vector3 = pb if low_is_a else pa
			# STAIR/ramp: the probe finds continuous ground rising in step-sized increments between the rims. Allowed a
			# longer run than a jump; always two-way (you walk up AND down a staircase).
			var is_walk := false
			if has_probe and dh <= stair_run_max and climb <= stair_climb_max:
				var pr: Dictionary = probe.call(low, high)
				if bool(pr.get("grounded", false)) and float(pr.get("max_step", 999.0)) <= step_walk_max:
					is_walk = true
			if not is_walk and (dh > max_gap_h or climb > max_drop):
				continue  # not a walkable staircase, and too wide/tall to jump or drop -> no link (a real void)
			candidates.append({
				"a": low, "b": high, "climb": climb, "gap": dh, "walk": is_walk,
				"one_way_down": (not is_walk) and climb > max_climb,
				"ia": ei.island, "ib": ej.island,
				"low_island": (ei.island if low_is_a else ej.island),   # island of the LOW rim point (drop-INTO end)
				"high_island": (ej.island if low_is_a else ei.island),  # island of the HIGH rim point (drop-OUT / launch-from end)
				"mid": (low + high) * 0.5, "cost": dh + climb,
			})

	# --- Dedup. A JUMP/DROP ledge gets one link per link_spacing cell along its rim (a long parallel ledge would else
	# emit one candidate per rim-edge pair). A WALK/stair gap gets ONE link per ISLAND PAIR — the SHORTEST run — so a
	# staircase isn't also linked corner-to-far-corner across the upper floor. Keys are position-derived (not the
	# unstable island-root ids) so a re-bake of the same geometry reproduces the same node names (idempotent regen). ---
	var spacing: float = b.link_spacing
	var best := {}
	for c in candidates:
		var dk: String
		if c.walk:
			dk = "wk:%d-%d" % [mini(c.ia, c.ib), maxi(c.ia, c.ib)]  # one stair link per island pair (shortest)
		else:
			var kind := "dn" if c.one_way_down else "tw"
			dk = "%s:%d,%d,%d" % [kind, roundi(c.mid.x / spacing), roundi(c.mid.y / spacing), roundi(c.mid.z / spacing)]
		if not best.has(dk) or c.cost < best[dk].cost:
			best[dk] = c

	# --- Sink rescue. A SMALL island you can only DROP INTO — every link touching it is a one-way-DOWN arriving there,
	# with no walk / two-way / drop-out edge — is a TRAP: an NPC that pursues (or falls) in can never climb back, because
	# A* has no return route, so it strands in a hole forever. Promote the CHEAPEST such incoming drop to a climbable
	# TWO_WAY; the link-ascent launch is uncapped (Locomotor.jump_velocity_for_climb scales to any height, and
	# should_climb_link has no upper bound), so the NPC climbs back out however it got in. Guards against over-promotion:
	# (1) only PURE sinks (no other exit link) qualify — a normal cliff DOWN to the main floor is skipped because the main
	# floor is a hub with many other links; (2) only islands STRICTLY SMALLER than the largest island are rescued, so a
	# legitimate one-way cliff to a comparably-sized floor (and the degenerate two-island case) is left exactly as planned
	# — a "pit" is by nature a small pocket, the main walkable area is the big island. Runs after dedup, re-labelling a
	# single kept link (dn -> tw), so regeneration stays idempotent. ---
	var island_size := {}   # island root -> polygon count (which island is the big main floor vs a small pit)
	for i in n:
		var r := _find(parent, i)
		island_size[r] = int(island_size.get(r, 0)) + 1
	var max_island_size := 0
	for r in island_size:
		max_island_size = maxi(max_island_size, island_size[r])
	var links_by_island := {}   # island root -> Array of the (deduped) link dicts touching it
	for c in best.values():
		for isl in [c.ia, c.ib]:
			if not links_by_island.has(isl):
				links_by_island[isl] = []
			links_by_island[isl].append(c)
	for isl in links_by_island:
		if int(island_size.get(isl, 0)) >= max_island_size:
			continue   # the (a) largest island is the main floor, never a pit to rescue
		var has_escape := false
		var drops_in: Array = []   # one-way-down links this island is the LOW (arrival) end of
		for c in links_by_island[isl]:
			if c.walk or not c.one_way_down or c.high_island == isl:
				has_escape = true   # a walk / two-way link (both ways), or a drop-OUT to a lower island
				break
			if c.low_island == isl:
				drops_in.append(c)
		if has_escape or drops_in.is_empty():
			continue
		var cheapest: Dictionary = drops_in[0]
		for c in drops_in:
			if c.cost < cheapest.cost:
				cheapest = c
		cheapest.one_way_down = false   # mutates the shared dict in `best`: this drop is now a climbable TWO_WAY

	for dk in best:
		var c: Dictionary = best[dk]
		var kind := "wk" if c.walk else ("dn" if c.one_way_down else "tw")
		out.append({
			"a": c.a, "b": c.b, "climb": c.climb, "gap": c.gap,
			"one_way_down": c.one_way_down, "walk": c.walk,
			"key": "%s_%d_%d_%d" % [kind, roundi(c.mid.x / spacing), roundi(c.mid.y / spacing), roundi(c.mid.z / spacing)],
		})
	out.sort_custom(func(x, y): return x.key < y.key)
	return out

# --- Pure helpers (mirror NavMeshAudit's edge-snap union-find so islands match its report). ---

static func _pkey(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x / EDGE_SNAP), roundi(v.y / EDGE_SNAP), roundi(v.z / EDGE_SNAP)]

static func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := _pkey(a)
	var kb := _pkey(b)
	return (ka + "|" + kb) if ka <= kb else (kb + "|" + ka)

static func _find(parent: Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

static func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb

## Closest points between two segments (p1->q1) and (p2->q2). Standard clamped solution (Ericson, Real-Time Collision
## Detection) — a long rim edge shouldn't be reduced to its midpoint, so we bridge from the nearest points on each rim.
static func _closest_points(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-8 and e <= 1e-8:
		return [p1, p2]
	if a <= 1e-8:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-8:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var denom := a * e - bb * bb
			s = clampf((bb * f - c * e) / denom, 0.0, 1.0) if denom > 1e-8 else 0.0
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]
