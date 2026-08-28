extends GutTest

## Build-time contract for WORLD weapon drops (WorldItem.build -> _make_throwable). A set of traits is stamped onto the
## dropped weapon's Throwable at BUILD time (not in _ready), so a weapon you take in hand (H) and throw behaves right:
##   • destructible == false — a stray shot / hard impact can't shatter a dropped gun or knife ("weapons can't be
##     destroyed by impact damage").
##   • impact_damage_mult == WeaponData.thrown_impact_damage_mult — the final "hits harder thrown" multiplier,
##     applied on both damage paths.
##   • thrown_weapon == the WeaponData itself, but ONLY when it sets thrown_uses_weapon_damage. That switches a
##     thrown hit from the speed-based prop bludgeon to a real weapon hit (weapon damage + headshot multiplier +
##     stat scaling + located limb damage). It must stay null for a weapon that doesn't opt in, or a thrown PISTOL
##     would deal its BULLET damage as a bludgeon.
##   • throw_impulse_mult == WeaponData.thrown_impulse_mult — how fast a real throw launches it, and (above 1.0)
##     continuous_cd so a fast slender body can't tunnel through thin geometry between physics ticks.
##   • throw_sound == WeaponData.thrown_sound — the signature throw whip, played instead of the release sound.
##   • face_travel_when_thrown == WeaponData.thrown_faces_travel — a thrown knife noses toward its travel direction.
##   • face_carrier_rotation_degrees == WeaponData.thrown_face_rotation_degrees — the mesh-front correction, which
##     Throwable shares between the thrown facing and the CARRY pose...
##   • face_carrier_while_held + face_carrier_reversed == WeaponData.held_faces_aim — ...and THIS is what decides
##     whether the carry pose runs at all. ONE weapon flag drives BOTH, because a weapon has exactly one sensible
##     carry pose: the dog's face-carrier machinery REVERSED, so the blade points AWAY down your aim (held ready to
##     throw) rather than back at your face. ON for every weapon by default; the pose follows the FULL look
##     including pitch, so it lies along the throw it is about to make.
##   • the drop's CanPickUp gets item_light_always_lit == WeaponData.dropped_item_light_always_lit, so a carried /
##     in-flight weapon keeps its red item light instead of being faded out by the ground-loot near-distance ramp.
## Plus the drop's SHAPE, which the thrown facing makes load-bearing (it pins local +Z along travel, so a badly
## seated model becomes a wobbling pivot arm and a mis-shaped box sits broadside to every throw):
##   • the posed Visual's bounds are CENTRED on the body origin (dropped_model_offset trims the residual). Asserted
##     as the real geometric invariant, NOT as "position == npc_hold_position + dropped_model_offset" — that form is
##     tautological (it recomputes the production line) and passes for ANY authored value, including a wrong one.
##   • the collider matches dropped_collision_size when the weapon authors one.
## Verified OFF-TREE: WorldItem.build is a static func and sets these directly on the node, so we never add_child /
## run Throwable._ready (which would auto-fit the collider + start audio). The knife item routes through build()
## case 3 (weapon view_model), so the result is a Throwable. Every expectation is read back off the RESOURCE rather
## than hardcoded, so re-tuning melee.tres never breaks this test.

const WorldItemScript := preload("res://scripts/items/world_item.gd")
const KNIFE_ITEM := "res://resources/items/melee_item.tres"
## How far the posed model's bounds centre may sit from the body origin (m). Generous — this guards against a
## seating blunder (a tenth of a metre or more), not against a few mm of authoring slack.
const CENTRE_TOLERANCE := 0.05


## Bounds of every MeshInstance3D under `node`, expressed in the DROP's local space — the same walk
## Throwable._collect_visual_aabb does. Returns an empty dictionary when nothing renders.
func _visual_bounds(node: Node, xf: Transform3D, state: Dictionary) -> Dictionary:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var box := xf * mi.mesh.get_aabb()
			state["aabb"] = box if not state.has("aabb") else (state["aabb"] as AABB).merge(box)
	for child in node.get_children():
		var child_xf := xf
		if child is Node3D:
			child_xf = xf * (child as Node3D).transform
		_visual_bounds(child, child_xf, state)
	return state


