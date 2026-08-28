extends GutTest

## See-through geometry — the rule that lets an NPC spot you through a chain-link fence AND lets both of you
## shoot through it, while the fence stays solid to walk into. Four surfaces are pinned here:
##
##   * `SightRay.is_see_through_hit` (pure) — the MARKING CONTRACT. One channel: the COLLIDER is in
##     `Groups.SEE_THROUGH`. Whole bodies only, because a flying round collides with a BODY and there is no
##     per-shape collision exception — which is the whole reason `SeeThroughBrushes` splits rather than tags.
##   * `SeeThroughBrushes.hull_is_see_through` + `build_grid` (pure) — the GEOMETRY RULE that decides which
##     brushes are fences: every corner of the brush hull must land on a vertex of a transparent-material
##     surface. The "every corner" part is what keeps a wall sharing an edge with a fence opaque.
##   * The SPLIT itself, in a live tree — the fence brushes must end up in their own tagged `StaticBody3D`
##     carrying the source body's collision layer/mask, and the source body must keep everything else.
##   * `Perception.can_see()` through a real marked body, in a real physics space — borrowing
##     `tests/test_held_prop_los.gd`'s harness (the other "what may block sight" pin).
##
## NOT covered here: `SeeThroughBrushes` reading materials off a real func_godot map (that needs the built level
## scene — verified against `alive.map` at implementation time: 17 brushes, the 13 `fence1_a` panels plus the 4
## `tree` solids, and re-checkable any time with the component's `verbose` knob), and the two FIRE paths, which
## need a wielder and a weapon: `DamageTrace.run_pellet`'s pass-through and
## `Projectile._pass_see_through_geometry` are playtest-verified, per the "don't run an actor's `_ready` in a
## unit test" convention.

const CELL := 0.05  ## SeeThroughBrushes.vertex_tolerance's default, in metres


# --- SightRay.is_see_through_hit: the marking contract -------------------------------------------------------

func test_unmarked_collider_is_opaque() -> void:
	var body := StaticBody3D.new()
	assert_false(SightRay.is_see_through_hit({"collider": body, "shape": 0}),
		"an ordinary wall body blocks sight and gunfire")
	body.free()

func test_body_in_group_is_see_through() -> void:
	var body := StaticBody3D.new()
	body.add_to_group(Groups.SEE_THROUGH)
	assert_true(SightRay.is_see_through_hit({"collider": body, "shape": 3}),
		"a body tagged by the SeeThrough drop-in is see-through whatever shape was hit")
	body.free()

func test_a_malformed_or_empty_hit_fails_closed() -> void:
	# "Solid" must always be the fallback answer: a bug that makes fences of everything is far worse than one
	# that leaves a fence opaque.
	assert_false(SightRay.is_see_through_hit({}), "an empty hit is not see-through")
	assert_false(SightRay.is_see_through_hit({"collider": null}), "a null collider is not see-through")


# --- SeeThroughBrushes: which brushes count as fence ---------------------------------------------------------

## Corner points of an axis-aligned box, the shape every TrenchBroom fence panel actually is.
func _box_corners(box: AABB) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 8:
		pts.append(box.get_endpoint(i))
	return pts

func test_hull_whose_corners_are_all_fence_vertices_is_see_through() -> void:
	var fence := AABB(Vector3(-2, 0, -2), Vector3(4, 3, 0.2))
	var grid := SeeThroughBrushes.build_grid(_box_corners(fence), CELL)
	assert_true(SeeThroughBrushes.hull_is_see_through(_box_corners(fence), grid, CELL),
		"the fence brush's own corners match the fence surface it is drawn with")

func test_neighbouring_wall_sharing_an_edge_stays_opaque() -> void:
	# The failure this rule exists to prevent: a concrete brush butted against the fence shares two corners.
	# Requiring EVERY corner to match keeps it solid.
	var fence := AABB(Vector3(-2, 0, -2), Vector3(4, 3, 0.2))
	var wall := AABB(Vector3(2, 0, -2), Vector3(2, 3, 0.2))  # starts exactly where the fence ends
	var grid := SeeThroughBrushes.build_grid(_box_corners(fence), CELL)
	assert_false(SeeThroughBrushes.hull_is_see_through(_box_corners(wall), grid, CELL),
		"a wall that only touches the fence is not itself see-through")

