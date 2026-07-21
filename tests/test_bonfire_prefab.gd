extends GutTest

## Scene-wiring contract for bonfire.tscn (Bonfire) — a drop-in checkpoint/rest station (a LookAtInteractable
## Area3D). Standalone (the default), it's a look-at hitbox: the ray opens it only if it sits on the talk layer
## with a CollisionShape3D child. This pins that authored structure + the talk-layer arming _ready performs.
##
## Complements test_bonfire.gd (which covers the rest()/respawn behaviour). In-tree (add_child_autofree) so
## _ready runs; Bonfire._ready is harmless (auto_fit_collider off, so no off-tree transform math).

const PREFAB := "res://scenes/components/bonfire.tscn"


func test_prefab_root_is_a_bonfire_area() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "bonfire.tscn loads")
	if scene == null:
		return
	var b := scene.instantiate()
	assert_true(b is Area3D, "the prefab root is an Area3D (the look-at hitbox)")
	assert_true(b is Bonfire, "the root carries the Bonfire script")
	b.free()


func test_prefab_has_a_collision_shape_child() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "bonfire.tscn loads")
		return
	var b := scene.instantiate()
	var shape: CollisionShape3D = null
	for c in b.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
			break
	assert_not_null(shape, "the prefab has a CollisionShape3D child (the body you aim at to rest)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	b.free()


func test_ready_arms_the_standalone_hitbox_on_the_talk_layer() -> void:
	# A standalone bonfire (the default) must sit on the talk layer so aiming + Interact opens it directly.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "bonfire.tscn loads")
		return
	var b := scene.instantiate()
	assert_true(b.standalone, "the prefab ships as a standalone (direct-interact) bonfire")
	add_child_autofree(b)
	assert_eq(b.collision_layer, TalkHelpers.TALK_LAYER, "a standalone bonfire is armed on the talk layer")
	assert_eq(b.collision_mask, 0, "it senses nothing itself (mask 0)")
	assert_true(b.has_method("start_talk"), "exposes start_talk (the interaction ray opens it)")
