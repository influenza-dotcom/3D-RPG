extends GutTest

## Pins the NEW pure line-math added for the GIZMOS-v2 batch (gizmo_shapes.gd::arc, the Door swing arc). No editor /
## no tree -- just geometry. add_lines() format is PAIRS, so every helper must return an EVEN number of finite points.
## The link-line / falloff-sphere / spawn-ring draws all reuse existing helpers (already pinned in
## test_devtools_gizmos.gd) and the link math lives in the editor-glue plugin (not unit-testable headless).

const Shapes := preload("res://addons/cybersunday_tools/gizmos/gizmo_shapes.gd")


func _all_finite(pts: PackedVector3Array) -> bool:
	for p in pts:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return false
	return true


func test_arc_is_even_and_finite() -> void:
	var a := Shapes.arc(1.0, 0.0, deg_to_rad(90.0), Transform3D.IDENTITY, 8)
	assert_eq(a.size() % 2, 0, "line list must be pairs")
	assert_gt(a.size(), 0, "arc emits segments")
	assert_true(_all_finite(a), "arc points finite (no NaN from trig)")


func test_arc_segment_count() -> void:
	# 2 bounding radii (4 points) + `segments` curved-edge segments (2 points each).
	var segs := 12
	var a := Shapes.arc(2.0, 0.0, deg_to_rad(90.0), Transform3D.IDENTITY, segs)
	assert_eq(a.size(), 4 + segs * 2, "two radii + one segment per arc division")


func test_arc_zero_start_points_along_plus_z() -> void:
	# atan2(x, z) convention: angle 0 -> +Z. The first bounding radius runs origin -> (0,0,radius).
	var r := 3.0
	var a := Shapes.arc(r, 0.0, deg_to_rad(45.0))
	assert_almost_eq(a[0], Vector3.ZERO, Vector3(0.001, 0.001, 0.001), "first radius starts at the pivot origin")
	assert_almost_eq(a[1], Vector3(0.0, 0.0, r), Vector3(0.001, 0.001, 0.001), "closed edge points to +Z at angle 0")


func test_arc_sweep_endpoint_is_at_sweep_angle() -> void:
	# The second bounding radius (a[3]) is origin -> the swept end point at start+sweep.
	var r := 2.0
	var sweep := deg_to_rad(90.0)
	var a := Shapes.arc(r, 0.0, sweep)
	var expected := Vector3(sin(sweep), 0.0, cos(sweep)) * r  # 90deg -> ~(r, 0, 0)
	assert_almost_eq(a[3], expected, Vector3(0.001, 0.001, 0.001), "open edge points to the swept angle")


func test_arc_negative_sweep_goes_the_other_way() -> void:
	# A negative open_angle (door swings the other way) sweeps to -X instead of +X.
	var r := 2.0
	var a := Shapes.arc(r, 0.0, deg_to_rad(-90.0))
	assert_lt(a[3].x, 0.0, "a negative sweep places the open edge on the -X side")
	assert_true(_all_finite(a), "negative-sweep arc still finite")


func test_arc_radius_is_constant_along_curve() -> void:
	# Every point on the curved edge sits on the circle of `radius` around the (XZ) origin.
	var r := 4.0
	var a := Shapes.arc(r, deg_to_rad(20.0), deg_to_rad(70.0), Transform3D.IDENTITY, 10)
	var ok := true
	for i in range(4, a.size()):  # skip the two bounding radii (which include the origin)
		var p := a[i]
		if absf(Vector2(p.x, p.z).length() - r) > 0.01:
			ok = false
			break
	assert_true(ok, "curved-edge points all lie on the radius-r circle")


func test_arc_transform_is_baked_in() -> void:
	# Mirrors test_transform_is_baked_in: the pivot offset (a door's pivot position) shifts every point.
	var offset := Transform3D(Basis(), Vector3(0.0, 0.0, 100.0))
	var a := Shapes.arc(1.0, 0.0, deg_to_rad(90.0), offset, 8)
	var ok := true
	for p in a:
		if p.z < 90.0:
			ok = false
			break
	assert_true(ok, "the xform arg should be applied to every emitted arc point")


func test_arc_min_one_segment() -> void:
	# A zero/negative segments arg is clamped to 1 (no empty/degenerate curve), still finite + even.
	var a := Shapes.arc(1.0, 0.0, deg_to_rad(90.0), Transform3D.IDENTITY, 0)
	assert_eq(a.size(), 4 + 1 * 2, "segments clamped to a minimum of 1")
	assert_true(_all_finite(a))
