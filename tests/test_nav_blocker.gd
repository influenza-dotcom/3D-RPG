extends GutTest

## NavBlocker drop-in (navmesh carve / dynamic avoidance). In-tree via add_child_autofree so _ready -> _apply
## runs with a real parent collider to size from; the component is lightweight (no weapon/nav/audio), so its
## _ready is safe to run here. Pure config assertions — the actual bake carve / runtime steering is playtest-verified.

func _host_with_box(size: Vector3) -> Node3D:
	var host := Node3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	host.add_child(cs)
	return host


func test_carve_mode_carves_a_footprint_from_the_box() -> void:
	var host := _host_with_box(Vector3(2.0, 1.0, 4.0))
	var nb := NavBlocker.new()
	nb.mode = NavBlocker.Mode.CARVE
	host.add_child(nb)
	add_child_autofree(host)  # _ready -> _apply with the collider present
	assert_true(nb.affect_navigation_mesh, "CARVE discards source geometry in the bake (no walkable roof)")
	assert_true(nb.carve_navigation_mesh, "CARVE cuts the footprint hole so paths route around")
	assert_false(nb.avoidance_enabled, "CARVE is static — no runtime avoidance")
	assert_eq(nb.vertices.size(), 4, "CARVE builds a 4-corner footprint polygon")
	assert_almost_eq(nb.vertices[2].x, 1.0, 0.01, "footprint half-width from the 2 m box X")
	assert_almost_eq(nb.vertices[2].z, 2.0, 0.01, "footprint half-depth from the 4 m box Z")
	assert_almost_eq(nb.height, 1.0, 0.01, "height = the box Y size")


func test_avoid_mode_is_a_dynamic_rvo_obstacle() -> void:
	var host := _host_with_box(Vector3(2.0, 2.0, 2.0))
	var nb := NavBlocker.new()
	nb.mode = NavBlocker.Mode.AVOID
	host.add_child(nb)
	add_child_autofree(host)
	assert_true(nb.avoidance_enabled, "AVOID is a runtime RVO obstacle agents steer around")
	assert_false(nb.affect_navigation_mesh, "AVOID doesn't touch the bake")
	assert_false(nb.carve_navigation_mesh, "AVOID doesn't carve")
	assert_almost_eq(nb.radius, 1.0, 0.01, "AVOID radius from the box half-extent")
	assert_eq(nb.vertices.size(), 0, "AVOID uses a radius, not a carve polygon")


func test_size_override_wins_over_the_collider() -> void:
	var host := _host_with_box(Vector3(2.0, 2.0, 2.0))
	var nb := NavBlocker.new()
	nb.size_override = Vector3(3.0, 0.5, 5.0)  # half-extents
	nb.mode = NavBlocker.Mode.CARVE
	host.add_child(nb)
	add_child_autofree(host)
	assert_almost_eq(nb.vertices[2].x, 3.0, 0.01, "size_override half-width is used, not the box")
	assert_almost_eq(nb.vertices[2].z, 5.0, 0.01, "size_override half-depth is used")
	assert_almost_eq(nb.height, 1.0, 0.01, "height = size_override Y * 2")


func test_no_collider_falls_back_without_crashing() -> void:
	var nb := NavBlocker.new()
	var host := Node3D.new()  # no collider
	host.add_child(nb)
	add_child_autofree(host)
	assert_eq(nb.vertices.size(), 4, "CARVE still builds a (fallback ~1 m) footprint with no collider")
	assert_true(nb._get_configuration_warnings().size() >= 1, "and config-warns that it can't auto-size")
