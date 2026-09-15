extends GutTest

## NavigationUtils (scripts/npc/navigation_utils.gd) is the ONE gate every nav-map query in the project stands
## behind (Locomotor, NPC snap, CompanionFollow, NavLink, the soak/smoke harnesses). Two levels:
##   is_nav_map_ready   — RID valid AND iteration_id != 0 (querying earlier ERRORS "query made before first map
##                        synchronization").
##   map_answers_queries — STRONGER: at iteration 1 the map is "ready but lying" (answers the origin for every
##                        probe); a one-shot (NavLink.auto_project) must wait until a real probe stops answering
##                        ZERO. A probe within a metre of the origin can't be told from that failure, so it passes
##                        optimistically.
## Pinned with concrete RIDs / vectors: an invalid RID, a fresh unsynced map, and a real one-polygon map driven
## through physics frames until it answers truthfully (mirrors the headless measurement in the source comment).

const PROBE := Vector3(5.0, 0.0, 5.0)


func test_invalid_rid_is_never_ready_nor_answering() -> void:
	assert_false(NavigationUtils.is_nav_map_ready(RID()),
		"an invalid RID (agent not yet on a map) is not ready — and must short-circuit before touching the server")
	assert_false(NavigationUtils.map_answers_queries(RID(), PROBE),
		"an invalid map answers nothing")
	assert_false(NavigationUtils.map_answers_queries(RID(), Vector3.ZERO),
		"the origin-probe optimism sits BEHIND the readiness gate — an invalid map never passes")


func test_fresh_map_is_not_ready_before_its_first_sync() -> void:
	var map := NavigationServer3D.map_create()
	assert_true(map.is_valid(), "map_create hands back a valid RID")
	assert_eq(NavigationServer3D.map_get_iteration_id(map), 0,
		"a map that has never synced sits at iteration 0 (the state the gate exists for)")
	assert_false(NavigationUtils.is_nav_map_ready(map),
		"iteration 0 = not ready, even though the RID is valid")
	assert_false(NavigationUtils.map_answers_queries(map, PROBE),
		"the stronger gate is at least as strict as the weak one")
	assert_false(NavigationUtils.map_answers_queries(map, Vector3(0.2, 0.0, 0.1)),
		"an origin probe still fails an UNSYNCED map — optimism only applies once ready")
	NavigationServer3D.free_rid(map)


func test_synced_one_polygon_map_answers_queries_truthfully() -> void:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(-10.0, 0.0, -10.0), Vector3(10.0, 0.0, -10.0), Vector3(10.0, 0.0, 10.0), Vector3(-10.0, 0.0, 10.0)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	# Drive physics frames until the map answers the probe truthfully (the source measured iteration 1 lying and
	# iteration 2 truthful on a one-polygon map); cap it so a broken server can't hang the run.
	var frames := 0
	while frames < 120 and not NavigationUtils.map_answers_queries(map, PROBE):
		await get_tree().physics_frame
		frames += 1
	assert_true(NavigationUtils.is_nav_map_ready(map),
		"after %d physics frames the map must have synced at least once (iteration_id != 0)" % frames)
	assert_true(NavigationUtils.map_answers_queries(map, PROBE),
		"a synced map with a polygon under the probe answers it (took %d physics frames)" % frames)
	var closest := NavigationServer3D.map_get_closest_point(map, PROBE)
	assert_true(closest.is_equal_approx(PROBE),
		"the probe lies ON the polygon, so the truthful answer is the probe itself, got %s" % str(closest))
	assert_true(NavigationUtils.map_answers_queries(map, Vector3(0.3, 0.0, 0.2)),
		"a probe within a metre of the origin passes optimistically on a ready map (it can't be told from the 'answered origin' failure)")
	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)


func test_static_only_helper_surface() -> void:
	var u := NavigationUtils.new()
	assert_true(u.has_method("is_nav_map_ready"), "is_nav_map_ready is the weak gate every retrying query uses")
	assert_true(u.has_method("map_answers_queries"), "map_answers_queries is the strong gate every one-shot query uses")
	u = null
