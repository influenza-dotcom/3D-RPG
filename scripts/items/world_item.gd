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
	# held_view_model() skips a FIRST-PERSON-only rig (the bare hands): dropping fists would otherwise litter
	# the floor with a pair of floating forearms. Falls through to the generic pickup box instead.
	var held_vm: PackedScene = item.weapon.held_view_model() if (item != null and item.is_weapon() and item.weapon != null) else null
	if held_vm != null:
		var vm := held_vm.instantiate()  # the actual weapon model
		_make_world_renderable(vm)  # FP view models draw on the gun layer / no-depth -> would show through walls
		# A view_model whose ROOT bakes a first-person-only pose (the knife: FP scale 1.585 + a tilt + a 0.42/0.45
		# offset for the player's gun camera) sits ~0.6 m off its pickup box, oversized and mis-angled, when dropped
		# as-is. If the weapon declares an NPC hand-hold override, reuse it to reset the dropped model onto its box at
		# native scale (the same baked-FP-root correction npc.gd _build_weapon_mesh applies for the hand). A weapon
		# with a clean root (guns) sets no override, so its dropped model is untouched.
		if vm is Node3D and item.weapon.npc_hold_override:
			var vm3 := vm as Node3D
			# dropped_model_offset is a FINE re-centring of the posed model on the body origin, applied ONLY here (the
			# NPC hand mount and the FP rig never read it, so a drop can be nudged without disturbing either pose).
			# It matters because the thrown facing rotates the BODY about its own origin: any residual offset becomes
			# the spin's pivot arm, so a model whose posed bounds aren't centred wobbles instead of nosing cleanly.
			# The knife's own re-pose already lands within a few cm (its GLB nodes carry a +44.33 translation that
			# knife.tscn's -0.4285 child origin exists to cancel), so its value is a small trim, NOT a big correction.
			# Zero for every weapon that doesn't need it.
			vm3.position = item.weapon.npc_hold_position + item.weapon.dropped_model_offset
			vm3.rotation_degrees = item.weapon.npc_hold_rotation
			vm3.scale = Vector3.ONE * item.weapon.npc_hold_scale
		# Collider: the shared default is a chunky 0.7 x 0.3 x 0.3 slab sized for a gun lying flat. Once a weapon NOSES
		# when thrown (thrown_faces_travel) that box stops being a harmless approximation — the facing pins local +Z
		# along travel, so the 0.7 axis is DETERMINISTICALLY broadside to flight on every throw, and a thrown knife
		# would clip geometry a third of a metre to its side while its tip pokes out the front. dropped_collision_size
		# lets such a weapon author a box that matches its posed model; ZERO (every other weapon) keeps the default,
		# and the pickup hitbox keeps its "slightly larger, easy to aim at" margin either way.
		var body_size := Vector3(0.7, 0.3, 0.3)
		if item.weapon.dropped_collision_size != Vector3.ZERO:
			body_size = item.weapon.dropped_collision_size
		return _make_throwable(item, 1, vm, body_size, body_size + Vector3(0.2, 0.3, 0.3))
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
	# WEAPON drops get a set of special traits, stamped HERE because every weapon reaches this builder via build() cases
	# 2/3/4 (a weapon never uses a `world_prop`, which is case 1's early return — verified: only the dog/crate do).
	# Set on the node BEFORE it enters the tree; Throwable._ready never touches any of these fields, so they survive.
	# (The item-light flag lands on the CanPickUp instead, and MUST be set before it enters the tree for a different
	# reason: CanPickUp._ready is what spawns the PickupBeacon and reads the flag to build it.)
	#   • destructible = false — a dropped gun/knife can't be shot apart or shattered by a hard impact (take_damage
	#     no-ops while off). "Weapons can't be destroyed by impact damage."
	#   • impact_damage_mult ← weapon.thrown_impact_damage_mult — a final "hits harder thrown" multiplier, applied on
	#     both damage paths. is_weapon() guarantees weapon != null.
	#   • thrown_weapon ← the WeaponData ITSELF, but only when it opts in via thrown_uses_weapon_damage. That switches
	#     the hit from the generic speed-based prop bludgeon to a real weapon hit (weapon damage + headshot multiplier
	#     + stat scaling + located limb damage). Null for a gun, which keeps the blunt formula. The opt-in matters:
	#     stamping it unconditionally would make a thrown PISTOL deal its BULLET damage as a bludgeon.
	#   • pins_body_part ← weapon.thrown_pins_body_part — a LETHAL thrown hit staples the struck body part to the wall
	#     behind, blade embedded (GoreSpawner._resolve_pin). Rides on the thrown_weapon path above for its located
	#     contact point, so a weapon that sets it without thrown_uses_weapon_damage simply never pins.
	#   • sticks_in_body ← weapon.thrown_sticks_in_body — a SURVIVED thrown hit leaves the drop embedded in the body
	#     part it struck, riding that part (Throwable.stick_in_body). The far side of the same kill line as
	#     pins_body_part above, and it rides the same thrown_weapon path for its located contact point, so a weapon
	#     that sets it without thrown_uses_weapon_damage simply never sticks.
	#   • throw_impulse_mult ← weapon.thrown_impulse_mult — how fast a real throw launches it (the knife is HURLED,
	#     a gun is tossed). See the continuous_cd note below.
	#   • throw_sound ← weapon.thrown_sound — a signature throw sound, played instead of the drop's release sound.
	#   • face_travel_when_thrown / face_carrier_rotation_degrees ← weapon.thrown_faces_travel /
	#     thrown_face_rotation_degrees — a THROWN weapon that opts in noses toward its travel direction (the knife
	#     leads with its point; guns leave it off and tumble). The rotation is the mesh-front correction, applied
	#     inside BOTH aim bases — Throwable._integrate_forces' thrown facing and face_carrier's carry pose. It
	#     defaults to Y=+90, the barrel-is-+X convention every gun model here follows, so it is authored per weapon
	#     only by a model that breaks it (the knife's blade is -X, hence its 180).
	#   • a ThrowTrail CHILD ← weapon.thrown_trail / thrown_trail_color — the white streak the drop drags while it
	#     flies. ON for EVERY weapon (thrown_trail defaults true), so this branch is the common case, not the knife's
	#     special case; the flag stays a per-weapon OPT-OUT for a throw that shouldn't be readable. The only stamp
	#     here that adds a NODE rather than setting a field, because the effect is a drop-in component (a hand-placed
	#     prop gets one by dragging it into the scene). Loaded by PATH, not by its ThrowTrail class_name: this builder
	#     already reaches Throwable.gd that way, and the component's host is duck-typed for the same reason (no
	#     class_name edge into the actor parse path). The child is added at the body's ORIGIN with no offset, which is
	#     what lets a TUMBLING drop (every gun — thrown_faces_travel is off) still lay a smooth line instead of a
	#     corkscrew: the sample point doesn't orbit as the body spins. A weapon that wants the streak to leave a
	#     specific point (a blade tip) authors a hand-placed ThrowTrail in a world_prop scene instead.
	#   • face_carrier_while_held + face_carrier_reversed ← weapon.held_faces_aim — and THAT is what decides whether
	#     the same rotation also poses the drop while it's CARRIED. ONE weapon flag sets BOTH Throwable fields because
	#     a weapon has only one sensible carry pose: the dog's face-carrier machinery, REVERSED, so the business end
	#     points AWAY down your aim (held ready to throw) instead of back at your face. ON for EVERY weapon by
	#     default — like the trail above, this is the common case and not the knife's special case: a weapon in your
	#     hands that ignores where you are looking reads as a bug whether the look is sideways or pitched. The pose
	#     tracks the FULL look including pitch (Throwable.face_carrier), which is the same vector PickupRay._release
	#     throws along, so what is in your hands lies along the throw it is about to make.
	if item != null and item.is_weapon():
		t.destructible = false
		t.impact_damage_mult = item.weapon.thrown_impact_damage_mult
		t.thrown_weapon = item.weapon if item.weapon.thrown_uses_weapon_damage else null
		t.pins_body_part = item.weapon.thrown_pins_body_part
		t.sticks_in_body = item.weapon.thrown_sticks_in_body
		t.throw_impulse_mult = item.weapon.thrown_impulse_mult
		t.throw_sound = item.weapon.thrown_sound
		t.face_travel_when_thrown = item.weapon.thrown_faces_travel
		t.face_carrier_rotation_degrees = item.weapon.thrown_face_rotation_degrees
		t.face_carrier_while_held = item.weapon.held_faces_aim
		t.face_carrier_reversed = item.weapon.held_faces_aim
		cp.item_light_always_lit = item.weapon.dropped_item_light_always_lit
		if item.weapon.thrown_trail:
			# Plain `var`, not `:=` — a load().new() chain is Variant and inference off it is an analyzer error.
			var trail = load("res://scripts/components/throw_trail.gd").new()
			trail.name = "ThrowTrail"
			trail.color = item.weapon.thrown_trail_color
			t.add_child(trail)
		# Continuous collision detection for a weapon tuned to fly FAST. The release sets linear_velocity directly, so
		# thrown_impulse_mult scales metres-per-second one-for-one: at the default 12 m/s a 60 Hz tick moves the body
		# 0.2 m, but a 2.5x knife covers 0.5 m — more than the length of its own 0.46 m collider — and discrete
		# stepping can put it clean through a wall/door panel between two ticks. Godot's continuous_cd sweeps the
		# motion instead. Gated on the OPT-IN (> 1.0) so every ordinary drop keeps the cheaper discrete solver.
		if item.weapon.thrown_impulse_mult > 1.0:
			t.continuous_cd = true
	return t


## Make an instanced first-person VIEW MODEL render like a normal world object: FP guns live on the view-model
## render layer (4), drawn on top by a dedicated camera with no-depth materials -- so dropped as-is they'd draw
## THROUGH walls. Move every VISIBLE mesh to the world layer (1) and turn no_depth_test off so it depth-tests
## geometry. InkOutline's tint duplicates are the one exception -- see the skip below.
static func _make_world_renderable(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# InkOutline's invisible tint duplicate (meta &"npc_tint_dup", parented under a visible mesh by NpcOutline /
		# Throwable) must KEEP its ACTOR_TINT_LAYER bit and nothing else: layer 1 is the MAIN camera, and it would
		# then DRAW ink_tint.gdshader's raw R/G log-depth bytes as moving yellow/green stripe bands over the dropped
		# weapon -- the failure reported 2026-08-25 (see scripts/effects/body_part_gib.gd:186). A duplicate has no
		# children, so returning here skips nothing else.
		if mi.has_meta(&"npc_tint_dup"):
			return
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
