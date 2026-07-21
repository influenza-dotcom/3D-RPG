extends GutTest

## AiDebugDraw — the immediate-mode line + billboard-label surface. In-tree (it builds a MeshInstance3D/ImmediateMesh
## in _ready and pools Label3D children), so we add_child_autofree it and exercise the frame lifecycle: an empty
## frame emits no surface, a frame with segments emits one, and labels are pooled + hidden when not reused.

func _make() -> AiDebugDraw:
	var d := AiDebugDraw.new()
	add_child_autofree(d)
	return d

func test_empty_frame_emits_no_surface() -> void:
	var d := _make()
	d.begin()
	d.end()
	assert_eq(d._mesh.get_surface_count(), 0, "no segments -> no (empty) mesh surface")

func test_segments_flush_into_one_surface() -> void:
	var d := _make()
	d.begin()
	d.add_lines(PackedVector3Array([Vector3.ZERO, Vector3.ONE]), Color.RED)
	d.end()
	assert_eq(d._mesh.get_surface_count(), 1, "buffered segments flush into a single PRIMITIVE_LINES surface")

func test_add_lines_drops_a_dangling_vertex() -> void:
	var d := _make()
	d.begin()
	# Three points = one full segment + a dangling vertex; the odd one is dropped (no half-segment).
	d.add_lines(PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3.UP]), Color.WHITE)
	assert_eq(d._verts.size(), 2, "odd trailing vertex is dropped")
	d.end()

func test_labels_pool_and_hide_when_unused() -> void:
	var d := _make()
	d.begin()
	d.add_label(Vector3.ZERO, "a")
	d.add_label(Vector3.UP, "b")
	d.end()
	assert_eq(d._labels.size(), 2, "two labels claimed -> pool holds two")
	assert_true(d._labels[0].visible and d._labels[1].visible, "both claimed labels are visible")
	# Next frame claims only one; the second must be hidden (kept in the pool, not freed).
	d.begin()
	d.add_label(Vector3.ZERO, "a")
	d.end()
	assert_eq(d._labels.size(), 2, "pool is reused, not regrown")
	assert_true(d._labels[0].visible, "the reused label stays visible")
	assert_false(d._labels[1].visible, "the un-reused label is hidden")

func test_through_walls_setter_restamps_material() -> void:
	var d := _make()
	d.draw_through_walls = false
	assert_false(d._mat.no_depth_test, "toggling draw_through_walls re-stamps the line material")
	d.draw_through_walls = true
	assert_true(d._mat.no_depth_test, "and back on")
