extends GutTest

## Held props must not block LINE OF SIGHT. While a player carries a Throwable, PickupRay parks it on the held-prop
## collision layer (PhysicsDamageSettings.pickup_held_collision_layer) and floats it in front of the camera. A
## raycast ignores the carry collision EXCEPTION the player gets, so without masking that layer out a carried box
## would shield the player from being SEEN (perception) and block their look-at verbs (pet/claim/takedown) — i.e.
## turn invisible by holding a box up. The sight rays now `& ~TalkHelpers.held_prop_collision_layer()`.
##
## This is SIGHT/DETECTION only — line-of-FIRE rays (bullets, the NPC clear-shot test, grapple) intentionally keep
## seeing the held prop, so a carried prop stays solid physical cover.
##
## These tests pin: (1) the defensive read the per-frame sight rays rely on -- an unresolved tuning resource clears NO
## bit instead of throwing; (2) the actual behaviour via in-tree Perception queries: a prop on the held-prop layer is
## looked THROUGH, while a world wall and a character standing in the way still occlude. The raw-bitmask contract
## (the carry code assigns `collision_layer = pickup_held_collision_layer` DIRECTLY, so the helper must clear that
## value, NOT 1<<index) is proven by test_held_prop_does_not_block_sight, whose box sits on exactly that raw value.

var _root: Node3D
var _saved_physics_damage: PhysicsDamageSettings


func before_each() -> void:
	_saved_physics_damage = GameSettings.physics_damage
	_root = Node3D.new()
	add_child_autofree(_root)


func after_each() -> void:
	GameSettings.physics_damage = _saved_physics_damage


func test_held_layer_read_clears_no_bit_while_the_tuning_is_unresolved() -> void:
	# Sight rays call the helper every frame per NPC; a reimport / hot-reload can leave GameSettings.physics_damage
	# momentarily null. The read must degrade to "clear nothing" (the old maskless ray) and never throw mid-frame.
	assert_gt(TalkHelpers.held_prop_collision_layer(), 0,
		"control: with the tuning resolved the helper names a real layer bit for the sight rays to clear")
	GameSettings.physics_damage = null
	var during := TalkHelpers.held_prop_collision_layer()
	GameSettings.physics_damage = _saved_physics_damage
	assert_eq(during, 0,
		"with the physics tuning unresolved the helper must clear NO bit (never throw inside every NPC's per-frame sight ray)")


# --- In-tree behaviour: Perception.can_see() must look THROUGH a held prop but NOT through a real wall ---

## A Perception parented to a (shapeless) CharacterBody3D, mirroring a real NPC: front is +Z (the model convention
## can_see uses) and get_parent() is a CollisionObject3D, matching how perception.gd self-excludes.
func _make_perception() -> Perception:
	var owner := CharacterBody3D.new()
	owner.collision_layer = 2
	owner.collision_mask = 0
	_root.add_child(owner)
	owner.global_transform = Transform3D.IDENTITY
	var p := Perception.new()
	owner.add_child(p)
	p.transform = Transform3D.IDENTITY
	return p


## A solid 0.6 m box body at `pos` on `layer`, sized to span the horizontal sight ray at eye height.
func _make_body(pos: Vector3, layer: int) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	sb.add_child(shape)
	_root.add_child(sb)
	sb.global_position = pos
	return sb


func test_can_see_unobstructed_target() -> void:
	var p := _make_perception()
	var target := _make_body(Vector3(0, p.eye_height, 2), 2)  # player layer, dead ahead at eye height
	p.target = target
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(p.can_see(), "a clear, in-cone, in-range target is seen (the test geometry is valid)")


func test_held_prop_does_not_block_sight() -> void:
	var p := _make_perception()
	var target := _make_body(Vector3(0, p.eye_height, 2), 2)
	p.target = target
	# A carried box on the held-prop layer, interposed between the eye and the target.
	_make_body(Vector3(0, p.eye_height, 1), GameSettings.physics_damage.pickup_held_collision_layer)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(p.can_see(),
		"a prop on the held-prop layer between eye and target must NOT block sight — no invisibility-by-box")


func test_real_wall_still_blocks_sight() -> void:
	var p := _make_perception()
	var target := _make_body(Vector3(0, p.eye_height, 2), 2)
	p.target = target
	_make_body(Vector3(0, p.eye_height, 1), 1)  # a genuine world-layer wall between us
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(p.can_see(),
		"a solid world-layer body between eye and target still occludes — the held mask must not over-block")


func test_only_the_held_prop_bit_is_see_through_a_character_in_the_way_still_blocks_sight() -> void:
	# The held-prop layer must be its OWN single bit: the carry code assigns it as the prop's whole collision_layer,
	# and every sight ray clears it. Tuned onto the character layer (2), NPCs would see straight through bodies;
	# onto the world layer (1), through walls (test_real_wall_still_blocks_sight); onto the talk layer, the look-at
	# verbs that already clear TALK_LAYER would stop telling a carried prop from a talk volume.
	var held := TalkHelpers.held_prop_collision_layer()
	assert_true(held > 0 and (held & (held - 1)) == 0,
		"pickup_held_collision_layer must be exactly ONE physics layer bit (got %d)" % held)
	assert_eq(held & (1 | 2 | TalkHelpers.TALK_LAYER), 0,
		"the held-prop layer must not share a bit with world (1), characters (2) or the talk layer (%d); got %d" % [TalkHelpers.TALK_LAYER, held])
	var p := _make_perception()
	var target := _make_body(Vector3(0, p.eye_height, 2), 2)
	p.target = target
	_make_body(Vector3(0, p.eye_height, 1), 2)  # another character standing between the eye and the target
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(p.can_see(),
		"a character body between eye and target still occludes -- only a CARRIED prop is see-through, not everyone on the character layer")
