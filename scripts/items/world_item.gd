class_name WorldItem
extends RefCounted

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## The world object a dropped OR hand-placed Item becomes. By default a Throwable (physics -- it falls, is
## shootable, and is carried/thrown with Z via PickupRay) wrapping a CanPickUp child (E stashes it back into the
## inventory). An item can instead carry an authored `world_prop` scene that is spawned AS-IS, so a prop with its
## OWN behavior (a destructible dog crate that spawns a dog on break) survives the round-trip. ONE canonical
## builder so an inventory drop (Player.drop_item) and the editor item-placer produce IDENTICAL objects.
## Positioning is the caller's job (the drop puts it in front of the player; the placer in front of the camera).


## Build the world object for `item` (x`count` for stackables). Precedence:
##   1. `item.world_prop` -- an authored full PROP scene, spawned AS-IS so it keeps its OWN behavior
##      (destructible, spawn-on-destroy, custom ThrowableData). The go-to for any throwable with unique
##      behavior. Spawns ONE instance regardless of count (a prop is a single object).
##   2. `item.world_model` -- a plain visual model resource, wrapped in the default Throwable + CanPickUp shell.
##   3. a WEAPON's first-person view model, moved to the world render layer so it doesn't draw through walls.
##   4. else a small placeholder box.
## Returns a Node3D: usually a Throwable, but a world_prop scene may root any Node3D (e.g. dogcrate.tscn roots a
## Node3D that WRAPS the Throwable). Callers only add it to the world + set its position, so a plain Node3D is fine.
static func build(item: Item, count: int = 1) -> Node3D:
	# 1. Authored prop scene wins -- designer intent. Spawn the real object so its destructible / spawn-on-destroy /
	# custom-data behavior survives a drop. world_prop is a PATH (not a PackedScene ref) so the prop's CanPickUp can
	# point back at this item without a load-time cycle; we load() it lazily here, by when this item is loaded. A
	# missing scene or a non-Node3D root is discarded (fail-safe) and we fall through to the placeholder.
	if item != null and not item.world_prop.is_empty():
		var ps := load(item.world_prop) as PackedScene
		if ps != null:
			var prop := ps.instantiate()
			if prop is Node3D:
				return prop as Node3D
			if prop is Node:
				(prop as Node).queue_free()
	# 2. A plain item world model shows as the default carry/throw/stash shell.
	if item != null and item.world_model != null:
		var world_visual: Node3D = ModelResourceUtil.instantiate(item.world_model, "Visual")
		if world_visual != null:
			return _make_throwable(item, maxi(1, count), world_visual, Vector3(0.35, 0.35, 0.35), Vector3(0.5, 0.5, 0.5))
	# 3. A weapon with no dedicated world model falls back to its first-person view model.
	if item != null and item.is_weapon() and item.weapon != null and item.weapon.view_model != null:
		var vm := item.weapon.view_model.instantiate()  # the actual weapon model
		_make_world_renderable(vm)  # FP view models draw on the gun layer / no-depth -> would show through walls
		return _make_throwable(item, 1, vm, Vector3(0.7, 0.3, 0.3), Vector3(0.9, 0.6, 0.6))
	# 4. Everything else: a small placeholder box. Assign `world_model` for a real look or `world_prop` for real behavior.
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.3, 0.3)
	mesh.mesh = bm
	return _make_throwable(item, maxi(1, count), mesh, Vector3(0.35, 0.35, 0.35), Vector3(0.5, 0.5, 0.5))


## A Throwable wrapping `visual`, with a body collision box (`body_size`) so it falls and is shootable / carry-
## throwable, plus a CanPickUp child carrying `item` x`amount` on its OWN talk-layer hitbox (`pickup_size`) so E
## stashes it. The CanPickUp's host is the Throwable, so E frees the whole drop and the visual highlights on hover;
## the separate hitbox is what lets the look-at ray pick E (stash) over the Throwable's Z (carry/throw).
static func _make_throwable(item: Item, amount: int, visual: Node, body_size: Vector3, pickup_size: Vector3) -> Throwable:
	var t: Throwable = load("res://scripts/components/Throwable.gd").new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = body_size
	shape.shape = box
	t.add_child(shape)
	t.collision_shape = shape  # PickupRay carry reads Throwable.collision_shape
	visual.name = "Visual"
	t.add_child(visual)
	var cp := CanPickUp.new()
	cp.name = "CanPickUp"
	cp.item = item
	cp.amount = amount
	cp.highlight_target = t  # E adds to inventory; outlines the dropped model on hover
	# The CanPickUp needs its OWN hitbox on the talk layer, or the look-at ray can't see it -- without this E falls
	# through to the Throwable grab instead of stashing. Slightly larger so it's easy to aim at.
	var cp_shape := CollisionShape3D.new()
	var cp_box := BoxShape3D.new()
	cp_box.size = pickup_size
	cp_shape.shape = cp_box
	cp.add_child(cp_shape)
	t.add_child(cp)
	return t


## Make an instanced first-person VIEW MODEL render like a normal world object: FP guns live on the view-model
## render layer (4), drawn on top by a dedicated camera with no-depth materials -- so dropped as-is they'd draw
## THROUGH walls. Move every mesh to the world layer (1) and turn no_depth_test off so it depth-tests geometry.
static func _make_world_renderable(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.layers = 1
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D and (mat as BaseMaterial3D).no_depth_test:
					var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					m.no_depth_test = false
					mi.set_surface_override_material(i, m)
	for child in node.get_children():
		_make_world_renderable(child)
