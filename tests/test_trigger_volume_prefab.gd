extends GutTest

## Scene-wiring contract for trigger_volume.tscn — the keystone drop-in EVENT volume. A TriggerVolume is an
## Area3D that only detects bodies through a CollisionShape3D child; its own _get_configuration_warnings() flags
## a missing shape, but that warning is EDITOR-ONLY, so this pins the authored structure headlessly where a
## designer's mistake would otherwise surface only at runtime.
##
## Complements test_trigger_volume.gd, which drives the _gate() LOGIC off-tree via TriggerVolume.new(); this one
## asserts the authored SCENE. Instantiated WITHOUT add_child (no _ready needed): both node-ref exports are
## NodePath-typed and unwired in the prefab, so there is nothing to resolve in-tree, and it keeps the test free
## of the body-monitoring side effects _ready arms.

const PREFAB := "res://scenes/components/trigger_volume.tscn"


func test_prefab_root_is_a_triggervolume_area() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "trigger_volume.tscn loads")
	if scene == null:
		return
	var tv := scene.instantiate()
	assert_true(tv is Area3D, "the prefab root is an Area3D (the body-detection volume)")
	assert_true(tv is TriggerVolume, "the root carries the TriggerVolume script")
	tv.free()


func test_prefab_has_a_collision_shape_child() -> void:
	# The Area3D senses nothing without a shape — the trigger would never fire. This is exactly the
	# misconfiguration _get_configuration_warnings warns about, checked here so it can't slip past headless.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "trigger_volume.tscn loads")
		return
	var tv := scene.instantiate()
	var shape: CollisionShape3D = null
	for c in tv.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
			break
	assert_not_null(shape, "the prefab has a CollisionShape3D child — the volume that detects bodies")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource (an empty one detects nothing)")
	tv.free()


func test_prefab_ships_inert_defaults() -> void:
	# A bare placed trigger must do nothing but emit `fired` — every action is wired per-instance in a level, so
	# the prefab itself carries none. Guards against an action or flag accidentally baked into the shipped prefab.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "trigger_volume.tscn loads")
		return
	var tv := scene.instantiate()
	assert_eq(tv.trigger_group, Groups.PLAYER, "defaults to firing for the Player group (Groups.PLAYER)")
	assert_true(tv.activate_node_path.is_empty(), "activate_node_path is unwired in the prefab")
	assert_true(tv.target.is_empty(), "target is unwired in the prefab")
	assert_eq(tv.action, &"", "no call-method action baked into the prefab")
	assert_eq(tv.set_flag, &"", "no set_flag baked into the prefab")
	tv.free()
