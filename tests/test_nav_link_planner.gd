extends GutTest

## NavLinkPlanner (scripts/tools/nav_link_planner.gd): the pure brain that decides WHERE to auto-generate NavLink
## bridges from a baked NavigationMesh. Hand-built two-island meshes exercise the classification + budget gates off-tree
## (mirrors test_navmesh_audit.gd). The File->Run generator (generate_nav_links.gd) and actual node insertion are
## editor/playtest territory.

## Preloaded (not the `NavLinkPlanner` global) so the suite compiles even before the editor has registered the new class.
const Planner := preload("res://scripts/tools/nav_link_planner.gd")

## Two disconnected quads: A spans x[ax0,ax1] at height ay, B spans x[bx0,bx1] at height by, both z[0,1]. Different x
## AND y so they share no edge -> two islands.
func _two_quads(ax0: float, ax1: float, ay: float, bx0: float, bx1: float, by: float) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.vertices = PackedVector3Array([
		Vector3(ax0, ay, 0), Vector3(ax1, ay, 0), Vector3(ax1, ay, 1), Vector3(ax0, ay, 1),
		Vector3(bx0, by, 0), Vector3(bx1, by, 0), Vector3(bx1, by, 1), Vector3(bx0, by, 1)])
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nm.add_polygon(PackedInt32Array([4, 5, 6, 7]))
	return nm


func test_climbable_ledge_becomes_a_two_way_link() -> void:
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 3, 5, 1.0))  # gap 1 m, climb 1 m
	assert_gt(specs.size(), 0, "a climbable ledge within budget yields at least one link")
	for s in specs:
		assert_false(s.one_way_down, "a climbable (<= max_climb) delta is bidirectional")
		assert_almost_eq(float(s.climb), 1.0, 0.05, "climb read from the island height delta")


func test_flat_chasm_within_reach_is_bridged() -> void:
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 3, 5, 0.0))  # same height, 1 m gap
	assert_gt(specs.size(), 0, "a jumpable flat gap is bridged")
	for s in specs:
		assert_false(s.one_way_down, "a flat gap is two-way")


func test_cliff_becomes_one_way_down() -> void:
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 3, 5, 3.5))  # climb 3.5 m (> max_climb 3, <= max_drop 4)
	assert_gt(specs.size(), 0, "a droppable cliff still gets a link")
	for s in specs:
		assert_true(s.one_way_down, "a delta above max_climb is drop-only (can't scale it)")


func test_small_drop_only_pit_is_rescued_to_two_way() -> void:
	# A SMALL island reachable ONLY by dropping in (no other link) is a TRAP — an NPC that pursues/falls in strands there
	# forever (no A* return). The planner promotes the incoming one-way drop to a climbable TWO_WAY so it can get back out.
	# Main floor = a 2-poly island; the pit = 1 poly, 3.5 m below + 1 m aside (a drop by budget, > max_climb 3). Contrast
	# test_cliff_becomes_one_way_down, where the two islands are EQUAL size (the low one might BE the real floor), so that
	# cliff is deliberately left one-way — the size gate is what tells a pit from a floor.
	var nm := NavigationMesh.new()
	nm.vertices = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 1), Vector3(0, 0, 1),   # main poly A
		Vector3(2, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 1), Vector3(2, 0, 1),   # main poly B (shares the x=2 edge -> ONE 2-poly island)
		Vector3(5, -3.5, 0), Vector3(7, -3.5, 0), Vector3(7, -3.5, 1), Vector3(5, -3.5, 1)])  # the pit: 1 poly, below + aside
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nm.add_polygon(PackedInt32Array([4, 5, 6, 7]))
	nm.add_polygon(PackedInt32Array([8, 9, 10, 11]))
	var specs := Planner.plan(nm)
	assert_eq(specs.size(), 1, "one link between the main floor and the pit")
	assert_false(specs[0].one_way_down, "a drop-only pit SMALLER than the main floor is rescued to a climbable TWO_WAY")
	assert_almost_eq(float(specs[0].climb), 3.5, 0.05, "the rescued link still spans the 3.5 m pit depth")


func test_lethal_drop_gets_no_link() -> void:
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 3, 5, 5.0))  # climb 5 m > max_drop 4
	assert_eq(specs.size(), 0, "a drop beyond max_drop is left un-bridged (NPCs won't path off a lethal cliff)")


