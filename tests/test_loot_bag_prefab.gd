extends GutTest

## Scene-wiring contract for loot_bag.tscn (LootBag, a Throwable subclass) — the RigidBody3D bag that drops when
## loot spills. Like its Throwable base it wires three refs (node_paths): `collision_shape`, `mesh_instance`,
## `impact_sfx`. It also ships `destructible = false` on purpose — a stray shot must NOT destroy dropped loot — so
## this pins that authored flag alongside the child wiring.
##
## Verified STRUCTURALLY, WITHOUT add_child (it's a RigidBody + Throwable._ready auto-fits/pushes data): resolve
## each wired NodePath against the instantiated subtree and assert its type.

const PREFAB := "res://scenes/props/loot_bag.tscn"


func test_prefab_root_is_an_indestructible_loot_bag() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "loot_bag.tscn loads")
	if scene == null:
		return
	var lb := scene.instantiate()  # authored `destructible` is set at instantiate, before any _ready
	assert_true(lb is RigidBody3D, "the prefab root is a RigidBody3D (a physics bag)")
	assert_true(lb is LootBag, "the root carries the LootBag script")
	assert_true(lb is Throwable, "LootBag extends Throwable (shares the prop wiring)")
	assert_false(lb.destructible, "a loot bag ships destructible=false so a stray shot can't destroy dropped loot")
	lb.free()


func test_wired_node_refs_resolve_to_the_right_children() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "loot_bag.tscn loads")
		return
	var lb := scene.instantiate()

	var col := lb.get_node_or_null(^"CollisionShape3D")
	assert_true(col is CollisionShape3D, "`collision_shape` points at a CollisionShape3D child")
	if col is CollisionShape3D:
		assert_not_null((col as CollisionShape3D).shape, "the collider carries a shape resource")

	assert_true(lb.get_node_or_null(^"MeshInstance3D") is MeshInstance3D, "`mesh_instance` points at a MeshInstance3D child (the visual root)")
	assert_true(lb.get_node_or_null(^"AudioStreamPlayer3D") is AudioStreamPlayer3D, "`impact_sfx` points at an AudioStreamPlayer3D child (the impact thud)")

	lb.free()
