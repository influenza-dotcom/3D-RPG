extends SubViewportContainer

## Shows an item's 3D MESH live inside a UI tile (Resident Evil / Deus Ex style). A tiny isolated SubViewport
## renders the model every frame (the standard, reliable "3D model in a Control" pattern). The model is
## RECENTERED + SCALED to a unit box so the fixed orthographic camera frames it consistently. No class_name
## (preloaded by the grid tile); mouse-transparent so the grid handles input.
##
## NOTE: framing (camera size 1.45 + angle) is intentionally simple + fixed — it reads small in wide tiles; the
## proper aspect-fit pass is on hold until we can eyeball a screenshot (a previous auto-fit attempt mis-framed).

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D     ## the instantiated model hangs here (cleared + rebuilt per item)
var _shown_id: StringName = &""
var _ext: Vector3 = Vector3.ONE  ## the normalized model's box extents (largest = 1) — drives the aspect-fit framing

func _ready() -> void:
	stretch = true                              # the viewport fills the container (tile) rect
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the grid view owns all mouse input
	if DisplayServer.get_name() == "headless":
		return  # no real renderer under GUT — skip the rig; show_item then no-ops (tests don't check visuals)
	_vp = SubViewport.new()
	_vp.size = Vector2i(96, 96)
	_vp.transparent_bg = true
	_vp.world_3d = World3D.new()                # ISOLATED world — the game scene never bleeds in
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.74, 0.80)
	env.ambient_light_energy = 1.35
	_vp.world_3d.environment = env
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 1.2
	_cam.near = 0.01
	_cam.far = 20.0
	_vp.add_child(_cam)                          # in-tree FIRST so look_at + current work
	_cam.position = Vector3(0.62, 0.5, 1.0).normalized() * 4.0
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_cam.current = true                          # CRITICAL: without an active camera the viewport renders nothing
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	key.light_energy = 1.4
	_vp.add_child(key)
	_holder = Node3D.new()
	_vp.add_child(_holder)
	resized.connect(_frame)

## The mesh scene for an item: a weapon's view_model, else its world_model (null for ammo/consumables today).
static func mesh_scene_for(item: Item) -> PackedScene:
	if item == null:
		return null
	if item.is_weapon() and item.weapon != null and item.weapon.view_model != null:
		return item.weapon.view_model
	return item.world_model

## Does `item` have a mesh to show? (The grid tile draws a category glyph instead when not.)
static func has_mesh(item: Item) -> bool:
	return mesh_scene_for(item) != null

## Render `item`'s mesh (idempotent — re-showing the same item id is a no-op so a drag/move doesn't re-instantiate).
func show_item(item: Item) -> void:
	if item == null or item.id == _shown_id or _holder == null:
		return  # _holder is null under headless (no rig) — no-op so GUT never instantiates a weapon scene
	_shown_id = item.id
	for c in _holder.get_children():
		c.queue_free()
	var scene := mesh_scene_for(item)
	if scene == null:
		return
	var inst: Node = scene.instantiate()
	_holder.add_child(inst)
	if inst is Node3D:
		_normalize(inst as Node3D)
	_frame()

## Recentre the model at the origin and scale its largest dimension to 1, recording its normalized extents.
func _normalize(inst: Node3D) -> void:
	var aabb := _aabb(inst)
	var maxdim := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if maxdim <= 0.00001:
		_ext = Vector3.ONE
		return
	var s := 1.0 / maxdim
	inst.scale = Vector3(s, s, s)
	inst.position = -(aabb.position + aabb.size * 0.5) * s  # the (scaled) centre lands on the origin
	_ext = aabb.size * s                                    # normalized extents (largest component is 1.0)

## Size the orthographic camera to EXACTLY fit the model to the tile, whatever the mesh's proportions or the
## tile's shape. We project the model's (origin-centred) bounding box through the camera and fit that footprint
## to the viewport — so a long sniper and a chunky pistol each fill their own tile instead of one being tiny and
## the other overflowing. CLAMPED as a safety net so a bad measurement can never blow it up or vanish.
func _frame() -> void:
	if _cam == null or not _cam.is_inside_tree():
		return
	var cam_inv := _cam.global_transform.affine_inverse()  # world -> camera space
	var half := _ext * 0.5
	var hw := 0.0  # half-width of the model's footprint in the camera's view plane
	var hh := 0.0  # half-height
	for i in 8:
		var corner := Vector3(half.x if (i & 1) else -half.x, half.y if (i & 2) else -half.y, half.z if (i & 4) else -half.z)
		var cv := cam_inv * corner
		hw = maxf(hw, absf(cv.x))
		hh = maxf(hh, absf(cv.y))
	var aspect := maxf(0.05, size.x) / maxf(1.0, size.y)
	# Ortho `size` is the view HEIGHT (KEEP_HEIGHT): fit both the height (2*hh) and the width (2*hw / aspect).
	_cam.size = clampf(maxf(2.0 * hh, 2.0 * hw / aspect) * 1.15, 0.2, 4.0)  # *1.15 air; clamp = anti-explosion

func _aabb(root: Node) -> AABB:
	var inv := (root as Node3D).global_transform.affine_inverse() if root is Node3D else Transform3D.IDENTITY
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
