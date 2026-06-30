class_name ModelResource
extends RefCounted

const HINT := "PackedScene,Mesh"

static func is_model(value: Variant) -> bool:
	return value is PackedScene or value is Mesh

static func instantiate(model: Resource, fallback_name: String = "Model") -> Node3D:
	if model is PackedScene:
		var root := (model as PackedScene).instantiate()
		if root is Node3D:
			return root as Node3D
		if root is Node:
			(root as Node).queue_free()
		return null
	if model is Mesh:
		var mi := MeshInstance3D.new()
		mi.name = fallback_name
		mi.mesh = model as Mesh
		return mi
	return null

static func label(model: Resource) -> String:
	if model == null:
		return "<null>"
	if not model.resource_path.is_empty():
		return model.resource_path
	return str(model)
