extends GutTest

## Scene-wiring contract for healer.tscn (Healer) — a drop-in medic/heal-station (a LookAtInteractable Area3D).
## Standalone (the default), the ray opens the heal screen only if it sits on the talk layer with a
## CollisionShape3D child. This pins that authored structure + the talk-layer arming _ready performs.
##
## Complements the heal-cost logic tests. In-tree (add_child_autofree) so _ready runs; Healer._ready is harmless
## (auto_fit_collider off, so no off-tree transform math; it only sets layer/mask + builds an outline material).

const PREFAB := "res://scenes/components/healer.tscn"


func test_prefab_root_is_a_healer_area() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "healer.tscn loads")
	if scene == null:
		return
	var h := scene.instantiate()
	assert_true(h is Area3D, "the prefab root is an Area3D (the look-at hitbox)")
	assert_true(h is Healer, "the root carries the Healer script")
	h.free()


func test_prefab_has_a_collision_shape_child() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "healer.tscn loads")
		return
	var h := scene.instantiate()
	var shape: CollisionShape3D = null
	for c in h.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
			break
	assert_not_null(shape, "the prefab has a CollisionShape3D child (the body you aim at to heal)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	h.free()


func test_ready_arms_the_standalone_hitbox_on_the_talk_layer() -> void:
	# A standalone healer (the default) must sit on the talk layer so aiming + Interact opens the heal screen.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "healer.tscn loads")
		return
	var h := scene.instantiate()
	assert_true(h.standalone, "the prefab ships as a standalone (direct-interact) healer")
	add_child_autofree(h)
	assert_eq(h.collision_layer, TalkHelpers.TALK_LAYER, "a standalone healer is armed on the talk layer")
	assert_eq(h.collision_mask, 0, "it senses nothing itself (mask 0)")
	assert_true(h.has_method("start_talk"), "exposes start_talk (the interaction ray opens it)")
