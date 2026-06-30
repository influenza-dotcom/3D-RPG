extends GutTest

## Contract tests for the CYBER SUNDAY CSG-blockout builders (addons/cybersunday_tools/dock_place/csg_blockout.gd).
## These guard the invariants the navmesh bake depends on: every piece is in the (PERSISTENT) `navmesh` group, root
## CSG shapes have collision, ramps stay under the agent_max_slope baseline, and a building shell's doorway never
## drops below the width that keeps the interior connected to the exterior as ONE navmesh island.
## Pure off-tree construction — no editor, no tree (see scene_placer.gd for the editor placement glue).

const CsgBlockout := preload("res://addons/cybersunday_tools/dock_place/csg_blockout.gd")
const NAV_GROUP := &"navmesh"


func test_floor_is_grouped_collidable_box() -> void:
	var f: CSGBox3D = CsgBlockout.build_floor()
	assert_true(f is CSGBox3D, "floor is a CSGBox3D")
	assert_true(f.use_collision, "floor has collision so the bake can read it / props rest on it")
	assert_true(f.is_in_group(NAV_GROUP), "floor is in the navmesh group so it feeds the bake")
	assert_almost_eq(f.position.y, -f.size.y * 0.5, 0.001, "floor top face sits at y=0")
	f.free()


func test_wall_base_at_floor() -> void:
	var w: CSGBox3D = CsgBlockout.build_wall()
	assert_true(w.use_collision, "wall has collision")
	assert_true(w.is_in_group(NAV_GROUP), "wall is in the navmesh group")
	assert_almost_eq(w.position.y, w.size.y * 0.5, 0.001, "wall base sits at y=0 (rests on the floor)")
	w.free()


func test_ramp_slope_clamped_under_agent_max_slope() -> void:
	# Ask for an absurd rise; the builder must clamp the tilt to <= 28° (a margin under agent_max_slope=30).
	var r: CSGBox3D = CsgBlockout.build_ramp(3.0, 6.0, 999.0)
	assert_true(r.is_in_group(NAV_GROUP), "ramp is in the navmesh group")
	assert_true(r.use_collision, "ramp has collision")
	assert_lte(absf(r.rotation_degrees.x), 28.001, "ramp tilt is clamped to a walkable slope")
	r.free()


func test_room_shell_is_grouped_combiner_with_walls() -> void:
	var room: CSGCombiner3D = CsgBlockout.build_room_shell()
	assert_true(room is CSGCombiner3D, "shell root is a CSGCombiner3D")
	assert_true(room.use_collision, "shell combiner has collision")
	assert_true(room.is_in_group(NAV_GROUP), "shell is in the navmesh group")
	# back + left + right + two front segments = 5 wall boxes (no floor — it sits on the open ground).
	assert_eq(room.get_child_count(), 5, "shell has 4 walls with the front split around a doorway")
	for c in room.get_children():
		assert_true(c is CSGBox3D, "every shell child is a CSGBox3D wall")
		assert_false(c.is_in_group(NAV_GROUP), "wall children are NOT separately grouped (the combiner is)")
	room.free()


func test_navmesh_group_membership_is_persistent() -> void:
	# Non-persistent group membership would NOT be written to the .tscn on save -> the piece silently drops out of
	# the bake after reload. get_groups() includes both kinds, so check the persistent set the packer serializes.
	var f: CSGBox3D = CsgBlockout.build_floor()
	var node := Node.new()
	add_child_autofree(node)
	node.add_child(f)
	f.owner = node
	var packed := PackedScene.new()
	assert_eq(packed.pack(node), OK, "packs the owned subtree")
	var reloaded := packed.instantiate()
	var floor_again: Node = reloaded.get_child(0)
	assert_true(floor_again.is_in_group(NAV_GROUP), "navmesh group survives a pack/instantiate round-trip")
	reloaded.free()


func test_doorway_never_below_minimum_clear() -> void:
	# Even when asked for a 0.5 m door, the builder must floor it to DOOR_MIN_CLEAR so the interior stays reachable.
	var room: CSGCombiner3D = CsgBlockout.build_room_shell(Vector2(8, 8), 3.0, 0.3, 0.5)
	var hz := 4.0  # +Z wall line for an 8 m interior
	var min_inner_edge := INF
	for c in room.get_children():
		var box := c as CSGBox3D
		if absf(box.position.z - hz) < 0.01:  # a front-wall segment
			min_inner_edge = minf(min_inner_edge, absf(box.position.x) - box.size.x * 0.5)
	assert_true(is_finite(min_inner_edge), "found the two front-wall segments")
	# clear opening = 2 * the nearest segment's inner edge to center.
	assert_gte(2.0 * min_inner_edge, CsgBlockout.DOOR_MIN_CLEAR - 0.001, "doorway is floored to the minimum clear width")
	room.free()
