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
func _mesh_with_material(mat: Material) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi

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
