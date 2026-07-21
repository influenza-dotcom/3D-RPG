extends GutTest

## Scene-wiring contract for can_pick_up.tscn (CanPickUp) — a drop-in world PICKUP (a LookAtInteractable Area3D
## you place an Item on). The player's ray can only grab it by hitting a CollisionShape3D child; without one the
## pickup is un-aimable. Its `item` is left null in the bare prefab (assigned per-placement), so this test pins the
## authored STRUCTURE (root type + collider), not behaviour — the grant logic is covered by test_world_components.gd.
##
## Structural (no add_child): the required-child contract needs no _ready, and it keeps the test clear of the
## talk-hitbox setup.

const PREFAB := "res://scenes/components/can_pick_up.tscn"


func test_prefab_root_is_a_can_pick_up_area() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "can_pick_up.tscn loads")
	if scene == null:
		return
	var cp := scene.instantiate()
	assert_true(cp is Area3D, "the prefab root is an Area3D (the look-at hitbox)")
	assert_true(cp is CanPickUp, "the root carries the CanPickUp script")
	cp.free()


func test_prefab_has_a_collision_shape_child() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "can_pick_up.tscn loads")
		return
	var cp := scene.instantiate()
	var shape: CollisionShape3D = null
	for c in cp.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
			break
	assert_not_null(shape, "the prefab has a CollisionShape3D child (the body you aim at to pick it up)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	cp.free()
