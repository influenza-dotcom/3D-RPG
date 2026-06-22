extends GutTest

## Pins the pure line-math behind the editor gizmos (gizmo_shapes.gd). No editor / no tree -- just geometry.
## add_lines() format is PAIRS, so every helper must return an EVEN number of finite points.

const Shapes := preload("res://addons/cybersunday_tools/gizmos/gizmo_shapes.gd")


func _all_finite(pts: PackedVector3Array) -> bool:
	for p in pts:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return false
	return true


func test_box_is_12_segments() -> void:
	var b := Shapes.box(Vector3(2, 2, 2))
	assert_eq(b.size(), 24, "a box is 12 edges = 24 line-pair points")
	assert_true(_all_finite(b), "box points finite")


func test_ring_is_even_and_finite() -> void:
	var r := Shapes.ring(3.0, Transform3D.IDENTITY, 16)
	assert_eq(r.size(), 32, "16 segments = 32 pair points")
	assert_true(_all_finite(r))


func test_sphere_even_and_finite() -> void:
	var s := Shapes.sphere(1.5, Transform3D.IDENTITY, 12)
	assert_eq(s.size() % 2, 0, "line list must be pairs")
	assert_gt(s.size(), 0)
	assert_true(_all_finite(s))


func test_polyline_open_vs_closed() -> void:
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 0, 1)])
	var open := Shapes.polyline(pts, false)
	var closed := Shapes.polyline(pts, true)
	assert_eq(open.size(), 4, "3 points open = 2 segments")
	assert_eq(closed.size(), 6, "closed adds the wrap segment")


func test_polyline_too_few_points_is_empty() -> void:
	assert_eq(Shapes.polyline(PackedVector3Array([Vector3.ZERO]), true).size(), 0)


func test_arrow_finite_and_has_head() -> void:
	var a := Shapes.arrow(Vector3.FORWARD, 1.0)
	assert_eq(a.size(), 6, "shaft + 2 head segments")
	assert_true(_all_finite(a))


func test_arrow_zero_dir_is_empty() -> void:
	assert_eq(Shapes.arrow(Vector3.ZERO, 1.0).size(), 0, "no direction -> no arrow")


func test_cone_flat_finite_and_even() -> void:
	var c := Shapes.cone_flat(10.0, deg_to_rad(55.0), Vector3.FORWARD, Transform3D.IDENTITY, 8)
	assert_eq(c.size() % 2, 0, "pairs")
	assert_gt(c.size(), 0)
	assert_true(_all_finite(c), "cone points finite (no NaN from atan2/trig)")


func test_cylinder_finite() -> void:
	var c := Shapes.cylinder(1.0, 3.0, Transform3D.IDENTITY, 12)
	assert_eq(c.size() % 2, 0)
	assert_true(_all_finite(c))


func test_transform_is_baked_in() -> void:
	var offset := Transform3D(Basis(), Vector3(100, 0, 0))
	var r := Shapes.ring(1.0, offset, 8)
	# every point should be shifted ~100 on X
	var ok := true
	for p in r:
		if p.x < 90.0:
			ok = false
			break
	assert_true(ok, "the xform arg should be applied to every emitted point")
