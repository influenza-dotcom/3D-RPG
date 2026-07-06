@tool
extends RefCounted

## RENDERER-REQUIRED: render an item's icon to a transparent Image, framed like the live inventory tile but baked
## ONCE at the item's footprint size — then AUTOCROPPED to the actual rendered pixels (padded back out to the
## footprint aspect) so the icon has no dead space, whatever the model's AABB claims. Items WITHOUT any authored
## model render a procedural primitive stand-in (icon_models.gd) instead, so EVERY item bakes. A SubViewport must
## be in the tree to render, so the caller (the Icons tab, or scripts/tools/bake_item_icons.gd) passes itself as
## `host` to temporarily parent it. Returns null with no renderer (headless GUT) or when nothing rendered — so it
## never breaks a headless run. The framing/crop math (normalize / fit_ortho_size / refit / crop_rect) is the
## unit-tested icon_render.gd; only the render rig + capture live here (editor-verified). ASYNC: awaits the draws.

const Render := preload("res://addons/cybersunday_tools/dock_icons/icon_render.gd")
const IconModels := preload("res://addons/cybersunday_tools/dock_icons/icon_models.gd")
const ItemMeshView := preload("res://scripts/ui/item_mesh_view.gd")
const ModelResourceUtil := preload("res://scripts/components/model_resource.gd")

## The same 3/4 view angle item_mesh_view uses, so a baked icon matches the live look the designer already sees.
const CAM_DIR := Vector3(0.62, 0.5, 1.0)
## Icon pixels per grid cell (matches the live tile viewport); a 2×1 item -> a 192×96 icon. Shared by the Icons
## tab and the CLI baker so both write identical files.
const CELL := 96
## The render is SUPERSAMPLED at this multiple of the final size, then autocropped + Lanczos-downscaled — the crop
## needs slack pixels to cut away, and the downscale buys clean edges on top of MSAA.
const SUPERSAMPLE := 2


## The model to BAKE an icon from for `item`: the live tile's mesh source (a weapon's view_model, else
## world_model), falling back to the item's `world_prop` SCENE — the full authored prop (a dog crate). The live
## ItemMeshView must never instantiate a world_prop (its gameplay scripts would run in the game); the BAKE path
## may, because bake() strips every script off the instance before it enters the tree. Null = nothing to bake.
static func bake_model_for(item: Item) -> Resource:
	if item == null:
		return null
	var m := ItemMeshView.model_resource_for(item)
	if m != null:
		return m
	if item.world_prop != "":
		var s := load(item.world_prop)
		if s is PackedScene:
			return s
	return null


## Render `item`'s icon to an Image of `px_size`, or null. `host` must be in the tree. EVERY item is bakeable:
## an authored model (view_model / world_model / world_prop scene) when it has one, else a procedural primitive
## stand-in from IconModels (cartridges for ammo, a medkit, keyword trinkets) — so no item is left to the letter
## glyph. Authored models always win; give the .tres a world_model (or Item.icon) and the stand-in retires.
func bake_item(item: Item, px_size: Vector2i, host: Node):
	if DisplayServer.get_name() == "headless" or item == null or host == null or not host.is_inside_tree():
		return null
	var inst: Node3D = null
	var model := bake_model_for(item)
	if model != null:
		inst = ModelResourceUtil.instantiate(model, "IconModel")
		if inst == null:
			return null  # empty-PackedScene reimport transient / not a 3D scene -> bail (matches the documented null result)
		# Strip EVERY script before the instance enters the tree: an icon only needs geometry, and a world_prop scene
		# (dogcrate.tscn) is a live gameplay object whose _ready would otherwise run — in the editor scripts are inert
		# anyway, but the CLI baker runs this in a real game process. Freeze any physics body for the same reason.
		# _apply_data_meshes must run FIRST — it reads script exports the strip discards.
		_apply_data_meshes(inst)
		_strip_behaviour(inst)
	else:
		inst = IconModels.build_for(item)  # script-less primitives by construction — nothing to strip
		if inst == null:
			return null
	return await _bake_instance(inst, px_size, host)


