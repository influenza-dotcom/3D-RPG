extends GutTest

## Interact key-hints + the Deus Ex carry fade.
## - InputManager.display_key reads an action's CURRENT binding for display — the canonical copy of the
##   OptionsMenu rebind-button label (which now delegates to it), and the source of the "[E]"/"[Z]" hints.
## - Throwable: look_name "Pick Up" backs the "[Z] Pick Up" hover prompt; on_picked_up / on_dropped apply
##   and clear CARRIED_TRANSPARENCY on its meshes.
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
	assert_eq(t.look_name(), "Pick Up", "a bare throwable's hover label is 'Pick Up'")
	var mi := MeshInstance3D.new()
	t.add_child(mi)
	t.on_picked_up(null)
	assert_almost_eq(mi.transparency, Throwable.CARRIED_TRANSPARENCY, 0.0001,
		"picking up fades the prop (Deus Ex carry transparency) so it doesn't wall off the screen")
	t.on_dropped()
	assert_almost_eq(mi.transparency, 0.0, 0.0001, "dropping restores full opacity")
	t.free()


func test_look_readout_prefixes_the_right_key() -> void:
	var p = load("res://scripts/player/player.gd").new()
	var t := Throwable.new()
	p._apply_look_readout(t)
	assert_eq(p._look_text, "[%s] Pick Up" % InputManager.display_key(InputManager.action_throw),
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
