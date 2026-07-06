extends GutTest

## Tests for MeshCoat — the shared runtime coat-recolour helper (mesh resolution + material duplication) that RandomCoat
## and SprayPaintable both use. The pure / off-tree bits (mesh_path resolution, first-mesh fallback, duplicate-not-
## shared) are unit-tested here; the deferred in-tree recolour on a real Throwable dog is playtest-verified.

const MeshCoat := preload("res://scripts/components/mesh_coat.gd")


func test_resolve_empty_when_no_parent_no_path() -> void:
	# A bare component with no mesh_path and no parent resolves to nothing rather than erroring.
	var comp := Node.new()
	var meshes := MeshCoat.resolve_meshes(comp, NodePath())
	assert_eq(meshes.size(), 0, "no host and no mesh_path => no target meshes")
	comp.free()


func test_resolve_null_component_safe() -> void:
	assert_eq(MeshCoat.resolve_meshes(null, NodePath()).size(), 0, "a null component resolves to [] instead of crashing")


func test_resolve_mesh_path_wins() -> void:
	var comp := Node.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Coat"
	comp.add_child(mesh)
	var meshes := MeshCoat.resolve_meshes(comp, NodePath("Coat"))
	assert_eq(meshes.size(), 1, "an explicit mesh_path resolves to exactly that mesh")
	assert_eq(meshes[0], mesh, "the wired mesh is the one returned")
	comp.free()  # frees the child mesh too


func test_resolve_first_mesh_fallback() -> void:
	# No mesh_path and a host that doesn't expose `mesh_instance` (a plain Node) => first MeshInstance3D under the host.
	var host := Node.new()
	var comp := Node.new()
	host.add_child(comp)
	var mesh := MeshInstance3D.new()
	host.add_child(mesh)
	var meshes := MeshCoat.resolve_meshes(comp, NodePath())
	assert_eq(meshes.size(), 1, "with no mesh_path and no host.mesh_instance, the first mesh under the host is used")
	assert_eq(meshes[0], mesh, "the first MeshInstance3D descendant of the host is returned")
	host.free()


func test_writable_material_duplicates_override() -> void:
	# The returned material MUST be a distinct copy of material_override — recolouring it must never mutate the shared
	# source. That is the whole reason MeshCoat exists (a scene material is shared across every instance).
	var mesh := MeshInstance3D.new()
	var shared := StandardMaterial3D.new()
	shared.albedo_color = Color(0.2, 0.4, 0.6)
	mesh.material_override = shared
	var writable := MeshCoat.writable_material(mesh)
	assert_ne(writable, shared, "writable_material returns a duplicate, not the shared source")
	assert_eq(writable.albedo_color, shared.albedo_color, "the duplicate preserves the source's albedo")
	writable.albedo_color = Color.RED
	assert_ne(shared.albedo_color, Color.RED, "mutating the duplicate leaves the shared source untouched")
	shared = null
	writable = null
	mesh.free()


func test_writable_material_fresh_when_none() -> void:
	# No override, no mesh => a fresh StandardMaterial3D so a coat still shows (rather than null).
	var mesh := MeshInstance3D.new()
	var writable := MeshCoat.writable_material(mesh)
	assert_not_null(writable, "a mesh with no material still yields a writable StandardMaterial3D")
	assert_true(writable is StandardMaterial3D, "the fresh material is a StandardMaterial3D")
	writable = null
	mesh.free()
