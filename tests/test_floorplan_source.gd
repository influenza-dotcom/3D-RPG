extends GutTest

## FloorplanSource — the minimap's wall layer: level colliders in, world-space solids out, cut to
## draw_multiline pairs at any height. The tree walk is the impure half of the section cut, and it has two
## failure modes that are INVISIBLE in play rather than loud:
##   - a character body slipping through the static gate freezes an NPC into the map as a wall blob;
##   - a CSG blockout level finding nothing at all, while the brush level next door looks perfect.
## Both are pinned below.

const FS := preload("res://scripts/ui/floorplan_section.gd")
const SRC := preload("res://scripts/ui/floorplan_source.gd")


func _box_body(body: CollisionObject3D, size: Vector3, pos: Vector3) -> CollisionObject3D:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	return body


# --- the static gate ------------------------------------------------------------------------------------

## THE ONE THAT MATTERS. Player.tscn and enemy.tscn are BOTH collision_layer 2 — the same layer as level
## ground — so no physics mask can separate characters from geometry in this project. The gate is the TYPE,
## and if it ever regresses to a layer check, every NPC standing in a room is baked into the deck cache as a
## wall that never moves.
func test_gather_skips_a_character_body() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var ch := CharacterBody3D.new()
	ch.collision_layer = 2
	root.add_child(_box_body(ch, Vector3.ONE, Vector3.ZERO))
	var s = SRC.new()
	s.gather(root, &"")
	assert_eq(s.solid_count(), 0, "a CharacterBody3D is never wall geometry, whatever layer it is on")

func test_gather_takes_a_static_body_on_the_same_layer() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var sb := StaticBody3D.new()
	sb.collision_layer = 2  # deliberately the SAME layer as the character above
	root.add_child(_box_body(sb, Vector3.ONE, Vector3.ZERO))
	var s = SRC.new()
	s.gather(root, &"")
	assert_eq(s.solid_count(), 1, "a StaticBody3D IS wall geometry, on the very layer a mask could not filter")

## AnimatableBody3D INHERITS StaticBody3D (verified against the engine), so the obvious `is StaticBody3D`
## gate silently includes door leaves — and a door baked in whatever pose it held draws shut forever.
func test_gather_excludes_animatable_bodies_such_as_doors() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var door := AnimatableBody3D.new()
	root.add_child(_box_body(door, Vector3(1, 2, 0.2), Vector3.ZERO))
	assert_true(door is StaticBody3D, "AnimatableBody3D really does inherit StaticBody3D — hence the exclusion")
	var s = SRC.new()
	s.gather(root, &"")
	assert_eq(s.solid_count(), 0, "floorplans draw openings, not door leaves")

func test_gather_skips_disabled_shapes() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var sb := StaticBody3D.new()
	root.add_child(_box_body(sb, Vector3.ONE, Vector3.ZERO))
	(sb.get_child(0) as CollisionShape3D).disabled = true
	var s = SRC.new()
	s.gather(root, &"")
	assert_eq(s.solid_count(), 0, "a disabled collider is not solid matter")

## The MinimapHide contract: the whole subtree under a hidden node is skipped.
func test_gather_skips_a_hidden_subtree() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var fence := Node3D.new()
	fence.add_to_group(Groups.MINIMAP_HIDE)
	root.add_child(fence)
	var sb := StaticBody3D.new()
	fence.add_child(_box_body(sb, Vector3.ONE, Vector3.ZERO))
	var s = SRC.new()
	s.gather(root, Groups.MINIMAP_HIDE)
	assert_eq(s.solid_count(), 0, "everything under a MinimapHide prop is skipped")
	s.gather(root, &"")
	assert_eq(s.solid_count(), 1, "...and taken again when the group is not being honoured")

func test_gather_of_a_null_root_is_empty_and_quiet() -> void:
	var s = SRC.new()
	s.gather(null, &"")
	assert_eq(s.solid_count(), 0, "no level yet is a normal state, not an error")
	assert_eq(s.slice(0.0, 120.0, 0.35).size(), 0, "and slicing nothing yields nothing")


