extends GutTest

## Scene-wiring contract for merchant.tscn (Merchant) — a drop-in shop (a LookAtInteractable Area3D). Standalone
## (the default), the player's ray opens it only if it sits on the talk layer (collision_layer 16) with a
## CollisionShape3D child. This pins that authored structure + the runtime Stock inventory _ready builds.
##
## In-tree (add_child_autofree) for the runtime half — merchant._ready builds `stock` (a child CharacterInventory
## named "Stock") and seeds it; with the prefab's empty stock_counts the seed is a no-op, so _ready is safe.

const PREFAB := "res://scenes/components/merchant.tscn"


func test_prefab_is_a_merchant_on_the_talk_layer() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "merchant.tscn loads")
	if scene == null:
		return
	var m := scene.instantiate()  # authored properties set at instantiate, before _ready re-asserts them
	assert_true(m is Area3D, "the prefab root is an Area3D (the look-at hitbox)")
	assert_true(m is Merchant, "the root carries the Merchant script")
	assert_eq(m.collision_layer, TalkHelpers.TALK_LAYER, "authored on the talk layer so the interaction ray hits it")
	assert_eq(m.collision_mask, 0, "senses no bodies itself (mask 0)")
	m.free()


func test_prefab_has_a_collision_shape_child() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "merchant.tscn loads")
		return
	var m := scene.instantiate()
	var shape: CollisionShape3D = null
	for c in m.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
			break
	assert_not_null(shape, "the prefab has a CollisionShape3D child (the body you aim at to trade)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	m.free()


func test_ready_builds_the_stock_inventory() -> void:
	# The runtime half: _ready builds the shop's stock (a child CharacterInventory) that ShopScreen reads.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "merchant.tscn loads")
		return
	var m := scene.instantiate()
	assert_true(m.standalone, "the prefab ships as a standalone (direct-interact) merchant")
	add_child_autofree(m)
	assert_not_null(m.stock, "the merchant builds its Stock inventory in _ready (ShopScreen reads it)")
	assert_eq(m.collision_layer, TalkHelpers.TALK_LAYER, "a standalone merchant is armed on the talk layer")
