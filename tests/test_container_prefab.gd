extends GutTest

## Scene-wiring contract for container.tscn (ItemContainer) — a persistent, lootable drop-in crate/chest.
## It's an Area3D interaction hitbox: the player's ray can only open it by hitting a CollisionShape3D child while
## the Area3D sits on the talk layer (collision_layer 16 == TalkHelpers.TALK_LAYER). A designer who deletes the
## collider, detaches the script, or changes the layer breaks the container silently — this pins that seam.
##
## In-tree (add_child_autofree) for the runtime half: ItemContainer._ready is proven safe in-tree by
## test_world_components.gd (test_container_seeds_unique_weapon_in_tree); with the prefab's bare defaults
## (empty item_stacks, money 0, no loot_table) seeding is a no-op that never touches ItemDb.

const PREFAB := "res://scenes/components/container.tscn"


func test_prefab_is_an_item_container_on_the_talk_layer() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "container.tscn loads")
	if scene == null:
		return
	var c := scene.instantiate()  # authored properties are set at instantiate, before _ready re-asserts them
	assert_true(c is Area3D, "the prefab root is an Area3D (the look-at interaction hitbox)")
	assert_true(c is ItemContainer, "the root carries the ItemContainer script")
	assert_eq(c.collision_layer, TalkHelpers.TALK_LAYER, "authored on the talk layer so the interaction ray hits it")
	assert_eq(c.collision_mask, 0, "senses no bodies itself (mask 0 — it's aimed at, it doesn't monitor)")
	c.free()


func test_prefab_has_a_collision_shape_child() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "container.tscn loads")
		return
	var c := scene.instantiate()
	var shape: CollisionShape3D = null
	for ch in c.get_children():
		if ch is CollisionShape3D:
			shape = ch as CollisionShape3D
			break
	assert_not_null(shape, "the prefab has a CollisionShape3D child (the body you aim at to open it)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	c.free()


func test_ready_builds_the_contents_inventory_and_joins_group() -> void:
	# The runtime half of the contract: _ready builds a child CharacterInventory (`inventory`) and joins the
	# &"containers" group so NpcScavenge can raid it. Pinned in-tree with the safe, bare-default _ready.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "container.tscn loads")
		return
	var c := scene.instantiate()
	add_child_autofree(c)
	assert_not_null(c.inventory, "the container builds its own Contents inventory in _ready")
	assert_true(c.is_in_group(&"containers"), "the container joins the &\"containers\" group so NPCs can find it")
