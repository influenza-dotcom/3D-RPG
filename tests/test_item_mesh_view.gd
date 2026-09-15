extends GutTest

## ItemMeshView (scripts/ui/item_mesh_view.gd) — the live 3D mesh inside an inventory tile. Two seams matter to
## the rest of the UI and are exercised here:
##   • the STATIC model pick (model_resource_for / has_mesh) that grid_tile.gd gates on — a weapon shows its
##     view_model (unless first-person-only, which is not a thing you can picture in a tile), anything else its
##     world_model, and a null answer means "draw the category glyph instead";
##   • the STATIC measure_aabb that BOTH this tile and the icon baker and the character preview frame with —
##     geometry only, in the root's local space, particles excluded, merged across children. In-tree (it reads
##     global_transform), so the rigs live under a bare Node3D added with add_child_autofree.
## Headless has no renderer: _ready deliberately skips the SubViewport rig, so the instance tests pin that
## contract too (show_item is a silent no-op, _frame returns early) — never a rendered pixel.

const ItemMeshView = preload("res://scripts/ui/item_mesh_view.gd")


# --- Fixtures ------------------------------------------------------------------------------------------------

func _box(size: Vector3, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	return mi

func _root() -> Node3D:
	var n := Node3D.new()
	add_child_autofree(n)
	return n

func _assert_aabb(a: AABB, pos: Vector3, size: Vector3, why: String) -> void:
	assert_true(a.position.is_equal_approx(pos), "%s — position %s, expected %s" % [why, a.position, pos])
	assert_true(a.size.is_equal_approx(size), "%s — size %s, expected %s" % [why, a.size, size])


# --- The model pick ------------------------------------------------------------------------------------------

func test_null_item_has_no_model() -> void:
	assert_null(ItemMeshView.model_resource_for(null), "null item -> null model")
	assert_false(ItemMeshView.has_mesh(null), "null item -> no mesh (the tile draws a glyph)")

func test_plain_item_uses_its_world_model() -> void:
	var it := Item.new()
	it.category = Item.Category.MISC
	var m := BoxMesh.new()
	it.world_model = m
	assert_eq(ItemMeshView.model_resource_for(it), m, "a non-weapon shows its world_model")
	assert_true(ItemMeshView.has_mesh(it), "a world_model counts as a mesh")
	it = null

func test_item_with_no_models_has_no_mesh() -> void:
	var it := Item.new()
	it.category = Item.Category.MISC
	assert_null(ItemMeshView.model_resource_for(it), "no world_model, no weapon -> nothing to render")
	assert_false(ItemMeshView.has_mesh(it), "the tile falls through to the category glyph")
	it = null

func test_weapon_prefers_its_view_model_over_its_world_model() -> void:
	var it := Item.new()
	it.category = Item.Category.WEAPON
	it.weapon = WeaponData.new()
	var vm := PackedScene.new()
	it.weapon.view_model = vm
	it.world_model = BoxMesh.new()
	assert_eq(ItemMeshView.model_resource_for(it), vm, "a weapon pictures its held view_model, not the drop model")
	it = null

func test_first_person_only_view_model_falls_back_to_the_world_model() -> void:
	# The bare-hands rig is FP-only: held_view_model() reports null, so the tile shows the world_model (or glyph).
	var it := Item.new()
	it.category = Item.Category.WEAPON
	it.weapon = WeaponData.new()
	it.weapon.view_model = PackedScene.new()
	it.weapon.view_model_is_first_person_only = true
	var wm := BoxMesh.new()
	it.world_model = wm
	assert_eq(ItemMeshView.model_resource_for(it), wm, "an FP-only view_model is not picturable — use the world_model")
	it.world_model = null
	assert_false(ItemMeshView.has_mesh(it), "with no world_model either, the tile draws the glyph")
	it = null

func test_weapon_without_a_view_model_uses_its_world_model() -> void:
	var it := Item.new()
	it.category = Item.Category.WEAPON
	it.weapon = WeaponData.new()
	var wm := BoxMesh.new()
	it.world_model = wm
	assert_eq(ItemMeshView.model_resource_for(it), wm, "no view_model authored -> the world_model")
	it = null

func test_weapon_data_on_a_non_weapon_category_is_ignored() -> void:
	# is_weapon() gates on category AND weapon; a MISC item carrying a stray WeaponData still pictures world_model.
	var it := Item.new()
	it.category = Item.Category.MISC
	it.weapon = WeaponData.new()
	it.weapon.view_model = PackedScene.new()
	var wm := BoxMesh.new()
	it.world_model = wm
	assert_eq(ItemMeshView.model_resource_for(it), wm, "only a WEAPON-category item reads its view_model")
	it = null


# --- measure_aabb --------------------------------------------------------------------------------------------

func test_measure_aabb_of_one_offset_box_in_root_space() -> void:
	var root := _root()
	root.add_child(_box(Vector3(2, 4, 6), Vector3(1, 0, 0)))
	_assert_aabb(ItemMeshView.measure_aabb(root), Vector3(0, -2, -3), Vector3(2, 4, 6),
		"a 2x4x6 box centred at x=1 spans 0..2 / -2..2 / -3..3")

func test_measure_aabb_merges_every_geometry_child() -> void:
	var root := _root()
	root.add_child(_box(Vector3(1, 1, 1), Vector3(0, 0, 0)))
	var deep := Node3D.new()
	root.add_child(deep)
	deep.add_child(_box(Vector3(1, 1, 1), Vector3(4, 0, 0)))
	_assert_aabb(ItemMeshView.measure_aabb(root), Vector3(-0.5, -0.5, -0.5), Vector3(5, 1, 1),
		"two unit boxes at x=0 and x=4 (one nested) merge into a 5-wide box")

func test_measure_aabb_is_in_the_roots_local_space() -> void:
	# The root's own transform is factored OUT: a scaled / moved root measures the same box as an identity one,
	# because _normalize scales and moves the root itself and must reason in its own space.
	var root := _root()
	root.position = Vector3(10, 0, 0)
	root.scale = Vector3(2, 2, 2)
	root.add_child(_box(Vector3(2, 2, 2)))
	_assert_aabb(ItemMeshView.measure_aabb(root), Vector3(-1, -1, -1), Vector3(2, 2, 2),
		"the box reads in root-local units regardless of the root's world transform")

func test_measure_aabb_excludes_particles() -> void:
	# A particle system's AABB is its authored visibility slack, not art — merging it in would dwarf the mesh.
	var root := _root()
	root.add_child(_box(Vector3(1, 1, 1)))
	var p := CPUParticles3D.new()
	p.visibility_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	root.add_child(p)
	_assert_aabb(ItemMeshView.measure_aabb(root), Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1),
		"the particle volume is ignored; only the unit box counts")

