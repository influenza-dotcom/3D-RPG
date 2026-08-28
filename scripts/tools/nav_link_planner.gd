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

## Float-safety margins (metres) on the two CONSERVATIVE pre-rejects in the rim scan below. Both bounds they guard are
## exact in real arithmetic; the slack only has to swallow float32 rounding in the closest-point solve (worst case
## ~1e-4 m at this map's coordinate magnitudes). Erring WIDE is free — a pair a pre-reject lets through is simply
## tested the normal way — so these are numerical safety margins, NOT designer tunables. Do not fold them into
## DEFAULT_BUDGET: they are not gameplay numbers, and shrinking either one can silently change the planned links.
const GRID_SLACK := 1e-4        ## on the midpoint triangle-inequality bound (also what the rim grid's ring is sized from)
const PRE_REJECT_SLACK := 0.01  ## on the rim-AABB gap bound

## Rim-bucket cells per `coarse` radius (with a matching ±GRID_DIV ring). See the scan below: a cell exactly one search
## radius across forces a 3x3 square around the rim, ~2/3 of which is out of range yet still gathered and tested. Exact
## for any value >= 1 — the ring scales with it — so a future bake that regresses can be retuned by editing this one
## number. Measured on the live map: 5.49 M gathered rim pairs at 1, 1.71 M at 4, 1.50 M at 6 (past the knee).
const GRID_DIV := 4

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

	# Boundary edges only (size-1), tagged with their island root. Held as PARALLEL PACKED ARRAYS rather than an Array
	# of {island, a, b, mid} Dictionaries: the rim-pair scan below reads these MILLIONS of times (5.5 M pair visits on
	# the live map) and every Dictionary field read is a hash lookup where a PackedInt32Array / PackedVector3Array
	# subscript is a direct index. Same values, same append order, so rim index i is exactly what `boundaries[i]` was.
	#   rim_lo / rim_hi -- the rim segment's XZ+Y bounding box, for the conservative AABB pre-reject in the scan.
	#   rim_hxz         -- HALF the rim's XZ length, for the tightened midpoint reject and the grid's ring/cell prune.
	#   rim_d / rim_dd  -- the segment direction (b - a) and its self dot product. Both are inputs to the closest-point
	#                      solve that depend on ONE rim only, so they are computed once per RIM here rather than once
	#                      per PAIR down there. rim_dd is float64 so the dot survives the round trip bit-for-bit.
	var rim_island := PackedInt32Array()
	var rim_a := PackedVector3Array()
	var rim_mid := PackedVector3Array()
	var rim_lo := PackedVector3Array()
	var rim_hi := PackedVector3Array()
	var rim_d := PackedVector3Array()
	var rim_dd := PackedFloat64Array()
	var rim_hxz := PackedFloat64Array()
	for key in edge_map:
		var e: Dictionary = edge_map[key]
		if e.polys.size() != 1:
			continue
		var ea: Vector3 = e.a
		var eb: Vector3 = e.bpt
		rim_island.append(_find(parent, e.polys[0]))
		rim_a.append(ea)
		rim_mid.append((ea + eb) * 0.5)
		rim_lo.append(Vector3(minf(ea.x, eb.x), minf(ea.y, eb.y), minf(ea.z, eb.z)))
		rim_hi.append(Vector3(maxf(ea.x, eb.x), maxf(ea.y, eb.y), maxf(ea.z, eb.z)))
		var ed := eb - ea
		rim_d.append(ed)
		rim_dd.append(ed.dot(ed))
		rim_hxz.append(0.5 * Vector2(eb.x - ea.x, eb.z - ea.z).length())
	var rim_count := rim_island.size()

	# --- Candidate links: closest points between boundary edges of DIFFERENT islands, within the budget. ---
	var max_gap_h: float = b.max_gap_h
	var max_climb: float = b.max_climb
	var max_drop: float = b.max_drop
	var min_sep: float = b.min_sep
	var stair_run_max: float = b.stair_run_max
	var stair_climb_max: float = b.stair_climb_max
	var step_walk_max: float = b.step_walk_max
	var has_probe := probe.is_valid()
	# `reach` = the widest horizontal gap ANY branch below can still admit: the stair window needs dh <= stair_run_max
	# (probe only) and `jumpable` needs dh <= max_gap_h. `coarse` is that plus midpoint slop — see the reject below,
	# and DO NOT "correct" the +6.0 to the mathematically exact segment-to-segment slop. This map's longest rim is
	# 75.75 m, so the exact slop would be 2 * 37.9 m: `coarse` is already far NARROWER than the true bound, it prunes
	# some pairs whose real closest points are in budget, and that pruning is baked into every shipped link name.
	# Widening it (or narrowing it) changes the emitted keys and breaks idempotent regeneration.
	var reach := maxf(max_gap_h, stair_run_max if has_probe else 0.0)
	var coarse := reach + 6.0
	# The widest a KEPT rim pair can ever be, horizontally and vertically. A record only survives the scan if it lands
	# in the STAIR WINDOW (dh <= stair_run_max and climb <= stair_climb_max, probe only) or is JUMPABLE (dh <=
	# max_gap_h and climb <= max_drop); outside the union of those two boxes nothing can be kept. The AABB pre-reject
	# in the scan uses this to throw a pair away BEFORE paying for the closest-point solve and the record Dictionary.
	var reach_h := reach + PRE_REJECT_SLACK
	var reach_h2 := reach_h * reach_h
	var reach_v: float = (maxf(max_drop, stair_climb_max) if has_probe else max_drop) + PRE_REJECT_SLACK
	var candidates: Array = []
	var pending := {}   # Vector2i(island_lo, island_hi) -> Array of rim-pair records awaiting a STAIR probe
	# Rim pairs come from an XZ SPATIAL BUCKET, not an all-pairs scan: a rim only visits the cells its own search
	# radius can reach, and everything else is rejected without ever being touched. This is EXACT (identical candidate
	# set), not a sampling heuristic — the grid decides only what to LOOK AT, the rejects inside the j loop decide what
	# is admitted.
	# WHY IT MATTERS: the old `for i / for j in range(i+1, …)` scan was O(B^2) in the boundary-edge count. That was
	# fine on the small test levels it was written against, but the live map bakes B = 10 082 rims — 50 MILLION pair
	# tests of pure GDScript before a single link is planned, on top of ~65 k stair probes. File→Run blocks the
	# editor's main thread, so the Output panel cannot repaint while it churns: the tool printed its header and then
	# FROZE the editor for a minute with nothing on screen, which reads exactly like "it does nothing".
	# THE CELL IS FINER THAN THE SEARCH RADIUS (`coarse` / GRID_DIV, with a matching ±GRID_DIV ring). A cell exactly
	# `coarse` across forces a 3x3 = 42x42 m square around a 14 m reach and ~2/3 of that square is out of range yet
	# still gathered and distance-tested. A finer cell probes more cells per rim (9 -> 81 dictionary lookups) but each
	# holds far less, and a cell whose nearest corner is already out of budget is skipped whole. Measured on the live
	# map: 5.49 M gathered rim pairs -> 1.71 M, with byte-identical output.
	# THE VISIT ORDER IS PART OF THE CONTRACT: dedup below is first-wins on a cost tie and the generated node names
	# must stay reproducible for regeneration to be idempotent, so every pair must still be visited (i ascending, then
	# j ascending) exactly as the old O(B^2) scan visited it. Two things keep that true no matter which cells the grid
	# happened to gather from: `near.sort()` restores ascending j, and each record's `order` stamp is the pair's
	# LEXICOGRAPHIC RANK i * rim_count + j rather than a running counter (see the stamp below).
	var cell_size: float = maxf(coarse, 0.001) / float(GRID_DIV)
	var buckets := {}   # Vector2i cell -> PackedInt32Array of rim indices, ascending (the build loop below appends in i order)
	var cellcap := {}   # Vector2i cell -> the longest rim_hxz in it (lets a whole cell be skipped, see below)
	var hmax := 0.0     # the longest half-rim anywhere: the most a partner's own length can stretch the pair bound
	for i in range(rim_count):
		var bm: Vector3 = rim_mid[i]
		var bh: float = rim_hxz[i]
		hmax = maxf(hmax, bh)
		var bk := Vector2i(floori(bm.x / cell_size), floori(bm.z / cell_size))
		if not buckets.has(bk):
			buckets[bk] = PackedInt32Array()
			cellcap[bk] = 0.0
		buckets[bk].append(i)
		cellcap[bk] = maxf(float(cellcap[bk]), bh)
	for i in range(rim_count):
		# Everything about rim i is hoisted out of the j loop — read once here instead of once per neighbour below.
		var i_isl := rim_island[i]
		var i_mid: Vector3 = rim_mid[i]
		var i_a: Vector3 = rim_a[i]
		var i_lo: Vector3 = rim_lo[i]
		var i_hi: Vector3 = rim_hi[i]
		var d1: Vector3 = rim_d[i]
		var aa: float = rim_dd[i]
		var mix := i_mid.x
		var miz := i_mid.z
		var lim_i: float = reach + float(rim_hxz[i]) + GRID_SLACK   # this rim's half of the exact pair bound (see the reject)
		var r_i := minf(coarse, lim_i + hmax)   # not even the longest rim on the map could qualify past this
		var irank := i * rim_count   # base of this rim's slice of the (i asc, j asc) lexicographic rank — see `order`
		var cx := floori(mix / cell_size)
		var cz := floori(miz / cell_size)
		var ring := ceili(r_i / cell_size)   # every cell that can hold a partner (cell_size * ring >= r_i)
		var near := PackedInt32Array()
		for ox in range(-ring, ring + 1):
			for oz in range(-ring, ring + 1):
				var nk := Vector2i(cx + ox, cz + oz)
				var arr: Variant = buckets.get(nk)   # one hash instead of has() + [] (null = no such cell)
				if arr == null:
					continue
				# Skip the whole cell when even its NEAREST corner, paired with the LONGEST rim it holds, is already
				# out of budget: every rim inside is then guaranteed to fail the per-pair reject below, so none is read.
				var lox := float(cx + ox) * cell_size
				var loz := float(cz + oz) * cell_size
				var ddx := maxf(0.0, maxf(lox - mix, mix - (lox + cell_size)))
				var ddz := maxf(0.0, maxf(loz - miz, miz - (loz + cell_size)))
				var thr := minf(coarse, lim_i + float(cellcap[nk]))
				if ddx * ddx + ddz * ddz > thr * thr:
					continue
				# Each bucket was filled by the ASCENDING `i` loop above, so it is ALREADY sorted and its entries are
				# unique. bsearch finds where j > i starts (each unordered pair once, keeping the old scan's i < j
				# orientation — low_is_a depends on it) and the tail is copied in ONE memcpy, instead of testing and
				# appending millions of entries one at a time. Same values, same ascending order.
				# INVARIANT: this is only correct because each rim lands in exactly one cell, appended in i order. If
				# the bucket build above ever changes, re-sort each bucket or go back to a filtered element-wise walk.
				var cell: PackedInt32Array = arr
				var start := cell.bsearch(i + 1, true)
				if start < cell.size():
					near.append_array(cell.slice(start))
		near.sort()   # the ring's cells contribute ascending runs; one sort restores the (i asc, j asc) visit order
		for j in near:
			var j_isl := rim_island[j]
			if i_isl == j_isl:
				continue
			# COARSE REJECT, in two halves that are BOTH exact. First the original global radius (see `coarse` above —
			# it is part of the contract and must not move). Then a tighter per-pair one: this test compares rim
			# MIDPOINTS, but the budget applies to the segment-to-segment CLOSEST POINTS, and
			# |mid_i - mid_j|_xz <= h_i + dh + h_j (h = the rim's XZ half-length). So a pair whose midpoints are more
			# than reach + h_i + h_j apart must have dh > reach, and nothing below admits dh > reach — it can never
			# produce a link, whatever the probe says. It is layered ON TOP of `coarse`, never in place of it: for this
			# map's few giant rims reach + h_i + h_j is WIDER than `coarse`, so swapping to it outright would ADMIT
			# pairs the shipped links have never seen. Effectively min() of the two.
			var j_mid: Vector3 = rim_mid[j]
			var dmid := Vector2(mix - j_mid.x, miz - j_mid.z).length()
			if dmid > coarse:
				continue
			if dmid > lim_i + float(rim_hxz[j]):
				continue
			# CONSERVATIVE pre-reject on the two rims' bounding boxes, ahead of the closest-point solve. The gap
			# between the boxes is a LOWER BOUND on the distance between ANY point of rim i and any point of rim j,
			# and the solve's answer is one such point pair — so a box gap past `reach` PROVES the resulting dh /
			# climb blows the budget and the record would be thrown away. It can only reject pairs the scan was going
			# to drop anyway; the budget tests further down are still what decides admission. On the live map the two
			# bounds together take 1.71 M closest-point solves down to 339 k.
			var j_lo: Vector3 = rim_lo[j]
			var j_hi: Vector3 = rim_hi[j]
			if maxf(i_lo.y - j_hi.y, j_lo.y - i_hi.y) > reach_v:
				continue
			var gx := maxf(maxf(i_lo.x - j_hi.x, j_lo.x - i_hi.x), 0.0)
			var gz := maxf(maxf(i_lo.z - j_hi.z, j_lo.z - i_hi.z), 0.0)
			if gx * gx + gz * gz > reach_h2:
				continue
			# Closest points between the two rim segments — standard clamped solution (Ericson, Real-Time Collision
			# Detection). A long rim edge shouldn't be reduced to its midpoint, so we bridge from the nearest points
			# on each rim. INLINED (it used to be a `_closest_points()` helper) because the helper returned its two
			# points in a freshly allocated Array, once per surviving pair.
			var j_a: Vector3 = rim_a[j]
			var d2: Vector3 = rim_d[j]
			var ee: float = rim_dd[j]
			var rr := i_a - j_a
			var ff := d2.dot(rr)
			var ss := 0.0
			var tt := 0.0
			var pa := i_a
			var pb := j_a
			if aa > 1e-8 or ee > 1e-8:   # else BOTH rims are degenerate points: pa/pb stay at the two endpoints
				if aa <= 1e-8:
					tt = clampf(ff / ee, 0.0, 1.0)
				else:
					var cc := d1.dot(rr)
					if ee <= 1e-8:
						ss = clampf(-cc / aa, 0.0, 1.0)
					else:
						var bb2 := d1.dot(d2)
						var denom := aa * ee - bb2 * bb2
						ss = clampf((bb2 * ff - cc * ee) / denom, 0.0, 1.0) if denom > 1e-8 else 0.0
						tt = (bb2 * ss + ff) / ee
						if tt < 0.0:
							tt = 0.0
							ss = clampf(-cc / aa, 0.0, 1.0)
						elif tt > 1.0:
							tt = 1.0
							ss = clampf((bb2 - cc) / aa, 0.0, 1.0)
				pa = i_a + d1 * ss
				pb = j_a + d2 * tt
			var dh := Vector2(pb.x - pa.x, pb.z - pa.z).length()
			var dy: float = pb.y - pa.y
			var climb := absf(dy)
			if dh < min_sep and climb < min_sep:
				continue  # coincident rims: a bake-split, not a real gap -> fixing the bake, not a link
			var jumpable := dh <= max_gap_h and climb <= max_drop
			# STAIR/ramp window: the probe may find continuous ground rising in step-sized increments between the rims.
			# Allowed a longer run than a jump; always two-way (you walk up AND down a staircase).
			# The probe is DEFERRED rather than fired here, because firing it here asks the physics server the same
			# question once per rim PAIR while the dedup below keeps only ONE walk link per ISLAND pair. On the live map
			# that was 268 k probes (13 raycasts each) to elect 245 winners — the bulk of the tool's runtime, spent
			# almost entirely on rim pairs that were about to be thrown away. Batched by island pair in _resolve_stairs.
			var stair_window := has_probe and dh <= stair_run_max and climb <= stair_climb_max
			# Decide the pair's fate BEFORE allocating anything for it. A pair that is neither in the stair window nor
			# jumpable is a real void (too wide/tall to walk, jump or drop) -> no link. Its record used to be built in
			# full and dropped one line later, and on the live map that was 80% of every record allocated: 1.37 M of
			# 1.71 M 14-key Dictionaries built purely to be discarded.
			if not stair_window and not jumpable:
				continue
			var low_is_a := pa.y <= pb.y  # pa is on edge i (island i_isl), pb on edge j (island j_isl)
			var low: Vector3 = pa if low_is_a else pb
			var high: Vector3 = pb if low_is_a else pa
			var rec := {
				"a": low, "b": high, "climb": climb, "gap": dh, "walk": false,
				"one_way_down": (not jumpable) or climb > max_climb,   # provisional; re-decided once `walk` is known
				"ia": i_isl, "ib": j_isl,
				"low_island": (i_isl if low_is_a else j_isl),   # island of the LOW rim point (drop-INTO end)
				"high_island": (j_isl if low_is_a else i_isl),  # island of the HIGH rim point (drop-OUT / launch-from end)
				"mid": (low + high) * 0.5, "cost": dh + climb,
				"jumpable": jumpable,
				# This pair's position in the (i ascending, j ascending) scan — restores scan order below. i * B + j is
				# that position as a LEXICOGRAPHIC RANK rather than a running counter: with 0 <= j < B it is strictly
				# increasing in (i, j), so every `order` comparison lands exactly where a seq++ counter would have put
				# it — and it stays correct even though the rejects above skip building a record for most pairs, and
				# would stay correct if a future pass visited j out of order. Max B^2-1 ~ 1.0e8 at B = 10 k rims,
				# nowhere near the 64-bit int range. `order` is private to plan(): the only readers are the two
				# `x.order < y.order` comparisons below, so only its ORDERING is ever observed.
				"order": irank + j,
			}
			if stair_window:
				var pk := Vector2i(mini(i_isl, j_isl), maxi(i_isl, j_isl))
				if not pending.has(pk):
					pending[pk] = []
				pending[pk].append(rec)
				continue
			rec.one_way_down = climb > max_climb
			candidates.append(rec)

	# --- Resolve the deferred STAIR probes, then put every candidate back in scan order so the dedup below behaves
	# exactly as it did when the probe fired inline (it keeps the FIRST candidate on a cost tie, so order is part of
	# the contract that makes regenerated node names reproducible). ---
	_resolve_stairs(pending, candidates, probe, step_walk_max, max_climb)
	candidates.sort_custom(func(x, y): return x.order < y.order)

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

