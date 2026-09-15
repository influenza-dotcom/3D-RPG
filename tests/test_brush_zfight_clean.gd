extends GutTest

## BrushZFightClean — the runtime pass that clips same-facing coplanar overlaps out of func_godot brush meshes
## (the interpenetrating-brush z-fight strobe). Builds tiny quads under a FuncGodotMap-scripted node IN the tree
## (the pass reads global_transform; off-tree that is a tracked engine error) and pins the contract: the larger
## face loses exactly the overlapped area, new corners interpolate attributes, winding survives, opposite-facing /
## transparent / non-map meshes are left alone, and a second pass is a no-op.

const SCRIPT_PATH := "res://scripts/components/brush_zfight_clean.gd"
const MAP_SCRIPT := "res://addons/func_godot/src/map/func_godot_map.gd"
const UP := Vector3.UP

var _root: Node3D
var _map: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_map = Node3D.new()
	_map.name = "FuncGodotMap"
	_map.set_script(load(MAP_SCRIPT))   # no lifecycle hooks on FuncGodotMap: attaching it is inert
	_root.add_child(_map)


func _cleaner() -> Node:
	var c: Node = load(SCRIPT_PATH).new()
	autofree(c)
	return c


func _mat(name: String = "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	return m


## A quad of `size` (r, f extents) centred at `center`, facing `n`, wound CLOCKWISE seen from the front (Godot's
## front-face convention), with UVs = a linear map of position so interpolation can be checked exactly.
func _quad(parent: Node, center: Vector3, size: Vector2, n: Vector3, mat: Material) -> MeshInstance3D:
	var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var r := n.cross(up).normalized()
	var f := r.cross(n).normalized()   # r × f = -n: ccw in (r, f) is clockwise seen from +n
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var corners := [
		center - r * hx - f * hz, center + r * hx - f * hz, center + r * hx + f * hz, center - r * hx + f * hz,
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	for c in corners:
		st.set_normal(n)
		st.set_uv(_uv_of(c))
		st.add_vertex(c)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_index(i)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	parent.add_child(mi)
	return mi


static func _uv_of(p: Vector3) -> Vector2:
	return Vector2(p.x * 0.25 + 0.5, p.z * 0.25 + 0.5)


static func _tri_count(mi: MeshInstance3D) -> int:
	var n := 0
	for s in mi.mesh.get_surface_count():
		n += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


static func _surface_area(mi: MeshInstance3D) -> float:
	var total := 0.0
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k in range(0, ix.size(), 3):
			total += (v[ix[k + 1]] - v[ix[k]]).cross(v[ix[k + 2]] - v[ix[k]]).length() * 0.5
	return total


func test_quad_helper_front_faces_its_normal() -> void:
	var mi := _quad(_map, Vector3.ZERO, Vector2(2, 2), UP, _mat("a"))
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var a := v[ix[0]]
	var b := v[ix[1]]
	var c := v[ix[2]]
	assert_gt((c - a).cross(b - a).dot(UP), 0.0, "clockwise-from-the-front winding: outward normal is (c-a)×(b-a)")


func test_same_facing_overlap_is_clipped_out_of_the_larger_face() -> void:
	var big := _quad(_map, Vector3.ZERO, Vector2(4, 4), UP, _mat("slab"))
	var small := _quad(_map, Vector3.ZERO, Vector2(1, 1), UP, _mat("detail"))
	var small_mesh := small.mesh
	var c := _cleaner()
	var before: Dictionary = c.overlap_report(_root)
	assert_gt(before.pairs, 0, "the 1x1 quad sits on the 4x4 quad: same plane, same facing = a fight")
	assert_almost_eq(before.area_m2, 1.0, 0.001, "the whole 1 m² of the small quad is overlapped")
	var rep: Dictionary = c.clean(_root)
	assert_eq(rep.meshes_touched, 1, "only the loser's mesh is rebuilt")
	assert_eq(rep.tris_removed, 0, "the big face is partially covered: clipped, not removed")
	assert_true(is_same(small.mesh, small_mesh), "the winner (smaller face) keeps its original ArrayMesh")
	assert_eq(_tri_count(small), 2, "the detail quad is untouched")
	assert_gt(_tri_count(big), 2, "the slab is re-emitted as the pieces around the hole")
	assert_almost_eq(_surface_area(big), 15.0, 0.001, "the slab lost exactly the 1 m² under the detail")
	var after: Dictionary = c.overlap_report(_root)
	assert_eq(after.pairs, 0, "no same-facing overlap remains")
	assert_eq(big.mesh.surface_get_material(0).resource_name, "slab", "the rebuilt surface keeps its material")


func test_new_corners_interpolate_attributes_and_keep_winding() -> void:
	var big := _quad(_map, Vector3.ZERO, Vector2(4, 4), UP, _mat("slab"))
	_quad(_map, Vector3(0.5, 0, 0.25), Vector2(1, 1.5), UP, _mat("detail"))   # off-centre: every cut is a real cut
	_cleaner().clean(_root)
	var arr := big.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var tan: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	assert_gt(v.size(), 4, "new corners were appended")
	assert_eq(uv.size(), v.size(), "every appended vertex has a UV")
	assert_eq(nrm.size(), v.size(), "every appended vertex has a normal")
	assert_eq(tan.size(), v.size() * 4, "every appended vertex has a 4-float tangent")
	for i in v.size():
		assert_almost_eq(uv[i].x, _uv_of(v[i]).x, 0.0005, "UV.x of vertex %d is the linear map of its position" % i)
		assert_almost_eq(uv[i].y, _uv_of(v[i]).y, 0.0005, "UV.y of vertex %d is the linear map of its position" % i)
		assert_almost_eq(nrm[i].y, 1.0, 0.0005, "normal of vertex %d stays UP" % i)
		assert_almost_eq(absf(tan[i * 4 + 3]), 1.0, 0.0005, "tangent handedness of vertex %d is ±1" % i)
	for k in range(0, ix.size(), 3):
		var a := v[ix[k]]
		var b := v[ix[k + 1]]
		var cc := v[ix[k + 2]]
		assert_gt((cc - a).cross(b - a).dot(UP), 0.0, "rebuilt triangle at index %d still faces UP" % k)


func test_identical_faces_keep_exactly_one() -> void:
	var first := _quad(_map, Vector3.ZERO, Vector2(2, 2), UP, _mat("a"))
	var second := _quad(_map, Vector3.ZERO, Vector2(2, 2), UP, _mat("b"))
	var rep: Dictionary = _cleaner().clean(_root)
	assert_eq(rep.tris_removed, 2, "a fully covered face is dropped whole, not clipped")
	assert_eq(_tri_count(first), 2, "the earlier face wins the tie")
	assert_eq(_tri_count(second), 0, "the later identical face loses")


func test_forced_loser_material_loses_even_when_smaller() -> void:
	var big := _quad(_map, Vector3.ZERO, Vector2(4, 4), UP, _mat("floor"))
	var sky := _quad(_map, Vector3.ZERO, Vector2(1, 1), UP, _mat("sky1"))
	_cleaner().clean(_root)
	assert_eq(_tri_count(big), 2, "the floor is untouched")
	assert_eq(_tri_count(sky), 0, "the sky face loses regardless of size (default loser_surfaces = [sky])")


func test_opposite_facing_flush_faces_are_left_alone() -> void:
	var top := _quad(_map, Vector3.ZERO, Vector2(2, 2), UP, _mat("a"))
	var bottom := _quad(_map, Vector3.ZERO, Vector2(2, 2), Vector3.DOWN, _mat("b"))
	var top_mesh := top.mesh
	var bottom_mesh := bottom.mesh
	var c := _cleaner()
	assert_eq(c.overlap_report(_root).pairs, 0, "opposite normals never fight (back-face culling hides one)")
	var rep: Dictionary = c.clean(_root)
	assert_eq(rep.meshes_touched, 0, "nothing rebuilt")
	assert_true(is_same(top.mesh, top_mesh) and is_same(bottom.mesh, bottom_mesh), "both meshes are the originals")


func test_transparent_surfaces_are_skipped() -> void:
	_quad(_map, Vector3.ZERO, Vector2(4, 4), UP, _mat("slab"))
	var cutout := _mat("fence")
	cutout.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_quad(_map, Vector3.ZERO, Vector2(1, 1), UP, cutout)
	var c := _cleaner()
	assert_eq(c.overlap_report(_root).pairs, 0, "a cutout surface renders in its own pass and is not harvested")
	assert_eq(c.clean(_root).meshes_touched, 0, "so nothing is rebuilt")


func test_meshes_outside_a_funcgodotmap_are_ignored() -> void:
	var props := Node3D.new()
	_root.add_child(props)
	_quad(props, Vector3.ZERO, Vector2(4, 4), UP, _mat("a"))
	_quad(props, Vector3.ZERO, Vector2(1, 1), UP, _mat("b"))
	var c := _cleaner()
	assert_eq(c.overlap_report(_root).meshes, 0, "authored prop meshes are not brush geometry")
	assert_eq(c.clean(_root).meshes_touched, 0, "and are never rebuilt")


func test_second_pass_is_a_no_op() -> void:
	_quad(_map, Vector3.ZERO, Vector2(4, 4), UP, _mat("slab"))
	_quad(_map, Vector3(0.7, 0, -0.3), Vector2(1, 1), UP, _mat("detail"))
	var c := _cleaner()
	c.clean(_root)
	var again: Dictionary = c.clean(_root)
	assert_eq(again.pairs, 0, "no overlap is found on a cleaned level")
	assert_eq(again.meshes_touched, 0, "and no mesh is rebuilt again")


func test_ready_cleans_the_parent_and_keeps_the_report() -> void:
	var big := _quad(_map, Vector3.ZERO, Vector2(4, 4), UP, _mat("slab"))
	_quad(_map, Vector3.ZERO, Vector2(1, 1), UP, _mat("detail"))
	var c := _cleaner()
	_root.add_child(c)   # _ready runs the pass over the parent's subtree
	assert_gt((c.get("last_report") as Dictionary).get("pairs", 0), 0, "last_report carries the tally of the pass")
	assert_almost_eq(_surface_area(big), 15.0, 0.001, "the slab under the level root was cleaned on _ready")


func test_disabled_node_does_nothing() -> void:
	var big := _quad(_map, Vector3.ZERO, Vector2(4, 4), UP, _mat("slab"))
	_quad(_map, Vector3.ZERO, Vector2(1, 1), UP, _mat("detail"))
	var c := _cleaner()
	c.set("enabled", false)
	_root.add_child(c)
	assert_eq(_tri_count(big), 2, "enabled = false leaves the meshes exactly as authored")
	assert_true((c.get("last_report") as Dictionary).is_empty(), "and records no pass")


func test_level_root_spawns_the_pass_at_runtime() -> void:
	var level := LevelRoot.new()
	var map := Node3D.new()
	map.name = "FuncGodotMap"
	map.set_script(load(MAP_SCRIPT))
	level.add_child(map)
	var big := _quad(map, Vector3.ZERO, Vector2(4, 4), UP, _mat("slab"))
	_quad(map, Vector3.ZERO, Vector2(1, 1), UP, _mat("detail"))
	add_child_autofree(level)   # LevelRoot._ready runs here, after its children are in the tree
	var spawned := level.get_node_or_null("BrushZFightClean")
	assert_not_null(spawned, "LevelRoot spawns the pass at runtime — no level authors the node")
	assert_almost_eq(_surface_area(big), 15.0, 0.001, "and the level's brush mesh was cleaned on load")


func test_level_root_leaves_a_hand_placed_pass_alone() -> void:
	var level := LevelRoot.new()
	var own: Node = load(SCRIPT_PATH).new()
	own.name = "MyZFightClean"
	level.add_child(own)
	add_child_autofree(level)
	assert_null(level.get_node_or_null("BrushZFightClean"), "an authored BrushZFightClean suppresses the spawn")


func test_level_root_toggle_off_spawns_nothing() -> void:
	var level := LevelRoot.new()
	level.clean_brush_zfights = false
	add_child_autofree(level)
	assert_eq(level.get_child_count(), 0, "clean_brush_zfights = false: the root spawns no pass")
