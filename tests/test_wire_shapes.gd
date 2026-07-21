extends GutTest

## WireShapes — pure line-segment generators for runtime debug drawing. All off-tree (no node/tree), so we assert
## the segment counts (PAIR format: point count is always even) and that the `x` transform is baked into the points.

func test_box_has_twelve_edges() -> void:
	var b := WireShapes.box(Vector3.ONE)
	assert_eq(b.size(), 24, "12 box edges * 2 endpoints = 24 points")

func test_box_bakes_the_transform() -> void:
	# A box translated +10 on X: symmetric points, so their mean sits at the translated centre.
	var b := WireShapes.box(Vector3(2, 2, 2), Transform3D(Basis(), Vector3(10, 0, 0)))
	var sum := Vector3.ZERO
	for p in b:
		sum += p
	var mean := sum / float(b.size())
	assert_almost_eq(mean.x, 10.0, 0.001, "transform is baked into every vertex")

func test_ring_segments_and_degenerate() -> void:
	assert_eq(WireShapes.ring(1.0).size(), 64, "32 ring segments * 2 = 64 points")
	assert_eq(WireShapes.ring(0.0).size(), 0, "a zero-radius ring draws nothing")

func test_cone_flat_counts_and_degenerate() -> void:
	# 2 edge rays (2 pairs = 4 pts) + a 20-segment far arc (40 pts) = 44.
	var c := WireShapes.cone_flat(5.0, deg_to_rad(55.0), Vector3.BACK)
	assert_eq(c.size(), 44, "two edge rays + the far arc")
	assert_eq(WireShapes.cone_flat(0.0, deg_to_rad(55.0), Vector3.BACK).size(), 0, "zero range -> no cone")

func test_shape_lines_dispatches_and_skips_unsupported() -> void:
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE
	assert_eq(WireShapes.shape_lines(box_shape).size(), 24, "BoxShape3D -> box wire")
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 1.0
	assert_gt(WireShapes.shape_lines(sphere_shape).size(), 0, "SphereShape3D -> sphere wire")
	# An unsupported shape (no wire recipe) returns empty so the caller can safely skip it.
	assert_eq(WireShapes.shape_lines(ConcavePolygonShape3D.new()).size(), 0, "unsupported shape -> empty")
	box_shape = null
	sphere_shape = null

func test_all_generators_emit_pairs() -> void:
	# Every generator must emit whole segments (an even point count) for PRIMITIVE_LINES.
	for pts in [
		WireShapes.box(Vector3.ONE),
		WireShapes.ring(1.0),
		WireShapes.sphere(1.0),
		WireShapes.cylinder(1.0, 2.0),
		WireShapes.capsule(0.5, 2.0),
		WireShapes.cone_flat(3.0, 0.5, Vector3.BACK),
	]:
		assert_eq(pts.size() % 2, 0, "line points come in pairs")
