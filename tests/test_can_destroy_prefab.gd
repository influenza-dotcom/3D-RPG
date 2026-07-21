extends GutTest

## Scene-wiring contract for can_destroy.tscn (CanDestroy) — a drop-in DESTRUCTIBLE prop. It's a StaticBody3D so a
## shot can hit it: that requires a CollisionShape3D child (the hurt/hit body) and a MeshInstance3D (the thing that
## visibly breaks). This pins that authored structure; the HP/destroy logic is covered off-tree by
## test_world_components.gd.
##
## Structural (no add_child): the required-child contract needs no _ready.

const PREFAB := "res://scenes/components/can_destroy.tscn"


func test_prefab_root_is_a_can_destroy_body() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "can_destroy.tscn loads")
	if scene == null:
		return
	var cd := scene.instantiate()
	assert_true(cd is StaticBody3D, "the prefab root is a StaticBody3D (so a shot's raycast can hit it)")
	assert_true(cd is CanDestroy, "the root carries the CanDestroy script")
	cd.free()


func test_prefab_has_collider_and_mesh_children() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "can_destroy.tscn loads")
		return
	var cd := scene.instantiate()
	var shape: CollisionShape3D = null
	var has_mesh := false
	for c in cd.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
		elif c is MeshInstance3D:
			has_mesh = true
	assert_not_null(shape, "the prefab has a CollisionShape3D child (the body a shot must hit to damage it)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	assert_true(has_mesh, "the prefab has a MeshInstance3D child (the visible prop that breaks)")
	cd.free()
