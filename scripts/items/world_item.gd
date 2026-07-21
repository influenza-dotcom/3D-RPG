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
##      behavior. Spawns ONE instance (a prop is a single object), but a stack of count>1 stamps that count
##      onto the prop's CanPickUp so E re-stashes the whole stack back — never silently loses the other N-1.
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
				_apply_item_metadata_to_prop(prop as Node3D, item)
				# The prop is ONE authored object no matter the count (a crate is a crate). But if a STACK of N is
				# dropped we must not silently destroy the other N-1: stamp the drop count onto the prop's CanPickUp
				# so E re-stashes the whole stack back. Mirrors _make_throwable's `cp.amount = amount`. Only override
				# when count > 1, so a normal single drop keeps the scene's AUTHORED amount (a prop that grants, say,
				# 5 on pickup stays 5). Scan DESCENDANTS (dogcrate.tscn nests its CanPickUp under Throwable) via `is`
				# iteration, not find_children's `type` filter (unreliable across Godot versions).
				if count > 1:
					for n in (prop as Node3D).find_children("*", "", true, false):
						if n is CanPickUp:
							(n as CanPickUp).amount = count
							break  # one prop, one primary pickup
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
		# A view_model whose ROOT bakes a first-person-only pose (the knife: FP scale 1.585 + a tilt + a 0.42/0.45
		# offset for the player's gun camera) sits ~0.6 m off its pickup box, oversized and mis-angled, when dropped
		# as-is. If the weapon declares an NPC hand-hold override, reuse it to reset the dropped model onto its box at
		# native scale (the same baked-FP-root correction npc.gd _build_weapon_mesh applies for the hand). A weapon
		# with a clean root (guns) sets no override, so its dropped model is untouched.
		if vm is Node3D and item.weapon.npc_hold_override:
			var vm3 := vm as Node3D
			vm3.position = item.weapon.npc_hold_position
			vm3.rotation_degrees = item.weapon.npc_hold_rotation
			vm3.scale = Vector3.ONE * item.weapon.npc_hold_scale
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


## Restore the runtime state a stashed prop captured onto its Item back onto the freshly-rebuilt scene, so a dropped
## dog keeps its SIZE, its COAT colour, and its BEFRIENDED state (name + follow + rim) instead of re-rolling into a
## different stray. DogPickup does the capture (SIZE_META / COAT_META / CLAIMED_* metas); here we push each onto the
## matching drop-in's preset field, which its _ready then applies. Meta absent => that field is left at its authored
## default (a hand-placed dog item just rolls a fresh coat and spawns unclaimed). One descendant pass sets all three.
static func _apply_item_metadata_to_prop(prop: Node3D, item: Item) -> void:
	if prop == null or item == null:
		return
	var size_mult := float(item.get_meta(RandomSize.SIZE_META)) if item.has_meta(RandomSize.SIZE_META) else -1.0
	var has_coat := item.has_meta(RandomCoat.COAT_META)
	var coat_tint: Color = item.get_meta(RandomCoat.COAT_META) if has_coat else Color(0.0, 0.0, 0.0, 0.0)
	var claimed := item.has_meta(Claimable.CLAIMED_META) and bool(item.get_meta(Claimable.CLAIMED_META))
	var claim_name := String(item.get_meta(Claimable.CLAIMED_NAME_META)) if item.has_meta(Claimable.CLAIMED_NAME_META) else ""
	for n in prop.find_children("*", "", true, false):
		if size_mult > 0.0 and n is RandomSize:
			(n as RandomSize).preset_scale_mult = size_mult
		elif has_coat and n is RandomCoat:
			(n as RandomCoat).preset_tint = coat_tint
		elif claimed and n is Claimable:
			(n as Claimable).preset_claimed = true
			(n as Claimable).preset_claim_name = claim_name
