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
## These tests pin: (1) the mask helper to the single tuning source of truth — guarding the off-by-one bit mistake
## (the carry code assigns `collision_layer = pickup_held_collision_layer` DIRECTLY, so the value is the raw bitmask
## to clear, NOT 1<<index); (2) the mask semantics; (3) the actual behaviour via an in-tree Perception query.

func test_helper_matches_tuning_source_of_truth() -> void:
	# If someone "corrects" the helper to 1<<(value-1) or 1<<value it would mask the WRONG layer — failing to hide
	# the held prop AND wrongly blinding sight to a different layer. This equality is the regression lock.
	assert_eq(TalkHelpers.held_prop_collision_layer(), GameSettings.physics_damage.pickup_held_collision_layer,
		"held_prop_collision_layer() must equal the tuning value it mirrors (raw bitmask, not a shifted index)")
	assert_gt(TalkHelpers.held_prop_collision_layer(), 0,
		"the held-prop layer bit must be a real (>0) physics layer to be maskable")


func test_sight_mask_clears_held_bit_but_keeps_world_and_characters() -> void:
	var held := TalkHelpers.held_prop_collision_layer()
	var mask := 0xFFFFFFFF & ~held
	assert_eq(mask & held, 0, "the sight mask clears the held-prop bit — a carried box is invisible to sight")
	assert_eq(mask & 1, 1, "the sight mask still sees world geometry (layer 1)")
	assert_eq(mask & 2, 2, "the sight mask still sees player / NPC bodies (layer 2)")
	assert_eq(mask & TalkHelpers.TALK_LAYER, TalkHelpers.TALK_LAYER,
		"the held mask alone leaves the talk layer intact — pet/claim combine ~TALK_LAYER separately")


# --- In-tree behaviour: Perception.can_see() must look THROUGH a held prop but NOT through a real wall ---

var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


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