# --- shape_solid dispatch -------------------------------------------------------------------------------

func test_shape_solid_returns_hulls_for_convex_kinds() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	assert_true(SRC.shape_solid(box, Transform3D.IDENTITY).has("hull"), "box -> hull")
	var cyl := CylinderShape3D.new()
	assert_true(SRC.shape_solid(cyl, Transform3D.IDENTITY).has("hull"), "cylinder -> hull")
	var cap := CapsuleShape3D.new()
	assert_true(SRC.shape_solid(cap, Transform3D.IDENTITY).has("hull"), "capsule -> hull")
	var sph := SphereShape3D.new()
	assert_true(SRC.shape_solid(sph, Transform3D.IDENTITY).has("hull"), "sphere -> hull")
	box = null
	cyl = null
	cap = null
	sph = null

func test_shape_solid_concave_returns_faces() -> void:
	var tri := ConcavePolygonShape3D.new()
	tri.set_faces(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0)]))
	assert_true(SRC.shape_solid(tri, Transform3D.IDENTITY).has("faces"), "trimesh -> face soup, not a hull")
	tri = null

## An infinite plane would cut ONE segment straight across the whole map; a heightfield is terrain.
func test_shape_solid_skips_unboundable_shapes() -> void:
	var wb := WorldBoundaryShape3D.new()
	assert_true(SRC.shape_solid(wb, Transform3D.IDENTITY).is_empty(), "WorldBoundary is skipped")
	wb = null
	var empty_convex := ConvexPolygonShape3D.new()
	assert_true(SRC.shape_solid(empty_convex, Transform3D.IDENTITY).is_empty(), "a point-less convex is skipped")
	empty_convex = null


# --- slicing --------------------------------------------------------------------------------------------

func test_slice_of_two_boxes_yields_two_rings() -> void:
	# Hand-built solids: no tree, no navmesh — the CUT is under test here, not the walk.
	var s = SRC.new()
	# Typed local, not a bare literal: Array[Dictionary] refuses an untyped Array on assignment.
	var solids: Array[Dictionary] = [
		{"hull": FS.box_points(Vector3(2, 3, 2), Transform3D.IDENTITY)},
		{"hull": FS.box_points(Vector3(2, 3, 2), Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))},
	]
	s.solids = solids
	var segs := s.slice(0.0, 120.0, 0.01)
	assert_eq(segs.size(), 16, "two 4-sided rings = 8 edges = 16 flat points")
	assert_eq(segs.size() % 2, 0, "draw_multiline needs whole pairs")

func test_slice_skips_solids_that_do_not_reach_the_cut() -> void:
	var s = SRC.new()
	var solids: Array[Dictionary] = [{"hull": FS.box_points(Vector3(2, 1, 2), Transform3D.IDENTITY)}]
	s.solids = solids
	assert_eq(s.slice(50.0, 120.0, 0.01).size(), 0, "a knee-high crate is not cut at chest height")
	assert_gt(s.slice(0.0, 120.0, 0.01).size(), 0, "...but it is cut through its own middle")

func test_slice_rejects_the_void_seal_and_the_speckle() -> void:
	var s = SRC.new()
	var solids: Array[Dictionary] = [
		{"hull": FS.box_points(Vector3(500, 10, 500), Transform3D.IDENTITY)},   # a worldspawn shell
		{"hull": FS.box_points(Vector3(0.1, 2, 0.1), Transform3D.IDENTITY)},    # a pipe collar
		{"hull": FS.box_points(Vector3(4, 3, 0.2), Transform3D.IDENTITY)},      # a real wall: thin but LONG
	]
	s.solids = solids
	var segs := s.slice(0.0, 120.0, 0.35)
	assert_eq(segs.size(), 8, "only the real wall survives — one 4-edge ring")


# --- the pure cut maths (FloorplanSection's half) -------------------------------------------------------

