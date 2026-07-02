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
		"res://scripts/components/container.gd",
		"res://scripts/components/can_pick_up.gd",
		"res://scripts/components/merchant.gd",
		"res://scripts/components/lootable_corpse.gd",
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


func test_xc1_editor_guard_hoisted_and_pure_delegates_inherit() -> void:
	# XC1: the @tool editor early-out (Engine.is_editor_hint() -> _editor_fit_hitbox() + return) lives ONCE in the base
	# _ready. The pure-delegate subclasses dropped their own _ready and inherit it; container KEEPS a _ready for its
	# runtime inventory tail but routes the editor preview through super() (no direct _editor_fit_hitbox() call).
	# Source-scanned because the guard is edit-time behaviour a unit test can't exercise (we never run _ready here).
	var base := _read_source("res://scripts/components/look_at_interactable.gd")
	assert_true(base.contains("func _ready"), "base still defines _ready")
	var base_ready := base.substr(base.find("func _ready"))
	assert_true(base_ready.contains("Engine.is_editor_hint()"), "the @tool editor early-out is hoisted into the base _ready (XC1)")
	# The pure delegates no longer define _ready — they inherit the base guard.
	for path in ["res://scripts/components/switch_lever.gd", "res://scripts/components/readable.gd"]:
		assert_false(_read_source(path).contains("func _ready"), "%s inherits the base _ready (no own override) — XC1 dedup" % path)
	# container keeps its _ready (runtime inventory tail) but no longer calls _editor_fit_hitbox directly.
	var cont := _read_source("res://scripts/components/container.gd")
	assert_true(cont.contains("func _ready"), "container keeps its own _ready for the runtime inventory build")
	assert_false(cont.contains("_editor_fit_hitbox"), "container routes the editor preview through super(), not a direct _editor_fit_hitbox() call (XC1)")


func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "could read %s" % path)
	return f.get_as_text() if f != null else ""