func test_corner_within_tolerance_still_matches() -> void:
	# func_godot re-derives face vertices from the brush planes, so a corner can land a thousandth off the
	# collision hull it came from (observed on the map's foliage brushes). The tolerance is what recovers them.
	var fence := AABB(Vector3(-2, 0, -2), Vector3(4, 3, 0.2))
	var grid := SeeThroughBrushes.build_grid(_box_corners(fence), CELL)
	var nudged := PackedVector3Array()
	for p: Vector3 in _box_corners(fence):
		nudged.append(p + Vector3(0.001, -0.001, 0.001))
	assert_true(SeeThroughBrushes.hull_is_see_through(nudged, grid, CELL),
		"float noise well under the tolerance does not lose a fence brush")

func test_corner_far_off_does_not_match() -> void:
	var fence := AABB(Vector3(-2, 0, -2), Vector3(4, 3, 0.2))
	var grid := SeeThroughBrushes.build_grid(_box_corners(fence), CELL)
	var moved := PackedVector3Array()
	for p: Vector3 in _box_corners(fence):
		moved.append(p + Vector3(0.5, 0.0, 0.0))
	assert_false(SeeThroughBrushes.hull_is_see_through(moved, grid, CELL),
		"half a metre off is a different brush, tolerance or not")

func test_degenerate_hull_is_never_see_through() -> void:
	var fence := AABB(Vector3(-2, 0, -2), Vector3(4, 3, 0.2))
	var grid := SeeThroughBrushes.build_grid(_box_corners(fence), CELL)
	var sliver := PackedVector3Array([fence.position, fence.position + Vector3(0.1, 0, 0)])
	assert_false(SeeThroughBrushes.hull_is_see_through(sliver, grid, CELL),
		"a two-point hull is not a solid and must not be treated as a fence")


# --- the designer override lists -------------------------------------------------------------------------

func test_surface_name_matching_accepts_bare_and_qualified_names() -> void:
	# A designer types what TrenchBroom shows ("fence2"); func_godot names the surface "textures/fence2".
	var list := PackedStringArray(["fence2", "textures/window5"])
	assert_true(SeeThroughBrushes._name_listed("textures/fence2", list), "bare texture name matches")
	assert_true(SeeThroughBrushes._name_listed("textures/window5", list), "fully qualified name matches")
	assert_true(SeeThroughBrushes._name_listed("TEXTURES/FENCE2", list), "matching is case-insensitive")
	assert_false(SeeThroughBrushes._name_listed("textures/fence1_a", list), "an unlisted texture does not match")
	assert_false(SeeThroughBrushes._name_listed("", list), "an unnamed surface never matches a list")


# --- In-tree: the split, and a real Perception ray through a real marked body --------------------------------
#
# Harness shared with tests/test_held_prop_los.gd: a Perception on a CharacterBody3D at the origin facing +Z, a
# target 2 m ahead at eye height, and bodies interposed between them.

var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


## A Perception parented to a (shapeless) CharacterBody3D, mirroring a real NPC: front is +Z (the model
## convention can_see uses) and get_parent() is a CollisionObject3D, matching how perception.gd self-excludes.
func _make_perception() -> Perception:
	var host := CharacterBody3D.new()
	host.collision_layer = 2
	host.collision_mask = 0
	_root.add_child(host)
	host.global_transform = Transform3D.IDENTITY
	var p := Perception.new()
	host.add_child(p)
	p.transform = Transform3D.IDENTITY
	return p