func test_dropped_weapon_is_indestructible_and_carries_its_thrown_mult() -> void:
	var item := load(KNIFE_ITEM) as Item
	assert_not_null(item, "the knife Item resource loads")
	if item == null:
		return
	assert_true(item.is_weapon(), "melee_item.tres is a WEAPON-category item carrying a WeaponData")

	var drop := WorldItemScript.build(item, 1)
	assert_true(drop is Throwable, "a dropped weapon builds a Throwable (build() case 3, weapon view_model)")
	if not (drop is Throwable):
		if is_instance_valid(drop):
			drop.free()
		return
	var t := drop as Throwable

	assert_false(t.is_destructible(), "a dropped weapon is indestructible — a shot / hard impact can't break it")
	assert_eq(t.impact_damage_mult, item.weapon.thrown_impact_damage_mult,
		"the WeaponData.thrown_impact_damage_mult is stamped onto the drop's Throwable.impact_damage_mult")
	# The weapon-damage opt-in, asserted BOTH ways so neither direction can drift: opted in -> the drop carries the
	# very same WeaponData resource (not a copy, so re-tuning melee.tres retunes the throw); opted out -> null, and
	# the drop keeps the blunt speed formula.
	if item.weapon.thrown_uses_weapon_damage:
		assert_eq(t.thrown_weapon, item.weapon,
			"a weapon opting into thrown_uses_weapon_damage stamps ITSELF onto the drop's Throwable.thrown_weapon")
	else:
		assert_null(t.thrown_weapon,
			"a weapon that doesn't opt in leaves thrown_weapon null, keeping the speed-based prop bludgeon")
	assert_eq(t.face_travel_when_thrown, item.weapon.thrown_faces_travel,
		"WeaponData.thrown_faces_travel is stamped onto the drop's Throwable.face_travel_when_thrown")
	assert_eq(t.face_carrier_rotation_degrees, item.weapon.thrown_face_rotation_degrees,
		"WeaponData.thrown_face_rotation_degrees is stamped onto the drop's Throwable.face_carrier_rotation_degrees")
	assert_eq(t.throw_impulse_mult, item.weapon.thrown_impulse_mult,
		"WeaponData.thrown_impulse_mult is stamped onto the drop's Throwable.throw_impulse_mult (the launch speed)")
	assert_eq(t.throw_sound, item.weapon.thrown_sound,
		"WeaponData.thrown_sound is stamped onto the drop's Throwable.throw_sound (played instead of the drop sound)")
	# A weapon tuned to fly fast MUST sweep its motion: the knife covers more than its own collider length per 60 Hz
	# tick, so discrete stepping can put it clean through a wall panel between two ticks.
	assert_eq(t.continuous_cd, item.weapon.thrown_impulse_mult > 1.0,
		"a drop opting into a faster-than-normal throw gets continuous collision detection (and only then)")
	# The mesh-front correction becomes a CARRY pose only when the weapon opts in: face_carrier() is gated on this
	# predicate. Every weapon opts in by default (see tests/test_weapon_data_completeness.gd for the roster pin);
	# read back off the resource here so turning it off on one weapon still checks the stamp rather than the value.
	assert_eq(t.faces_carrier_while_held(), item.weapon.held_faces_aim,
		"WeaponData.held_faces_aim is what turns the carry pose on — the thrown rotation alone can't")
	# ...and it must be the REVERSED pose. Both flags come off the one weapon field, so they can never disagree: a
	# weapon posed like the DOG would hold the knife blade-first at the player's own face.
	assert_eq(t.faces_carrier_reversed(), item.weapon.held_faces_aim,
		"a weapon's carry pose is the REVERSED one — business end down your aim, not nosed back at you")
	var pickup := t.get_node_or_null(^"CanPickUp") as CanPickUp
	assert_not_null(pickup, "the drop wraps a CanPickUp so E stashes it back")
	if pickup != null:
		assert_eq(pickup.item_light_always_lit, item.weapon.dropped_item_light_always_lit,
			"WeaponData.dropped_item_light_always_lit is stamped onto the drop's CanPickUp, so a carried / thrown weapon keeps its glow")
	var visual := t.get_node_or_null(^"Visual") as Node3D
	assert_not_null(visual, "the drop wraps the weapon's view model in a 'Visual' child")
	if visual != null:
		# THE invariant dropped_model_offset exists to hold: the posed model's bounds are centred on the body origin,
		# which is the point the thrown facing spins the prop about. Measured from the real mesh AABBs, so a wrong
		# authored offset FAILS here (a tautological "position == the sum we just added" check would not).
		var state := _visual_bounds(visual, visual.transform, {})
		assert_true(state.has("aabb"), "the dropped weapon model has renderable bounds to centre")
		if state.has("aabb"):
			var centre := (state["aabb"] as AABB).get_center()
			assert_lt(centre.length(), CENTRE_TOLERANCE,
				"the posed model is centred on the drop's origin (offset by %s, %.3f m out) — else the thrown facing pivots on an arm and it wobbles instead of nosing" % [item.weapon.dropped_model_offset, centre.length()])
	# A weapon that authors a collider gets it (the default slab is broadside to a nosing throw).
	if item.weapon.dropped_collision_size != Vector3.ZERO:
		var box := t.collision_shape.shape as BoxShape3D
		assert_not_null(box, "the drop's collider is a BoxShape3D")
		if box != null:
			assert_eq(box.size, item.weapon.dropped_collision_size,
				"WeaponData.dropped_collision_size sizes the drop's collision box")

	drop.free()