## The capture rig: parent `inst` in an isolated SubViewport, frame it (AABB pass, then a pixel-measured refit),
## autocrop + downscale. `inst` must be an orphan; the viewport adopts and frees it.
func _bake_instance(inst: Node3D, px_size: Vector2i, host: Node):
	var vp := SubViewport.new()
	vp.size = px_size * SUPERSAMPLE
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

	vp.add_child(inst)
	var nrm := Render.normalize(ItemMeshView.measure_aabb(inst))
	inst.scale = Vector3.ONE * float(nrm["scale"])
	inst.position = nrm["offset"]
	var aspect := float(px_size.x) / float(maxi(1, px_size.y))
	cam.size = Render.fit_ortho_size(cam.global_transform, nrm["ext"], aspect)

	# Render + capture. UPDATE_ALWAYS + TWO frame waits is the robust capture: a single wait after UPDATE_ONCE can
	# catch the end of the current frame BEFORE the viewport re-renders with the mesh, yielding a BLANK icon.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		vp.queue_free()
		return null  # nothing rendered (bad model) — treat exactly like a failed bake
	# PASS 2: the AABB fit only guarantees the art is SOMEWHERE in frame (real GLBs carry wildly polluted bounds —
	# the pistol scene's box is ~356 units across). Re-zoom + re-centre the camera from the pixels that actually
	# drew, re-render at full resolution, THEN autocrop to the footprint aspect and downscale. Crisp, no dead space.
	var rf := Render.refit(cam.size, aspect, used, Vector2i(img.get_width(), img.get_height()))
	cam.position += cam.global_transform.basis.x * float(rf["dx"]) + cam.global_transform.basis.y * float(rf["dy"])
	cam.size = float(rf["size"])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	img = vp.get_texture().get_image()
	vp.queue_free()  # capture done — "always" only ever cost these four frames
	used = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	img = img.get_region(Render.crop_rect(used, Vector2i(img.get_width(), img.get_height()), aspect))
	img.resize(px_size.x, px_size.y, Image.INTERPOLATE_LANCZOS)
	return img


## Save `image` as a PNG at `path` (creating the folder). Returns OK/err. Static so the tab can call without the rig.
static func save_png(image: Image, path: String) -> int:
	if image == null:
		return ERR_INVALID_DATA
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return image.save_png(path)


## A stripped script never runs its _ready visual contract, so emulate the ONE that matters for icons first:
## a Throwable-style node whose ThrowableData `mesh` REPLACES the authored `mesh_instance` mesh (Throwable.gd
## _apply_data_model_resource). dogcrate.tscn authors a PlaceholderMesh exactly to blank throwable.tscn's default
## white BoxMesh while the real GLB hangs as a sibling — without this swap the bake renders that box swallowing
## the crate. Duck-typed (any node exporting `data`-with-a-`mesh` + a wired `mesh_instance` gets the swap);
## everything else is untouched. Runs BEFORE _strip_behaviour, which discards the exports this reads.
static func _apply_data_meshes(node: Node) -> void:
	var data = node.get("data")
	var mi = node.get("mesh_instance")
	if data is Resource and mi is MeshInstance3D:
		var m = (data as Resource).get("mesh")
		if m is Mesh:
			(mi as MeshInstance3D).mesh = m  # incl. PlaceholderMesh, which renders nothing — the authored blank
		elif m is PackedScene:
			(mi as MeshInstance3D).mesh = null
			var sub = (m as PackedScene).instantiate()
			if sub != null:
				(mi as MeshInstance3D).add_child(sub)  # scripts on it are stripped right after
	for c in node.get_children():
		_apply_data_meshes(c)


## Drop every script and freeze every physics body under `root` — BEFORE it enters the tree, so no _enter_tree /
## _ready gameplay ever runs and a RigidBody prop doesn't take gravity during the capture frames. (_init has
## already run at instantiate; the prop scenes here don't define one.)
static func _strip_behaviour(root: Node) -> void:
	root.set_script(null)
	if root is RigidBody3D:
		(root as RigidBody3D).freeze = true
	for c in root.get_children():
		_strip_behaviour(c)
