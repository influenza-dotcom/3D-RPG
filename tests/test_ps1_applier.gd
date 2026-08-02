extends GutTest
## F-C49 — the PS1 warp applier only warps plain BaseMaterial3D surfaces.
##
## `_ps1ify` walks a mesh's surfaces and swaps each opaque BaseMaterial3D for the ps1 warp shader, carrying that
## material's albedo tex/colour across. A ShaderMaterial (an authored effect, OR the applier's own override on a
## re-walk) and a material-less surface have NO albedo to read — warping them would paint them flat opaque white
## and wipe the authored shader. So a non-BaseMaterial3D surface must be SKIPPED (no override set, nothing
## recorded in _warped -> the walk is also idempotent).
##
## Built OFF-TREE: load(...).new() WITHOUT add_child, so _ready never runs (no Settings lookup / _process). We
## call _ps1ify directly on a hand-built one-surface MeshInstance3D and inspect the override + the _warped ledger.

const PS1_PATH := "res://scripts/effects/ps1_applier.gd"

## A 1-surface ArrayMesh (a bare triangle) whose surface material is `mat`, wrapped in a MeshInstance3D.
func _mesh_with_vertices(mat: Material, vertices: PackedVector3Array) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi

func _mesh_with_material(mat: Material) -> MeshInstance3D:
	return _mesh_with_vertices(mat, PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP]))

func _floor_mesh_with_material(mat: Material) -> MeshInstance3D:
	return _mesh_with_vertices(mat, PackedVector3Array([Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT]))

func test_shader_material_surface_is_skipped() -> void:
	var a = load(PS1_PATH).new()  # no add_child -> _ready never runs
	var shader_mat := ShaderMaterial.new()
	var mi := _mesh_with_material(shader_mat)
	a._ps1ify(mi)
	assert_null(mi.get_surface_override_material(0), "a ShaderMaterial surface is left untouched (no warp override)")
	assert_true(a._warped.is_empty(), "nothing recorded in the restore ledger for a skipped surface")
	mi.free()
	a.free()
	shader_mat = null

func test_opaque_base_material_surface_is_warped() -> void:
	var a = load(PS1_PATH).new()
	var base_mat := StandardMaterial3D.new()  # a BaseMaterial3D, opaque by default -> warpable
	var mi := _mesh_with_material(base_mat)
	a._ps1ify(mi)
	var ov := mi.get_surface_override_material(0)
	assert_not_null(ov, "an opaque BaseMaterial3D surface gets a warp override")
	assert_true(ov is ShaderMaterial, "the override is the ps1 ShaderMaterial")
	assert_true(not a._warped.is_empty(), "the warped surface is recorded so _restore can undo it")
	mi.free()
	a.free()
	base_mat = null

func test_floor_like_surface_is_stabilized_when_opted_in() -> void:
	# Floor stabilization is OPT-IN now (default false): freezing floors while adjoining walls warp tears a
	# flickering seam at every stair-step / wall-base contact line, so the shipped comfort path is the
	# shader's snap_near_fade window instead. The classification machinery stays for levels that opt in.
	var a = load(PS1_PATH).new()
	a.stabilize_floor_surfaces = true
	var base_mat := StandardMaterial3D.new()
	var mi := _floor_mesh_with_material(base_mat)
	a._ps1ify(mi)
	assert_null(mi.get_surface_override_material(0), "with stabilization opted in, a horizontal floor-like surface is left stable")
	assert_true(a._warped.is_empty(), "stabilized floor surfaces are not recorded as warped")
	mi.free()
	a.free()
	base_mat = null

func test_floor_like_surface_warps_by_default() -> void:
	# The default: floors warp WITH their walls so shared corner vertices snap identically and every
	# contact edge stays glued (watertight), instead of tearing against frozen floor geometry.
	var a = load(PS1_PATH).new()
	var base_mat := StandardMaterial3D.new()
	var mi := _floor_mesh_with_material(base_mat)
	a._ps1ify(mi)
	assert_not_null(mi.get_surface_override_material(0), "by default a floor-like surface warps like any other opaque surface")
	assert_true(not a._warped.is_empty(), "a warped floor surface records restore data like any warped surface")
	mi.free()
	a.free()
	base_mat = null
