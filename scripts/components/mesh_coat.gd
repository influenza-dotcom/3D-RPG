class_name MeshCoat
extends RefCounted

## Shared runtime coat-recolour contract for the cosmetic mesh-tinting drop-ins (RandomCoat, SprayPaintable). It
## centralises the three non-obvious rules that ANY "recolour a prop's albedo at runtime" code must honour, so they
## live in ONE place instead of being re-derived — and silently mis-implemented — per component:
##
##   1. DUPLICATE the material. A scene's StandardMaterial3D is a SINGLE sub-resource shared by every instance of that
##      scene (every dog shares dog.tscn's material). Tinting it in place recolours EVERY instance at once AND mutates
##      the on-disk resource. `writable_material()` hands back a per-instance duplicate to recolour.
##   2. Touch material_OVERRIDE only. The look-at outline + red hit-flash live on material_OVERLAY (a separate channel,
##      `Throwable._setup_overlay_chain`). Callers reassign the duplicate as `material_override` and never touch the
##      overlay, so the outline / flash keep working.
##   3. Resolve the target mesh the same way everywhere: an explicit `mesh_path` wins, else the host's `mesh_instance`
##      (a `Throwable` exposes its visual root there), else the first `MeshInstance3D` under the host.
##
## Pure static utility — never instantiated. Only `StandardMaterial3D` albedo is supported: a `ShaderMaterial` prop
## can't be tinted this way, so `writable_material()` falls back to a fresh `StandardMaterial3D` (the coat still shows,
## it just doesn't build on the shader). See [[throwable-runtime-recolor-contract]].


## Resolve the mesh(es) a coat component recolours. `component` is the drop-in node itself: `mesh_path` is resolved
## relative to it, and its parent is the host prop. Returns [] off-tree / when nothing is found.
static func resolve_meshes(component: Node, mesh_path: NodePath) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if component == null:
		return out
	if not mesh_path.is_empty():
		var wired := component.get_node_or_null(mesh_path)
		if wired is MeshInstance3D:
			out.append(wired as MeshInstance3D)
		return out
	var host := component.get_parent()
	if host == null:
		return out
	var mi: Variant = host.get(&"mesh_instance")  # a Throwable / dog exposes its visual root here
	if mi is MeshInstance3D:
		out.append(mi as MeshInstance3D)
		return out
	var found := first_mesh(host)
	if found != null:
		out.append(found)
	return out


## A writable per-instance StandardMaterial3D for `m`: a DUPLICATE of its `material_override`, else a duplicate of its
## active surface material, else a fresh StandardMaterial3D. Duplicating preserves every other property (roughness,
## cull, transparency…) — the caller only overwrites albedo. Never returns the shared source itself, so recolouring
## the result can't leak into other instances or the on-disk resource.
static func writable_material(m: MeshInstance3D) -> StandardMaterial3D:
	var src: Material = m.material_override
	if src == null and m.mesh != null and m.mesh.get_surface_count() > 0:
		src = m.get_active_material(0)
	if src is StandardMaterial3D:
		return (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	return StandardMaterial3D.new()


## First MeshInstance3D in `node`'s descendants (depth-first), or null. Used only when the host doesn't expose a
## `mesh_instance` and no `mesh_path` was wired.
static func first_mesh(node: Node) -> MeshInstance3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			return c as MeshInstance3D
		var deeper := first_mesh(c)
		if deeper != null:
			return deeper
	return null
