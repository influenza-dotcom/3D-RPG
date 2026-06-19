extends GutTest

## Slice 4 (Patrol): PatrolPath waypoint accessors + PatrolBehavior index traversal (loop wrap vs ping-pong)
## and is_active() gating. The act() drive reuses the NPC's _move_toward / _face_travel (navmesh pathing) and is
## playtest-verified; here we test the pure routing math. get_waypoint() reads global_position, so that one test
## runs IN-TREE (off-tree global_position raises a GUT-tracked engine error) — the rest are tree-free.

func _path_with(n: int, loops: bool) -> PatrolPath:
	var p := PatrolPath.new()
	p.loop = loops
	for i in n:
		var m := Marker3D.new()
		m.position = Vector3(i, 0, 0)
		p.add_child(m)
	return p

func test_waypoint_count_and_positions() -> void:
	var p := _path_with(3, true)
	add_child_autofree(p)  # in-tree so global_position is valid (off-tree it raises a tracked engine error)
	assert_eq(p.get_waypoint_count(), 3, "counts the Node3D children")
	assert_almost_eq(p.get_waypoint(1).x, 1.0, 0.001, "waypoint 1 is the 2nd marker")

func test_loop_wraps() -> void:
	var p := _path_with(3, true)
	var pb := PatrolBehavior.new()
	pb._index = 0
	pb._advance(p)
	assert_eq(pb._index, 1, "0 -> 1")
	pb._advance(p)
	pb._advance(p)  # 1 -> 2 -> 0 (wrap)
	assert_eq(pb._index, 0, "wraps to the start on loop")
	pb.free()
	p.free()

func test_pingpong_bounces() -> void:
	var p := _path_with(3, false)  # no loop -> ping-pong
	var pb := PatrolBehavior.new()
	pb._index = 0
	pb._advance(p)  # 0 -> 1
	pb._advance(p)  # 1 -> 2
	assert_eq(pb._index, 2, "reaches the far end")
	pb._advance(p)  # 2 -> 1 (bounce)
	assert_eq(pb._index, 1, "bounces back from the end")
	pb._advance(p)  # 1 -> 0
	pb._advance(p)  # 0 -> 1 (bounce off the start)
	assert_eq(pb._index, 1, "bounces off the start")
	pb.free()
	p.free()

func test_is_active_gating() -> void:
	var pb := PatrolBehavior.new()
	assert_false(pb.is_active(), "no path -> inactive")
	var p := _path_with(2, true)
	pb.add_child(p)
	pb.patrol_path = pb.get_path_to(p)
	assert_true(pb.is_active(), "enabled + a path with waypoints -> active")
	pb.enabled = false
	assert_false(pb.is_active(), "disabled -> inactive")
	pb.free()  # frees the child path too