func test_slice_hull_unit_cube_is_the_unit_square() -> void:
	var ring := FS.slice_hull(FS.box_points(Vector3.ONE, Transform3D.IDENTITY), 0.0)
	var b := FS.ring_bounds(ring)
	assert_almost_eq(b.position.x, -0.5, 0.001, "cut spans the box in X")
	assert_almost_eq(b.position.y, -0.5, 0.001, "...and in Z")
	assert_almost_eq(b.size.x, 1.0, 0.001, "unit width")
	assert_almost_eq(b.size.y, 1.0, 0.001, "unit depth")

func test_slice_hull_above_and_below_is_empty() -> void:
	var pts := FS.box_points(Vector3.ONE, Transform3D.IDENTITY)
	assert_eq(FS.slice_hull(pts, 5.0).size(), 0, "nothing to cut above the solid — the multi-storey filter")
	assert_eq(FS.slice_hull(pts, -5.0).size(), 0, "nor below it")

## Makes the all-pairs-is-a-superset argument executable: a point INSIDE the body contributes crossings, and
## every one of them must land inside the hull the surface points already describe.
func test_slice_hull_ignores_interior_points() -> void:
	var pts := FS.box_points(Vector3.ONE, Transform3D.IDENTITY)
	var clean := FS.ring_bounds(FS.slice_hull(pts, 0.0))
	pts.append(Vector3(0.1, 0.2, -0.1))
	var dirty := FS.ring_bounds(FS.slice_hull(pts, 0.0))
	assert_almost_eq(dirty.size.x, clean.size.x, 0.001, "an interior point cannot widen the cross-section")
	assert_almost_eq(dirty.size.y, clean.size.y, 0.001, "...on either axis")

func test_slice_hull_rotated_box_is_a_diamond() -> void:
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO)
	var b := FS.ring_bounds(FS.slice_hull(FS.box_points(Vector3.ONE, xf), 0.0))
	assert_almost_eq(b.size.x, sqrt(2.0), 0.01, "a 45deg unit square measures sqrt(2) across")
	assert_almost_eq(b.size.y, sqrt(2.0), 0.01, "...on both axes")

func test_slice_faces_one_segment_per_straddling_triangle() -> void:
	var faces := PackedVector3Array([
		Vector3(0, -1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1),      # straddles y = 0
		Vector3(0, 5, 0), Vector3(1, 6, 0), Vector3(0, 6, 1),       # entirely above
	])
	assert_eq(FS.slice_faces(faces, 0.0).size(), 2, "one straddling triangle -> one segment (2 points)")

func test_ring_edges_drops_the_closing_duplicate() -> void:
	# Godot's convex_hull repeats the first point; without dropping it every solid emits a doubled edge.
	var square := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)])
	assert_eq(FS.ring_edges(square).size(), 8, "4 corners -> 4 edges -> 8 flat points, not 10")

func test_ring_edges_degenerate_is_empty() -> void:
	assert_eq(FS.ring_edges(PackedVector2Array()).size(), 0, "no ring, no edges")
	assert_eq(FS.ring_edges(PackedVector2Array([Vector2.ZERO])).size(), 0, "a single point is not an edge")

func test_ring_rejects_need_BOTH_axes() -> void:
	# A long thin wall must survive both filters — rejecting on one axis would delete every wall in the level.
	var wall := PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 0.2), Vector2(0, 0.2)])
	assert_false(FS.ring_is_shell(wall, 30.0), "a long wall is not a void seal")
	assert_false(FS.ring_is_noise(wall, 0.35), "a long wall is not speckle either")
	var shell := PackedVector2Array([Vector2(0, 0), Vector2(500, 0), Vector2(500, 500), Vector2(0, 500)])
	assert_true(FS.ring_is_shell(shell, 120.0), "a map-enclosing brush IS a void seal")
	var speck := PackedVector2Array([Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, 0.1), Vector2(0, 0.1)])
	assert_true(FS.ring_is_noise(speck, 0.35), "a pipe collar IS speckle")