func test_measure_aabb_of_no_geometry_is_empty() -> void:
	var root := _root()
	root.add_child(Node3D.new())
	var a := ItemMeshView.measure_aabb(root)
	assert_true(a.size.is_zero_approx(), "no GeometryInstance3D under the root -> a zero-size box")

func test_measure_aabb_accepts_a_plain_node_root() -> void:
	# The icon baker / preview may hand a non-Node3D root: it measures in world space with an identity inverse.
	var holder := Node.new()
	add_child_autofree(holder)
	var box := _box(Vector3(2, 2, 2), Vector3(1, 1, 1))
	holder.add_child(box)
	_assert_aabb(ItemMeshView.measure_aabb(holder), Vector3(0, 0, 0), Vector3(2, 2, 2),
		"a Node root uses the identity — the box reads in world space")


# --- The instance under headless -----------------------------------------------------------------------------

func test_ready_configures_the_container_and_skips_the_rig_headless() -> void:
	var view := ItemMeshView.new()
	add_child_autofree(view)
	assert_true(view.stretch, "the viewport must fill the tile rect")
	assert_eq(view.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the grid view owns all mouse input")
	assert_null(view._holder, "headless builds no SubViewport rig (no renderer) — _holder stays null")
	assert_null(view._cam, "and no camera")

func test_show_item_is_a_silent_no_op_headless() -> void:
	# ⭐This is what keeps GUT from instantiating a weapon scene through a tile: with no rig, show_item returns
	# before touching the model.
	var view := ItemMeshView.new()
	add_child_autofree(view)
	var it := Item.new()
	it.id = &"test_mesh_view_item"
	it.world_model = BoxMesh.new()
	view.show_item(it)
	assert_eq(view._shown_id, StringName(""), "no rig -> the shown id is never recorded")
	view.show_item(null)
	assert_eq(view._shown_id, StringName(""), "a null item is ignored as well")
	it = null

func test_normalize_scales_the_largest_dimension_to_one_and_centres() -> void:
	var view := ItemMeshView.new()
	add_child_autofree(view)
	var stage := _root()
	var inst := Node3D.new()
	stage.add_child(inst)
	inst.add_child(_box(Vector3(2, 4, 6), Vector3(1, 0, 0)))
	view._normalize(inst)
	assert_true(inst.scale.is_equal_approx(Vector3.ONE / 6.0), "the 6-long axis is scaled to 1 (uniform 1/6). Got %s" % inst.scale)
	assert_true(inst.position.is_equal_approx(Vector3(-1.0 / 6.0, 0, 0)),
		"the box centre (x=1, scaled) lands on the origin. Got %s" % inst.position)
	assert_true(view._ext.is_equal_approx(Vector3(2.0 / 6.0, 4.0 / 6.0, 1.0)),
		"the recorded extents are the normalized box with its largest component 1. Got %s" % view._ext)

func test_normalize_of_an_empty_model_keeps_unit_extents() -> void:
	var view := ItemMeshView.new()
	add_child_autofree(view)
	var stage := _root()
	var inst := Node3D.new()
	stage.add_child(inst)
	view._normalize(inst)
	assert_true(view._ext.is_equal_approx(Vector3.ONE), "a zero-size model must not divide by zero — extents stay ONE")
	assert_true(inst.scale.is_equal_approx(Vector3.ONE), "and the instance is left unscaled")

func test_frame_returns_quietly_without_a_camera() -> void:
	var view := ItemMeshView.new()
	add_child_autofree(view)
	view._frame()
	assert_null(view._cam, "headless: no camera, and _frame (wired to `resized`) must not error without one")
