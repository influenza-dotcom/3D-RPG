extends GutTest

## PickupRay (ray_cast.gd) freed-prop recovery. A carried Throwable can be freed out from under the ray while HELD —
## a gore gib's lifetime fade/free, an NPC shooting it apart, or the gib cap reclaiming the oldest gib. In Godot 4 a
## FREED Object is FALSY and compares == null (both verified headless), so the old `if not held_object: return` guard
## short-circuited on the dead reference BEFORE the recovery branch could run — held_object stayed dangling and
## carry_changed(false) never fired, stranding the player "carrying" a dead ref with the gun holstered + draw-locked
## (the reported "pick up a gib, it vanishes in your hand, stuck until you die"). The fix gates recovery on a _holding
## BOOL that survives the free (held_object alone can't distinguish "carrying a freed prop" from "carrying nothing").
##
## These pin that both recovery sites — the per-frame _physics_process branch and force_release_held (die/quickload) —
## null held_object, clear _holding, and emit carry_changed(false) so the player un-holsters + lifts the gun draw-lock.
## The held prop is built OFF-TREE (no add_child, so Throwable._ready is not run — we only need a ref to free), matching
## the repo's "don't run a heavy _ready in a unit test" rule; the PickupRay itself is in-tree so its signal + world work.

const PickupRayScript = preload("res://scripts/components/ray_cast.gd")
const ThrowableScript = preload("res://scripts/components/Throwable.gd")


func _ray_carrying_a_freed_prop() -> PickupRay:
	var ray := PickupRayScript.new() as PickupRay
	add_child_autofree(ray)  # in-tree: carry_changed listeners + get_world_3d() for the per-frame update
	var prop := ThrowableScript.new() as Throwable  # off-tree: _ready not run; just a Throwable ref to hold then free
	ray.held_object = prop
	ray._holding = true
	prop.free()  # freed WHILE held — the exact case the old truthiness guard mis-handled
	return ray


func test_physics_process_recovers_from_freed_held_prop() -> void:
	var ray := _ray_carrying_a_freed_prop()
	watch_signals(ray)
	ray._physics_process(0.016)  # per-frame carry update must detect the freed prop and recover, not chase a dead ref
	assert_null(ray.held_object, "freed held prop is nulled — the player isn't left 'carrying' a dead reference")
	assert_false(ray._holding, "_holding clears on recovery")
	assert_signal_emit_count(ray, "carry_changed", 1, "exactly one carry_changed on recovery")
	# 4th arg is the emission index (int), not a message — [false] means the player un-holsters + lifts the draw-lock.
	assert_signal_emitted_with_parameters(ray, "carry_changed", [false], 0)


func test_force_release_recovers_from_freed_held_prop() -> void:
	# die() / quickload call force_release_held; its old `if held_object` guard was ALSO falsy for a freed ref, so it
	# couldn't restore the gun either. It must recover the freed case explicitly now.
	var ray := _ray_carrying_a_freed_prop()
	watch_signals(ray)
	ray.force_release_held()
	assert_null(ray.held_object, "force_release_held nulls a freed held prop")
	assert_false(ray._holding, "_holding clears")
	assert_signal_emit_count(ray, "carry_changed", 1, "force_release_held emits carry_changed(false) exactly once")
	assert_signal_emitted_with_parameters(ray, "carry_changed", [false], 0)


func test_force_release_with_nothing_held_is_silent() -> void:
	var ray := PickupRayScript.new() as PickupRay
	add_child_autofree(ray)
	watch_signals(ray)
	ray.force_release_held()
	assert_signal_not_emitted(ray, "carry_changed", "no spurious carry_changed when nothing was ever held")
