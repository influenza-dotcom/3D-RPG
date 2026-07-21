extends GutTest

## Scene-wiring contract for throwable.tscn (Throwable) — the drop-in physics-prop base (a RigidBody3D). Three
## exported refs are WIRED (node_paths): `impact_sfx` (the thud), `collision_shape` (auto-fitted to the mesh on
## ready/save), and `mesh_instance` (the visual data meshes are pushed onto). If any is dropped, the prop loses
## its collider/sound/mesh silently — _get_configuration_warnings flags it in-editor, pinned here headlessly.
##
## Verified STRUCTURALLY, WITHOUT add_child: it's a RigidBody (it would fall) and Throwable._ready auto-fits the
## collider + pushes data onto the mesh — so we never run _ready. We resolve each wired NodePath against the
## instantiated subtree (relative get_node works off-tree) and assert the target's type.

const PREFAB := "res://scenes/components/throwable.tscn"


func test_prefab_root_is_a_throwable_body() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "throwable.tscn loads")
	if scene == null:
		return
	var t := scene.instantiate()
	assert_true(t is RigidBody3D, "the prefab root is a RigidBody3D (a thrown/dropped physics prop)")
	assert_true(t is Throwable, "the root carries the Throwable script")
	t.free()


func test_wired_node_refs_resolve_to_the_right_children() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "throwable.tscn loads")
		return
	var t := scene.instantiate()

	var col := t.get_node_or_null(^"CollisionShape3D")
	assert_true(col is CollisionShape3D, "`collision_shape` points at a CollisionShape3D child")
	if col is CollisionShape3D:
		assert_not_null((col as CollisionShape3D).shape, "the collider carries a shape resource")

	assert_true(t.get_node_or_null(^"MeshInstance3D") is MeshInstance3D, "`mesh_instance` points at a MeshInstance3D child (the visual root)")
	assert_true(t.get_node_or_null(^"AudioStreamPlayer3D") is AudioStreamPlayer3D, "`impact_sfx` points at an AudioStreamPlayer3D child (the impact thud)")

	t.free()
