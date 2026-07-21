extends GutTest

## NavDebugOverlay — must ship inert and never touch the NavigationServer / spawn a renderer off-tree (the
## is_inside_tree() guards). The AI-layer RENDERING is debug/playtest-only and not asserted here; the pure colour +
## label-text mappings that feed it ARE (they're host/tree-free by design).

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
	assert_true(ov.show_navmesh, "navmesh draw on by default (enabling behaves as it historically did)")
	assert_true(ov.agent_paths, "agent path lines on by default when the overlay is enabled")
	# Every AI-diagnostic layer ships OFF (inert) — the overlay is a safe no-op until a designer opts in.
	assert_false(ov.show_sight_cones, "sight cones ship off")
	assert_false(ov.show_faction_colors, "faction colours ship off")
	assert_false(ov.show_goap_labels, "goap labels ship off")
	assert_false(ov.show_trigger_zones, "trigger zones ship off")
	assert_true(ov.color_cone_by_alertness, "cones tint by alertness by default")
	ov.free()

func test_ai_layer_setters_are_safe_offtree() -> void:
	# Flipping an AI layer off-tree must not spawn a renderer or crash (the _sync_renderer is_inside_tree() guard).
	var ov := NavDebugOverlay.new()
	ov.set_show_sight_cones(true)
	ov.set_show_trigger_zones(true)
	assert_true(ov.show_sight_cones, "setter records the flag even off-tree")
	assert_null(ov._renderer, "no AiDebugDraw is spawned while off-tree")
	ov.free()

func test_cone_colour_reflects_alertness() -> void:
	# UNAWARE reads green (g dominant); ALERTED reads red (r dominant) — distinct so the state is legible.
	var calm := NavDebugOverlay.cone_color_for_state(Perception.State.UNAWARE)
	assert_gt(calm.g, calm.r, "calm cone is green-dominant")
	var alert := NavDebugOverlay.cone_color_for_state(Perception.State.ALERTED)
	assert_gt(alert.r, alert.g, "alerted cone is red-dominant")
	assert_ne(calm, alert, "different states map to different colours")

func test_goap_label_text_formats() -> void:
	assert_eq(NavDebugOverlay.goap_label_text(false, &"", &""), "(no brain)", "no executor -> explicit marker")
	assert_eq(NavDebugOverlay.goap_label_text(true, &"combat", &"fire_armed"), "combat / fire_armed", "goal / action")
	assert_eq(NavDebugOverlay.goap_label_text(true, &"", &""), "idle / -", "null goal+action -> idle / -")
	assert_eq(NavDebugOverlay.goap_label_text(true, &"survive", &""), "survive / -", "goal but no action")
