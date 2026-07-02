class_name ModelResource
extends RefCounted

const HINT := "PackedScene,Mesh"

static func is_model(value: Variant) -> bool:
	return value is PackedScene or value is Mesh

static func instantiate(model: Resource, fallback_name: String = "Model") -> Node3D:
	if model is PackedScene:
		var root := (model as PackedScene).instantiate()
		if root is Node3D:
			var n3 := root as Node3D
			# Empty-reimport guard (XC1): a headless / mid-edit reimport can briefly hand back an EMPTY PackedScene whose
			# instantiate() is a bare, script-less, child-less, mesh-less Node3D. Spawning it plants an INVISIBLE ghost —
			# and the caller's `if vis == null` fallback to a built-in placeholder (coin / emblem / item visual) never
			# fires. Treat that signature as "not ready yet" -> null so the caller uses its placeholder instead. A real
			# model always has a script, children, or a mesh; a bare empty Node3D is visually nothing anyway.
			if n3.get_script() == null and n3.get_child_count() == 0 and not (n3 is MeshInstance3D and (n3 as MeshInstance3D).mesh != null):
				n3.queue_free()
				return null
			return n3
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
