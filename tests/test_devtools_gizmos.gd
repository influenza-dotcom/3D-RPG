extends GutTest

## Pins the pure line-math behind the editor gizmos (gizmo_shapes.gd). No editor / no tree -- just geometry.
## add_lines() format is PAIRS, so every helper must return an EVEN number of finite points.

const Shapes := preload("res://addons/cybersunday_tools/gizmos/gizmo_shapes.gd")
const GizmoEdit := preload("res://addons/cybersunday_tools/gizmos/gizmo_edit.gd")


# --- editable-handle math (gizmo_edit.gd, behind the ExplosiveBarrel.blast_radius drag handle) ---

func test_radius_from_drag_reads_axis_distance() -> void:
	# A ray straight down onto the +X axis at x=5 -> radius 5; the y/z offset of an angled ray is irrelevant to the
	# closest point on the +X axis, so an angled ray crossing x=5 still reads 5.
	assert_almost_eq(GizmoEdit.radius_from_drag(Vector3(5, 10, 0), Vector3(0, -1, 0)), 5.0, 0.001, "perpendicular ray hits the axis at its x")
	assert_almost_eq(GizmoEdit.radius_from_drag(Vector3(5, 10, 10), Vector3(0, -1, -1)), 5.0, 0.001, "angled ray, same axis crossing")


func test_radius_from_drag_parallel_ray_falls_back() -> void:
	# A ray PARALLEL to the axis is degenerate -> fall back to projecting its origin onto the axis (x = 7).
	assert_almost_eq(GizmoEdit.radius_from_drag(Vector3(7, 3, 0), Vector3(1, 0, 0)), 7.0, 0.001, "parallel ray -> project origin onto axis")


func test_clamp_radius_floors_at_min() -> void:
	assert_almost_eq(GizmoEdit.clamp_radius(-2.0), 0.1, 0.0001, "negative clamps to the 0.1 floor")
	assert_almost_eq(GizmoEdit.clamp_radius(3.5), 3.5, 0.0001, "a positive radius passes through")
	assert_almost_eq(GizmoEdit.clamp_radius(0.05, 0.5), 0.5, 0.0001, "respects a custom floor")


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


func test_cross_is_three_segments_and_finite() -> void:
	var c := Shapes.cross(0.5)
	assert_eq(c.size(), 6, "a 3-axis cross is 3 segments = 6 pair points")
	assert_eq(c.size() % 2, 0, "line list must be pairs")
	assert_true(_all_finite(c), "cross points finite")


func test_cross_spans_size_on_each_axis() -> void:
	var s := 2.0
	var c := Shapes.cross(s)
	# spokes run from -s to +s on X, Y, Z -- so the extents must reach +/-s on every axis
	assert_eq(c[0], Vector3(-s, 0, 0), "X spoke negative end")
	assert_eq(c[1], Vector3(s, 0, 0), "X spoke positive end")
	assert_eq(c[2], Vector3(0, -s, 0), "Y spoke negative end")
	assert_eq(c[3], Vector3(0, s, 0), "Y spoke positive end")
	assert_eq(c[4], Vector3(0, 0, -s), "Z spoke negative end")
	assert_eq(c[5], Vector3(0, 0, s), "Z spoke positive end")


func test_cross_transform_is_baked_in() -> void:
	var offset := Transform3D(Basis(), Vector3(0, 50, 0))
	var c := Shapes.cross(1.0, offset)
	var ok := true
	for p in c:
		if p.y < 40.0:
			ok = false
			break
	assert_true(ok, "the xform arg should be applied to every emitted cross point")


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