## Fire the deferred STAIR probes and append the surviving rim pairs to `candidates`.
##
## Every record here sits in the stair WINDOW (short enough run + rise that continuous ground between the rims would
## make it a walkable flight), so the inline version probed all of them. But the dedup elects only ONE walk link per
## ISLAND PAIR — the cheapest — so for each pair we probe in ascending cost and STOP at the first flight we find: any
## later record has cost >= the winner's and would lose the `wk:` slot anyway. What still has to be probed after a
## winner is found is the JUMPABLE leftovers, and only those: a leftover that is not a stair falls through to the
## jump/drop branch and can earn its own spacing-cell link, so its stair verdict still matters. A leftover that is
## neither the winner nor jumpable is exactly the case the inline version probed and then discarded.
##
## This is an elimination of redundant work, not a change of policy: the elected winner, the jump/drop fallthroughs and
## the discarded pairs are all identical to probing every record inline.
static func _resolve_stairs(pending: Dictionary, candidates: Array, probe: Callable, step_walk_max: float, max_climb: float) -> void:
	for pk in pending:
		var lst: Array = pending[pk]
		# Cheapest first, ties broken by scan order — the same winner the inline probe + dedup would have elected.
		lst.sort_custom(func(x, y): return x.order < y.order if is_equal_approx(x.cost, y.cost) else x.cost < y.cost)
		var won := false
		for rec in lst:
			var is_walk := false
			if not won:
				var pr: Dictionary = probe.call(rec.a, rec.b)
				if bool(pr.get("grounded", false)) and float(pr.get("max_step", 999.0)) <= step_walk_max:
					is_walk = true
					won = true
			elif rec.jumpable:
				var pr2: Dictionary = probe.call(rec.a, rec.b)
				if bool(pr2.get("grounded", false)) and float(pr2.get("max_step", 999.0)) <= step_walk_max:
					is_walk = true   # a stair that will lose the wk: dedup to the cheaper winner — kept so it still loses
			else:
				continue   # cannot win the wk: slot and cannot be a jump either: the inline probe threw this away too
			if not is_walk and not rec.jumpable:
				continue   # not a walkable staircase, and too wide/tall to jump or drop -> no link (a real void)
			rec.walk = is_walk
			rec.one_way_down = (not is_walk) and rec.climb > max_climb
			candidates.append(rec)


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
