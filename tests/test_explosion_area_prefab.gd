extends GutTest

## Scene-wiring contract for explosion_area.tscn (Explosion) — the richest exported-node-ref prefab in the project.
## explosion.gd's _ready drives four WIRED node refs (node_paths): `mesh_instance` (the flash), `collision_shape`
## (the push collider + the DUAL-MODE switch), `screen_shake_collision_shape` (under a nested ScreenShakeArea), and
## `timer` (the self-destruct) — plus an `@onready var omni_light_3d = $OmniLight3D` that hard-crashes _ready if the
## light child is renamed/removed. A designer or a bad re-save could drop any of these silently.
##
## Verified STRUCTURALLY, WITHOUT add_child: the prefab is a live, self-freeing explosion (its Timer autostarts and
## frees the node on timeout), so we never run _ready. Instead we resolve each wired NodePath against the
## instantiated subtree (relative get_node works off-tree) and assert the target's type — pinning exactly what the
## exports point at, independent of runtime property resolution.

const PREFAB := "res://scenes/effects/explosion_area.tscn"


func test_prefab_root_is_an_explosion_area() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "explosion_area.tscn loads")
	if scene == null:
		return
	var e := scene.instantiate()
	assert_true(e is Area3D, "the prefab root is an Area3D (the blast overlap volume)")
	assert_true(e is Explosion, "the root carries the Explosion script")
	e.free()


func test_wired_node_refs_resolve_to_the_right_children() -> void:
	# Each exported node ref must point at a child of the expected type — the exact wiring a re-save could break.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "explosion_area.tscn loads")
		return
	var e := scene.instantiate()

	var mesh := e.get_node_or_null(^"MeshInstance3D")
	assert_true(mesh is MeshInstance3D, "`mesh_instance` points at a MeshInstance3D child (the flash mesh)")
	# The SCRIPT, not just the type: ExplosionMesh._ready is what builds the pulsing flash material AND what
	# stamps InkOutline.ACTOR_INK_MASK_LAYER. Drop the script and the blast silently becomes a plain opaque
	# sphere that the world's ink pass edge-detects into a black ring (the 2026-08-16 report).
	assert_true(mesh is ExplosionMesh, "the flash node carries the ExplosionMesh script (pulse + ink-mask stamp)")

	var col := e.get_node_or_null(^"CollisionShape3D")
	assert_true(col is CollisionShape3D, "`collision_shape` points at a CollisionShape3D child (the push collider / dual-mode switch)")
	if col is CollisionShape3D:
		assert_not_null((col as CollisionShape3D).shape, "the push collider carries a shape resource")

	var shake := e.get_node_or_null(^"ScreenShakeArea/CollisionShape3D")
	assert_true(shake is CollisionShape3D, "`screen_shake_collision_shape` points at ScreenShakeArea/CollisionShape3D")

	var timer := e.get_node_or_null(^"Timer")
	assert_true(timer is Timer, "`timer` points at the self-destruct Timer child")
	if timer is Timer:
		assert_true((timer as Timer).one_shot, "the self-destruct Timer is one-shot (fires once, frees the blast)")

	e.free()


func test_omni_light_and_screen_shake_area_children_exist() -> void:
	# explosion.gd's `@onready var omni_light_3d = $OmniLight3D` hard-crashes _ready if the light is missing; the
	# ScreenShakeArea (its own Area3D) drives the camera-shake reach. Pin both so the prefab can't silently rot.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "explosion_area.tscn loads")
		return
	var e := scene.instantiate()
	assert_true(e.get_node_or_null(^"OmniLight3D") is OmniLight3D, "the @onready $OmniLight3D child is present (its absence crashes _ready)")
	assert_true(e.get_node_or_null(^"ScreenShakeArea") is Area3D, "the ScreenShakeArea child (the camera-shake reach volume) is present")
	e.free()
