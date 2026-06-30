@tool
extends RefCounted

## EDITOR-ONLY: render an item's mesh scene to a transparent Image, framed like the live inventory tile but baked
## ONCE at the icon's footprint size. A SubViewport must be in the tree to render, so the caller (the Icons tab)
## passes itself as `host` to temporarily parent it. Returns null with no renderer (headless GUT) or for a meshless
## scene — so it never breaks a headless run. The framing math (normalize / fit_ortho_size) is the unit-tested
## icon_render.gd; only the render rig + capture live here (editor-verified). ASYNC: awaits the draw before capture.

const Render := preload("res://addons/cybersunday_tools/dock_icons/icon_render.gd")

## The same 3/4 view angle item_mesh_view uses, so a baked icon matches the live look the designer already sees.
const CAM_DIR := Vector3(0.62, 0.5, 1.0)


## Render `mesh_scene` to an Image of `px_size`, or null. `host` must already be in the editor tree.
func bake(mesh_scene: PackedScene, px_size: Vector2i, host: Node):
	if DisplayServer.get_name() == "headless" or mesh_scene == null or host == null or not host.is_inside_tree():
		return null
	var vp := SubViewport.new()
	vp.size = px_size
	vp.transparent_bg = true
	vp.world_3d = World3D.new()  # isolated — the edited scene never bleeds into the icon
	vp.msaa_3d = Viewport.MSAA_4X
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.74, 0.80)
	env.ambient_light_energy = 1.35
	vp.world_3d.environment = env
	host.add_child(vp)  # in-tree now so transforms + rendering work

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.01
	cam.far = 20.0
	vp.add_child(cam)
	cam.position = CAM_DIR.normalized() * 4.0
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	key.light_energy = 1.4
	vp.add_child(key)

	var inst: Node = mesh_scene.instantiate()
	if inst == null:
		return null  # empty-PackedScene reimport transient -> instantiate() can return null; bail (matches the documented null result)
	vp.add_child(inst)
	if inst is Node3D:
		var nrm := Render.normalize(_aabb(inst as Node3D))
		(inst as Node3D).scale = Vector3.ONE * float(nrm["scale"])
		(inst as Node3D).position = nrm["offset"]
		var aspect := float(px_size.x) / float(maxi(1, px_size.y))
		cam.size = Render.fit_ortho_size(cam.global_transform, nrm["ext"], aspect)

	# Render + capture. UPDATE_ALWAYS + TWO frame waits is the robust capture: a single wait after UPDATE_ONCE can
	# catch the end of the current frame BEFORE the viewport re-renders with the mesh, yielding a BLANK icon. We free
	# the viewport immediately after, so "always" only ever costs these two frames.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


## Save `image` as a PNG at `path` (creating the folder). Returns OK/err. Static so the tab can call without the rig.
static func save_png(image: Image, path: String) -> int:
	if image == null:
		return ERR_INVALID_DATA
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return image.save_png(path)


## AABB of all VisualInstance3D descendants in the root's local space (mirrors item_mesh_view._aabb).
func _aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var out := AABB()
	var seeded := false
	for vi in _visual_instances(root):
		var a := _xform_aabb(inv * vi.global_transform, vi.get_aabb())
		if not seeded:
			out = a
			seeded = true
		else:
			out = out.merge(a)
	return out


func _visual_instances(node: Node) -> Array:
	var out: Array = []
	if node is VisualInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_visual_instances(c))
	return out


func _xform_aabb(xf: Transform3D, a: AABB) -> AABB:
	var out := AABB(xf * a.position, Vector3.ZERO)
	for i in range(1, 8):
		out = out.expand(xf * (a.position + Vector3(a.size.x if (i & 1) else 0.0, a.size.y if (i & 2) else 0.0, a.size.z if (i & 4) else 0.0)))
	return out