func test_non_weapon_drop_stays_destructible_and_unboosted() -> void:
	# Guard the scope: only WEAPONS get the two traits. A plain MISC item with a world_model must keep the Throwable
	# defaults (destructible true, mult 1.0), so the stamp can't leak onto crates / loot.
	var item := Item.new()
	item.category = Item.Category.MISC
	item.display_name = "Test Rock"
	var mesh := BoxMesh.new()
	item.world_model = mesh
	assert_false(item.is_weapon(), "the test MISC item is not a weapon")

	var drop := WorldItemScript.build(item, 1)
	assert_true(drop is Throwable, "a world_model MISC item builds a Throwable (build() case 2)")
	if drop is Throwable:
		var t := drop as Throwable
		assert_true(t.is_destructible(), "a non-weapon drop keeps its destructible default")
		assert_eq(t.impact_damage_mult, 1.0, "a non-weapon drop keeps the 1.0 impact multiplier")
		assert_null(t.thrown_weapon, "a non-weapon drop has no weapon to hit like — it keeps the blunt speed formula")
		assert_eq(t.throw_impulse_mult, 1.0, "a non-weapon drop throws at the normal speed (no launch multiplier)")
		assert_false(t.continuous_cd, "a non-weapon drop keeps the cheaper discrete solver")
		assert_null(t.throw_sound, "a non-weapon drop authors no dedicated throw sound")
		assert_false(t.face_travel_when_thrown, "the thrown-facing stamp can't leak onto crates / loot")
		assert_false(t.faces_carrier_while_held(), "the carry-pose stamp can't leak onto crates / loot")
		assert_false(t.faces_carrier_reversed(), "the reversed-carry stamp can't leak onto crates / loot")
		var pickup := t.get_node_or_null(^"CanPickUp") as CanPickUp
		if pickup != null:
			assert_false(pickup.item_light_always_lit,
				"ordinary loot keeps the ground-pickup distance fade — only a carried/thrown weapon stays always-lit")
	if is_instance_valid(drop):
		drop.free()
	item = null
	mesh = null
