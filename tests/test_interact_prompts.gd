extends GutTest

## Interact key-hints + the Deus Ex carry fade.
## - InputManager.display_key reads an action's CURRENT binding for display. It is now a thin alias for the
##   canonical InputManager.get_action_binding (the OptionsMenu rebind-button label + the "[F]"/"[Z]" hints all
##   resolve through that); this test deliberately exercises the alias so it can't be dropped without notice.
## - Throwable: look_name "Pick Up" backs the "[Z] Pick Up" hover prompt; on_picked_up / on_dropped apply
##   and clear carried_transparency on its meshes.
## - Player._apply_look_readout prefixes the hint: the throw key for a Throwable (the input unique to
##   carrying), PickUp for an actable handler, and no key at all for nothing. Off-tree: the player computes
##   _look_text but skips the HUD (ui null) — exactly the surface pinned here.

func test_display_key_resolves_bound_and_missing_actions() -> void:
	assert_ne(InputManager.display_key(&"PickUp"), "(none)", "PickUp is a real project action")
	assert_ne(InputManager.display_key(&"PickUp"), "(unbound)", "PickUp has a binding to display")
	assert_ne(InputManager.display_key(&"PickUp"), "", "a bound action displays a non-empty key label")
	assert_eq(InputManager.display_key(&"NoSuchActionXYZ"), "(none)",
		"a missing action reads (none) — guarded so the InputMap never errors")


func test_throwable_look_name_and_carry_fade() -> void:
	var t := Throwable.new()
	assert_eq(t.look_name(), "[PH] Pick Up", "a bare throwable's hover label is 'Pick Up'")
	var mi := MeshInstance3D.new()
	t.add_child(mi)
	t.on_picked_up(null)
	assert_almost_eq(mi.transparency, t.carried_transparency, 0.0001,
		"picking up fades the prop (Deus Ex carry transparency) so it doesn't wall off the screen")
	t.on_dropped()
	assert_almost_eq(mi.transparency, 0.0, 0.0001, "dropping restores full opacity")
	t.free()


func test_throwable_carry_visibility_opaque_opt_out() -> void:
	var t := Throwable.new()
	t.held_visibility_mode = Throwable.HeldVisibilityMode.OPAQUE
	var mi := MeshInstance3D.new()
	t.add_child(mi)
	t.on_picked_up(null)
	assert_almost_eq(mi.transparency, 0.0, 0.0001,
		"an opaque-held Throwable should not become see-through when picked up")
	t.on_dropped()
	assert_almost_eq(mi.transparency, 0.0, 0.0001, "dropping an opaque-held Throwable keeps full opacity")
	t.free()


func test_pickup_ray_force_release_restores_without_throw_credit() -> void:
	var ray := PickupRay.new()
	var t := Throwable.new()
	ray.held_object = t
	ray._prior_gravity_scale = 2.5
	ray._prior_collision_layer = 8
	ray._prior_freeze = false
	ray._prior_freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	t.gravity_scale = 0.0
	t.collision_layer = 64
	t.freeze = true
	t.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	ray.force_release_held()
	assert_null(ray.held_object, "forced cleanup drops the held ref")
	assert_almost_eq(t.gravity_scale, 2.5, 0.001, "gravity scale is restored")
	assert_eq(t.collision_layer, 8, "collision layer is restored")
	assert_false(t.freeze, "freeze state is restored")
	assert_eq(t.freeze_mode, RigidBody3D.FREEZE_MODE_STATIC, "freeze mode is restored")
	assert_false(t._decoy_armed, "forced cleanup is not treated as a deliberate throw/decoy")
	t.free()
	ray.free()


func test_two_press_carry_grab_does_not_arm_first_release_is_inert() -> void:
	# Two-press carry/throw contract (see ray_cast.gd header + _grab_or_arm_release / _release_held): a GRAB does
	# NOT arm the release timer, so the FIRST key-up after grabbing is intentionally INERT — the prop keeps being
	# carried hands-free. Only a SECOND press (while carrying) arms the timer, and THAT press's key-up throws/drops.
	# Pins the design so a change can't silently turn it into hold-release (which would launch the prop the instant
	# you let go of the grab key, making hands-free carry impossible).
	var ray := PickupRay.new()
	var t := Throwable.new()
	ray.held_object = t
	ray._release_timer_started_us = -1  # the exact state right after a grab (the grab path never arms the timer)
	ray._release_held()  # first key-up: timer un-armed -> must be a no-op
	assert_eq(ray.held_object, t, "the first release after a grab is inert — the prop stays held (hands-free carry)")
	ray._grab_or_arm_release()  # a SECOND press while already carrying
	assert_gt(ray._release_timer_started_us, 0, "a press while carrying arms the release timer, so its key-up throws/drops")
	t.free()
	ray.free()


func test_look_readout_prefixes_the_right_key() -> void:
	var p = load("res://scripts/player/player.gd").new()
	var t := Throwable.new()
	p._apply_look_readout(t)
	assert_eq(p._look_text, "[%s] [PH] Pick Up" % InputManager.display_key(InputManager.action_throw),
		"a throwable's readout hints the carry/throw key — the input UNIQUE to throwables")
	var li := LookAtInteractable.new()
	p._apply_look_readout(li)
	assert_eq(p._look_text, "[%s] Interact" % InputManager.display_key(InputManager.action_pickup),
		"an actable interactable hints the Interact (PickUp) key")
	p._apply_look_readout(null)
	assert_eq(p._look_text, "", "looking at nothing clears the readout (no stray key hint)")
	t.free()
	li.free()
	p.free()
