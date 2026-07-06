extends GutTest

## Locomotor (scripts/components/locomotor.gd): the standalone drop-in pathfinder/mover. Attach under a CharacterBody3D,
## call move_to(), and it routes there on the navmesh. ACTUAL movement is integration/playtest territory (it needs a
## baked NavigationRegion3D + physics ticks — covered by the soak / combat-smoke harnesses), so these pin only the
## host-agnostic surface that IS cheaply checkable off-tree: the public API, the inert defaults, and the config warning
## that steers a designer to a CharacterBody3D parent. A bare .new() runs no _ready, so it's safe headless.


func test_api_surface_and_inert_defaults() -> void:
	var loco := Locomotor.new()  # not added to a tree -> _ready never runs -> stays fully inert
	assert_true(loco.has_method(&"move_to"), "exposes move_to(target)")
	assert_true(loco.has_method(&"stop"), "exposes stop()")
	assert_true(loco.has_method(&"is_moving"), "exposes is_moving()")
	assert_true(loco.has_signal(&"reached_target"), "emits reached_target on arrival")
	assert_true(loco.has_signal(&"path_blocked"), "emits path_blocked on an unreachable target")
	assert_false(loco.is_moving(), "idle by default (no target)")
	assert_eq(loco.desired_velocity, Vector3.ZERO, "no steering until a target is set")
	loco.move_to(Vector3.ONE)  # off-tree (no nav agent) this must no-op, never crash
	assert_false(loco.is_moving(), "move_to off-tree stays inert (no agent to path with)")
	loco.free()


func test_warns_under_a_non_characterbody_parent() -> void:
	var parent := Node3D.new()  # NOT a CharacterBody3D
	add_child_autofree(parent)
	var loco := Locomotor.new()
	parent.add_child(loco)  # freed with the autofreed parent; _ready sees the wrong parent type and stays inert
	assert_gt(loco._get_configuration_warnings().size(), 0, "warns that its parent must be a CharacterBody3D")


func test_no_warning_under_a_characterbody_parent() -> void:
	var body := CharacterBody3D.new()
	add_child_autofree(body)
	var loco := Locomotor.new()
	body.add_child(loco)  # _ready builds its NavigationAgent3D on the body; freed with the autofreed body
	assert_eq(loco._get_configuration_warnings().size(), 0, "no warning under a CharacterBody3D — the valid host")