func test_horizontally_unreachable_gap_gets_no_link() -> void:
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 6, 8, 0.0))  # 4 m gap > max_gap_h 2
	assert_eq(specs.size(), 0, "islands too far apart horizontally are not bridged")


func test_single_connected_island_needs_no_links() -> void:
	var nm := NavigationMesh.new()
	nm.vertices = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 2), Vector3(0, 0, 2)])
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var specs := Planner.plan(nm)
	assert_eq(specs.size(), 0, "one island = nothing to bridge")


func test_empty_or_unbaked_mesh_is_safe() -> void:
	assert_eq(Planner.plan(null).size(), 0, "null mesh -> no links, no crash")
	assert_eq(Planner.plan(NavigationMesh.new()).size(), 0, "unbaked (0-poly) mesh -> no links")


func test_budget_override_can_forbid_the_climb() -> void:
	# The same 1 m climbable ledge, but a budget that caps max_climb below it -> reclassified drop-only (one-way).
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 3, 5, 1.0), {"max_climb": 0.5})
	assert_gt(specs.size(), 0, "still bridged (1 m <= max_drop)")
	for s in specs:
		assert_true(s.one_way_down, "with max_climb lowered under the delta, the link becomes one-way-down")


func test_plan_is_deterministic() -> void:
	var a := Planner.plan(_two_quads(0, 2, 0.0, 3, 5, 1.0))
	var b := Planner.plan(_two_quads(0, 2, 0.0, 3, 5, 1.0))
	assert_eq(a.size(), b.size(), "same mesh -> same link count (idempotent regeneration)")
	for i in a.size():
		assert_eq(String(a[i].key), String(b[i].key), "stable, sorted keys")


# --- Stair detection (the optional physics `probe`). The generator supplies a real raycast probe; here we inject a
# fake Callable so the classification is pure/off-tree. grounded + small steps => a WALK/stairs link. ---

func _grounded_probe() -> Callable:
	return func(_low: Vector3, _high: Vector3) -> Dictionary: return {"grounded": true, "max_step": 0.4}

func _void_probe() -> Callable:
	return func(_low: Vector3, _high: Vector3) -> Dictionary: return {"grounded": false, "max_step": 999.0}


func test_probe_makes_a_short_climb_a_walk_link_not_a_jump() -> void:
	# A 1 m gap/1 m climb is jumpable, but if the probe finds continuous stairs under it, prefer WALK over a leap.
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 3, 5, 1.0), {}, _grounded_probe())
	assert_gt(specs.size(), 0, "still bridged")
	for s in specs:
		assert_true(s.get("walk", false), "a probed-walkable gap becomes a WALK (stairs) link, not a LAUNCH")
		assert_false(s.one_way_down, "a staircase is two-way")


func test_probe_bridges_a_long_flight_that_no_jump_would() -> void:
	# 3 m run (> max_gap_h 2) — no jump link without a probe, but a WALK link WITH one (a staircase is longer than a jump).
	var mesh := _two_quads(0, 2, 0.0, 5, 7, 2.0)
	assert_eq(Planner.plan(mesh).size(), 0, "without a probe, a 3 m run is too wide to bridge")
	var walked := Planner.plan(mesh, {}, _grounded_probe())
	assert_eq(walked.size(), 1, "with a walkable probe, the long flight gets exactly one WALK link")
	assert_true(walked[0].get("walk", false), "and it's a WALK link")


func test_void_probe_does_not_invent_a_stair_link() -> void:
	# Same long run, but the probe reports a void (no ground between) -> no link (it's a real gap, not a staircase).
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 5, 7, 2.0), {}, _void_probe())
	assert_eq(specs.size(), 0, "a void gap too wide to jump stays un-bridged even with a probe")


func test_one_stair_link_per_island_pair() -> void:
	# The top island has two rims; a grounded probe would walk to either, but dedup keeps ONE (shortest) per island pair.
	var specs := Planner.plan(_two_quads(0, 2, 0.0, 3, 6, 1.0), {}, _grounded_probe())
	var walks := specs.filter(func(s): return s.get("walk", false))
	assert_eq(walks.size(), 1, "one staircase between two floors = one WALK link, not corner-to-far-corner extras")
