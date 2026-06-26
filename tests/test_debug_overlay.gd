extends GutTest

## The runtime DebugOverlay (#10 profiler + #12 graphs): the PURE graph math (push_capped / graph_points) is
## unit-tested; the live sampling + draw are play-verified (they need a running game + renderer). Construct check
## confirms the component compiles off-tree.

const DebugOverlay := preload("res://scripts/components/debug_overlay.gd")


func test_push_capped_keeps_the_last_n() -> void:
	var b := PackedFloat32Array()
	for i in 5:
		b = DebugOverlay.push_capped(b, float(i), 3)
	assert_eq(b.size(), 3, "the rolling window keeps only `cap` samples")
	assert_eq(b[0], 2.0, "oldest kept is the 3rd-from-last")
	assert_eq(b[2], 4.0, "newest is the last pushed")


func test_push_capped_under_cap_keeps_all() -> void:
	var b := PackedFloat32Array()
	b = DebugOverlay.push_capped(b, 1.0, 10)
	b = DebugOverlay.push_capped(b, 2.0, 10)
	assert_eq(b.size(), 2, "below the cap nothing is dropped")


func test_graph_points_maps_range_and_spread() -> void:
	var s := PackedFloat32Array([0.0, 50.0, 100.0])
	var pts := DebugOverlay.graph_points(s, Rect2(0, 0, 100, 10), 0.0, 100.0)
	assert_eq(pts.size(), 3, "one point per sample")
	assert_almost_eq(pts[0].x, 0.0, 0.01, "first sample at the left edge")
	assert_almost_eq(pts[2].x, 100.0, 0.01, "last sample at the right edge")
	assert_almost_eq(pts[0].y, 10.0, 0.01, "value at vmin -> rect bottom")
	assert_almost_eq(pts[2].y, 0.0, 0.01, "value at vmax -> rect top")
	assert_almost_eq(pts[1].y, 5.0, 0.01, "value at the midpoint -> rect middle")


func test_graph_points_clamps_out_of_range() -> void:
	var s := PackedFloat32Array([200.0])  # above vmax
	var pts := DebugOverlay.graph_points(s, Rect2(0, 0, 10, 10), 0.0, 100.0)
	assert_almost_eq(pts[0].y, 0.0, 0.01, "an over-range value clamps to the top, never above the rect")
	assert_eq(DebugOverlay.graph_points(PackedFloat32Array(), Rect2(), 0.0, 1.0).size(), 0, "no samples -> no points")


func test_debug_overlay_constructs() -> void:
	var o = DebugOverlay.new()
	assert_not_null(o, "the overlay compiles + constructs off-tree (no _ready until added to a tree)")
	o.free()
