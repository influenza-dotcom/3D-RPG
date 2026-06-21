extends GutTest

## NavMeshAudit.analyze() — pure off-tree analysis of a NavigationMesh (no transforms touched, so no tracked
## engine errors — see the off-tree-transform GUT trap). Builds tiny navmeshes by hand and asserts the island /
## elevated-poly detection.

func test_flat_connected_mesh_is_one_clean_island() -> void:
	var nm := NavigationMesh.new()
	# Two triangles sharing the diagonal edge (verts 0-2) = one connected quad on a flat floor.
	nm.set_vertices(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
	]))
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	nm.add_polygon(PackedInt32Array([0, 2, 3]))
	var rep := NavMeshAudit.analyze(nm)
	assert_eq(rep.poly_count, 2, "two polygons")
	assert_eq(rep.islands.size(), 1, "tris sharing an edge collapse to one island")
	assert_eq(rep.elevated.size(), 0, "nothing is above the floor")
	assert_true(rep.ok, "a flat connected mesh has no warnings")
	nm = null

func test_detached_elevated_quad_is_flagged_island_and_roof() -> void:
	var nm := NavigationMesh.new()
	# A big floor at y=0 (verts 0-3) + a small detached quad at y=2 (verts 4-7) far away (a "car roof").
	nm.set_vertices(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), Vector3(0, 0, 10),
		Vector3(20, 2, 20), Vector3(21, 2, 20), Vector3(21, 2, 21), Vector3(20, 2, 21),
	]))
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	nm.add_polygon(PackedInt32Array([0, 2, 3]))
	nm.add_polygon(PackedInt32Array([4, 5, 6]))
	nm.add_polygon(PackedInt32Array([4, 6, 7]))
	var rep := NavMeshAudit.analyze(nm)
	assert_eq(rep.islands.size(), 2, "floor + detached roof = two islands")
	assert_almost_eq(rep.floor_y, 0.0, 0.01, "the larger island (floor) sets floor_y")
	assert_gt(rep.elevated.size(), 0, "the y=2 polys are flagged as elevated roof polys")
	assert_false(rep.ok, "disconnected + elevated = warnings present")
	nm = null

func test_unbaked_mesh_warns_zero_polygons() -> void:
	var nm := NavigationMesh.new()
	var rep := NavMeshAudit.analyze(nm)
	assert_eq(rep.poly_count, 0, "fresh mesh has no polys")
	assert_false(rep.ok, "an unbaked mesh is not ok")
	assert_gt(rep.warnings.size(), 0, "it warns to bake")
	nm = null

func test_null_mesh_is_handled() -> void:
	var rep := NavMeshAudit.analyze(null)
	assert_false(rep.ok, "a null navmesh is reported, not crashed")
	assert_gt(rep.warnings.size(), 0, "it says there's no mesh")
