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
	# GUARD THE SLICE. find() answers -1 for a needle that has been renamed away, substr() over a bad offset yields
	# "", and every contains() check against "" reads as "absent" — which quietly turns an assert_false into a pass
	# and retires the pin instead of failing it. Assert the offset first so a rename fails HERE, loudly.
	var ready_at := base.find("func _ready")
	assert_gt(ready_at, -1, "func _ready no longer present in look_at_interactable.gd — the pin is stale")
	var base_ready := base.substr(ready_at)
	assert_true(base_ready.contains("Engine.is_editor_hint()"), "the @tool editor early-out is hoisted into the base _ready (XC1)")
	# The pure delegates no longer define _ready — they inherit the base guard.
	for path in ["res://scripts/components/switch_lever.gd", "res://scripts/components/readable.gd"]:
		assert_false(_read_source(path).contains("func _ready"), "%s inherits the base _ready (no own override) — XC1 dedup" % path)
	# container keeps its _ready (runtime inventory tail) but no longer calls _editor_fit_hitbox directly.
	var cont := _read_source("res://scripts/components/container.gd")
	assert_true(cont.contains("func _ready"), "container keeps its own _ready for the runtime inventory build")
	assert_false(cont.contains("_editor_fit_hitbox"), "container routes the editor preview through super(), not a direct _editor_fit_hitbox() call (XC1)")


## --- The shared-overlay-slot contract (the 2026-08-15 ATM bug) --------------------------------------------
## `material_overlay` is ONE slot per mesh and the NPC combat rim / Throwable hull live in it too. The shipping
## ATM is authored `highlight_color = Color(1,1,1,0)` + `highlight_width = 0.0` ("no hover outline") AND sits
## directly under the level root, so its host was the whole map: hovering it swapped a transparent material over
## every actor in the level and their black outlines vanished until you looked away. Two independent pins, either
## of which alone kills that symptom — keep both, they guard different halves.

class _FakeActor extends Node3D:
	func flash_red() -> void:  # Character's API — this subtree drives its own rim
		pass

class _FakeProp extends Node3D:
	func set_outline_visible(_want = null) -> void:  # Throwable's API — this subtree drives its own hull
		pass


func test_invisible_highlight_never_evicts_the_shared_overlay() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var rim := TalkHelpers.make_outline_material(Color.BLACK, 2.0)  # stand-in for an NPC combat rim
	mesh.material_overlay = rim
	host.add_child(mesh)
	var li := LookAtInteractable.new()
	li.highlight_color = Color(1.0, 1.0, 1.0, 0.0)  # exactly how the shipping ATM is authored
	li.highlight_width = 0.0
	host.add_child(li)  # _ready -> _build_outline
	li.set_look_highlight(true)
	assert_eq(mesh.material_overlay, rim, "an invisible highlight must leave the existing overlay in place")
	assert_false(mesh.has_meta(&"talk_prev_overlay"), "...and must not even stash it — nothing was swapped in")
	li.set_look_highlight(false)
	assert_eq(mesh.material_overlay, rim, "look-away restores nothing, because nothing was ever taken")


func test_highlight_never_adopts_an_actor_or_prop_subtree() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var own := MeshInstance3D.new()
	own.mesh = BoxMesh.new()
	host.add_child(own)
	var actor := _FakeActor.new()
	var actor_mesh := MeshInstance3D.new()
	actor_mesh.mesh = BoxMesh.new()
	actor.add_child(actor_mesh)
	host.add_child(actor)
	var prop := _FakeProp.new()
	var prop_mesh := MeshInstance3D.new()
	prop_mesh.mesh = BoxMesh.new()
	prop.add_child(prop_mesh)
	host.add_child(prop)
	var li := LookAtInteractable.new()  # default white highlight -> a REAL material, so the prune is what saves us
	host.add_child(li)  # _ready -> _build_outline
	assert_true(li._meshes.has(own), "the host's own mesh IS collected (the highlight still works)")
	assert_false(li._meshes.has(actor_mesh),
		"an actor subtree (flash_red) is pruned — it drives its own disposition rim + damage flash")
	assert_false(li._meshes.has(prop_mesh),
		"a prop subtree (set_outline_visible) is pruned — it drives its own black hull")


func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "could read %s" % path)
	return f.get_as_text() if f != null else ""
