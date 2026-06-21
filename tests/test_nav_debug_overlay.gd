extends GutTest

## NavDebugOverlay — must ship inert and never touch the NavigationServer off-tree (the is_inside_tree() guard).
## The actual debug RENDERING is debug-build/playtest-only and not asserted here.

func test_ships_off_and_toggles_the_flag_safely_offtree() -> void:
	var ov := NavDebugOverlay.new()
	assert_false(ov.enabled, "overlay ships OFF by default (opt-in)")
	# Off-tree toggle: flips the flag but the is_inside_tree() guard means _apply() never runs -> no server calls.
	ov.toggle()
	assert_true(ov.enabled, "toggle flips the flag")
	ov.toggle()
	assert_false(ov.enabled, "toggle flips back")
	ov.free()

func test_defaults_are_sane() -> void:
	var ov := NavDebugOverlay.new()
	assert_eq(ov.toggle_action, StringName(""), "no toggle key bound by default")
	assert_true(ov.agent_paths, "agent path lines on by default when the overlay is enabled")
	ov.free()
