extends GutTest

## ModelResource.instantiate — the single chokepoint that turns an authored model Resource (PackedScene or Mesh)
## into a Node3D for the world pickups (MoneyPickUp coin / UpgradePickup emblem / CanPickUp item visual). XC1 added
## an empty-reimport guard: a briefly-empty reimported PackedScene (a bare, script-less, child-less, mesh-less Node3D)
## is rejected -> null, so the caller's `if vis == null` placeholder fallback fires instead of planting an invisible
## ghost. These pin the guard's accept/reject boundary + the normal PackedScene / Mesh / null paths. All off-tree.


func test_null_and_non_model_return_null() -> void:
	assert_null(ModelResource.instantiate(null), "a null model -> null")
	assert_false(ModelResource.is_model(null), "null is not a model")
	assert_false(ModelResource.is_model(Resource.new()), "a plain Resource is not a model")


func test_mesh_becomes_a_named_mesh_instance() -> void:
	var mesh := BoxMesh.new()
	var n := ModelResource.instantiate(mesh, "Coin")
	assert_true(n is MeshInstance3D, "a Mesh model -> a MeshInstance3D")
	assert_eq((n as MeshInstance3D).mesh, mesh, "the mesh is carried through")
	assert_eq(n.name, "Coin", "the fallback_name names the built node")
	assert_true(ModelResource.is_model(mesh), "a Mesh is a model")
	n.free()


func test_empty_reimport_packedscene_is_rejected() -> void:
	# The XC1 reject signature: a bare, script-less, child-less, mesh-less Node3D — exactly what instantiating an
	# EMPTY reimported PackedScene yields. It must come back null so the caller uses its built-in placeholder.
	var empty := Node3D.new()
	var ps := PackedScene.new()
	ps.pack(empty)
	empty.free()
	assert_true(ModelResource.is_model(ps), "a PackedScene is a model (type-wise)")
	assert_null(ModelResource.instantiate(ps), "an empty (bare Node3D) PackedScene is rejected -> null (caller falls back)")


func test_real_packedscene_with_children_passes_through() -> void:
	# A real model has children (or a script, or a mesh) -> NOT mistaken for an empty reimport.
	var root := Node3D.new()
	var child := MeshInstance3D.new()
	child.mesh = BoxMesh.new()
	root.add_child(child)
	child.owner = root  # required so pack() serializes the child
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	var n := ModelResource.instantiate(ps)
	assert_true(n is Node3D, "a PackedScene with real content instantiates through")
	assert_gt(n.get_child_count(), 0, "its children survived (not treated as an empty reimport)")
	n.free()


func test_single_meshinstance_root_passes_through() -> void:
	# A model whose ROOT is a MeshInstance3D with a mesh (child-less + script-less) is real, not an empty reimport.
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var ps := PackedScene.new()
	ps.pack(mi)
	mi.free()
	var n := ModelResource.instantiate(ps)
	assert_true(n is MeshInstance3D and (n as MeshInstance3D).mesh != null, "a mesh-bearing MeshInstance3D root passes through")
	n.free()