## A solid 0.6 m box body at `pos` on `layer`, sized to span the horizontal sight ray at eye height.
func _make_body(pos: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.add_child(_box_shape(Vector3.ZERO))
	_root.add_child(body)
	body.global_position = pos
	return body


func _box_shape(local_offset: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	shape.position = local_offset
	return shape


func test_a_see_through_body_does_not_block_perception() -> void:
	var p := _make_perception()
	var target := _make_body(Vector3(0, p.eye_height, 2), 2)
	p.target = target
	var fence := _make_body(Vector3(0, p.eye_height, 1), 1)  # a real world-layer solid, dead in the way
	fence.add_to_group(Groups.SEE_THROUGH)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(p.can_see(), "a tagged fence between eye and target must not hide the target")


func test_a_wall_behind_the_fence_still_blocks() -> void:
	# The pass-through must resume the ray, not abandon it: the second solid is the real answer.
	var p := _make_perception()
	var target := _make_body(Vector3(0, p.eye_height, 2), 2)
	p.target = target
	var fence := _make_body(Vector3(0, p.eye_height, 0.8), 1)
	fence.add_to_group(Groups.SEE_THROUGH)
	_make_body(Vector3(0, p.eye_height, 1.4), 1)  # untagged concrete just past it
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(p.can_see(), "sight passes the fence and is then stopped by the wall behind it")


# --- The split: fence brushes must leave the shared body for one of their own -------------------------------

## A func_godot-shaped body: one MeshInstance3D whose surfaces name their textures, plus one convex hull per
## brush built from the SAME corner points those surfaces use — which is exactly the relationship func_godot
## produces between a brush's faces and its collision shape, and what the "every corner" rule keys on.
func _make_map_body(boxes: Array, names: Array, transparent: Array) -> StaticBody3D:
	var mesh := ArrayMesh.new()
	for i in boxes.size():
		var material := StandardMaterial3D.new()
		if transparent[i]:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _box_corners(boxes[i])
		var indices := PackedInt32Array()
		for c in range(2, 8):
			indices.append_array([0, c - 1, c])  # a degenerate fan: only ARRAY_VERTEX is ever read back
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(i, names[i])
		mesh.surface_set_material(i, material)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	for box: AABB in boxes:
		var shape := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		hull.points = _box_corners(box)
		shape.shape = hull
		body.add_child(shape)
	_root.add_child(body)
	body.global_transform = Transform3D.IDENTITY
	return body


## The one see-through body under the harness root, or null. Found by GROUP rather than by name: the name is a
## debug convenience, the group membership IS the contract every consumer reads.
func _tagged_body() -> StaticBody3D:
	for node in get_tree().get_nodes_in_group(Groups.SEE_THROUGH):
		var body := node as StaticBody3D
		if body != null and _root.is_ancestor_of(body):
			return body
	return null


func test_transparent_brushes_are_split_into_their_own_tagged_body() -> void:
	var fence := AABB(Vector3(-2, 0, -2), Vector3(4, 3, 0.2))
	var wall := AABB(Vector3(-2, 0, -6), Vector3(4, 3, 1.0))
	var body := _make_map_body([fence, wall], ["textures/fence1_a", "textures/concrete1"], [true, false])
	var component := SeeThroughBrushes.new()
	_root.add_child(component)  # its parent is _root, so it scans the body beside it
	await get_tree().physics_frame

	assert_false(body.is_in_group(Groups.SEE_THROUGH),
		"the shared map body must NOT be tagged — that would make the whole level see-through")
	var split := _tagged_body()
	assert_not_null(split, "the fence brush is moved into its own sibling StaticBody3D")
	if split == null:
		return
	assert_ne(split, body, "the split body is a NEW body, not the shared map body re-tagged")
	assert_eq(split.get_parent(), body.get_parent(), "it is a SIBLING of the body it came from")
	assert_eq(split.get_shape_owners().size(), 1, "exactly the one transparent brush moved across")
	assert_eq(body.get_shape_owners().size(), 1, "the opaque brush stayed on the original body")
	# The fence must remain exactly as SOLID as it was — the split changes who consults it, never its physics.
	assert_eq(split.collision_layer, body.collision_layer, "the split body inherits the source collision layer")
	assert_eq(split.collision_mask, body.collision_mask, "the split body inherits the source collision mask")


func test_a_fully_transparent_body_is_tagged_in_place() -> void:
	# A fence authored as its own func_godot entity has nothing to split off — the body IS the fence.
	var fence := AABB(Vector3(-2, 0, -2), Vector3(4, 3, 0.2))
	var body := _make_map_body([fence], ["textures/fence1_a"], [true])
	var component := SeeThroughBrushes.new()
	_root.add_child(component)
	await get_tree().physics_frame

	assert_true(body.is_in_group(Groups.SEE_THROUGH), "an all-fence body is tagged where it stands")
	assert_eq(_tagged_body(), body, "no redundant sibling body is created when there is nothing to leave behind")


func test_opaque_surfaces_override_puts_a_texture_back_to_solid() -> void:
	# The designer knob: "a tree card should still be cover" — and should still stop rounds.
	var canopy := AABB(Vector3(-2, 0, -2), Vector3(4, 3, 0.2))
	var body := _make_map_body([canopy], ["textures/tree"], [true])
	var component := SeeThroughBrushes.new()
	component.opaque_surfaces = PackedStringArray(["tree"])
	_root.add_child(component)
	await get_tree().physics_frame

	assert_false(body.is_in_group(Groups.SEE_THROUGH),
		"a texture listed in opaque_surfaces stays solid despite its transparent material")
	assert_null(_tagged_body(), "and nothing is split off it either — the canopy still stops rounds")
