extends GutTest

## LookAtInteractable — the shared base for the look-at world components (Wave 0 dedup) + its opt-in collider
## auto-fit. Off-tree: .new() (no _ready), so we assert the duck-typed talk-handler defaults, that the 4
## components share the base, and that the collider auto-fit is a SAFE opt-in. The actual AABB fit needs
## in-tree meshes, so it's playtest-verified.


func test_base_talk_handler_defaults() -> void:
	var li := LookAtInteractable.new()
	assert_eq(li.host_npc(), null, "a world interactable has no NPC behind it (player.gd null-guards this)")
	assert_true(li.can_be_talked_to(), "interactable by default (subclasses override when conditional)")
	assert_eq(li.look_name(), "Interact", "generic hover label by default (subclasses override)")
	li.set_look_highlight(true)   # off-tree: no meshes -> no-op, must not crash
	li.set_look_highlight(false)
	li.free()


func test_world_components_share_the_base() -> void:
	# The 4 components extend the base, so the talk-handler surface + outline live in one place.
	for path in [
		"res://scripts/world/container.gd",
		"res://scripts/world/can_pick_up.gd",
		"res://scripts/world/merchant.gd",
		"res://scripts/world/lootable_corpse.gd",
	]:
		var inst = load(path).new()
		assert_true(inst is LookAtInteractable, "%s must extend LookAtInteractable" % path)
		inst.free()


func test_auto_fit_collider_is_opt_in_and_safe() -> void:
	var li := LookAtInteractable.new()
	assert_false(li.auto_fit_collider, "collider auto-fit is OPT-IN (default off) — hand-sized colliders are never touched")
	li._fit_hitbox_to_host()  # off-tree: no host meshes -> safe no-op
	assert_eq(li.get_child_count(), 0, "with no host meshes, no hitbox is created (safe no-op)")
	li.free()
