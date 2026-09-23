extends GutTest

## NavDebugOverlay — ships inert and builds nothing off-tree (the is_inside_tree() guards), but once it is in a level
## and enabled it drives the process-wide nav debug draw (NavigationServer3D debug, the tree's debug_navigation_hint,
## every NavigationAgent3D's debug_enabled) and spawns / tears down its AiDebugDraw renderer child. Those globals are
## snapshotted in before_each and restored in after_each so the rest of the suite never inherits a lit-up navmesh.
## The per-NPC AI-layer DRAWING (cones / rings / labels) is debug/playtest-only and not asserted here; the pure colour
## + label-text mappings that feed it ARE.

var _saved_nav_hint: bool = false
var _saved_nav_server_debug: bool = false


func before_each() -> void:
	_saved_nav_hint = get_tree().debug_navigation_hint
	_saved_nav_server_debug = NavigationServer3D.get_debug_enabled()


func after_each() -> void:
	get_tree().debug_navigation_hint = _saved_nav_hint
	NavigationServer3D.set_debug_enabled(_saved_nav_server_debug)


## A NavigationAgent3D in the running tree, under a Node3D host the way an NPC carries one.
func _add_agent() -> NavigationAgent3D:
	var host := Node3D.new()
	var agent := NavigationAgent3D.new()
	host.add_child(agent)
	add_child_autofree(host)
	return agent


## The AiDebugDraw renderers currently live under the overlay (a torn-down one is queue_free'd, so it doesn't count).
func _live_renderers(ov: Node) -> Array[AiDebugDraw]:
	var out: Array[AiDebugDraw] = []
	for c in ov.get_children():
		if c is AiDebugDraw and not c.is_queued_for_deletion():
			out.append(c as AiDebugDraw)
	return out


## An overlay whose nav layers are off, so tests about the AI renderer don't also light the navmesh.
func _ai_only_overlay() -> NavDebugOverlay:
	var ov := NavDebugOverlay.new()
	ov.show_navmesh = false
	ov.agent_paths = false
	return ov


func test_ships_off_and_toggles_the_flag_safely_offtree() -> void:
	var ov := NavDebugOverlay.new()
	assert_false(ov.enabled, "overlay ships OFF by default (opt-in)")
	# Off-tree toggle: flips the flag but the is_inside_tree() guard means _apply() never runs -> no server calls.
	ov.toggle()
	assert_true(ov.enabled, "toggle flips the flag")
	ov.toggle()
	assert_false(ov.enabled, "toggle flips back")
	ov.free()


func test_offtree_overlay_builds_no_renderer_until_it_enters_the_tree() -> void:
	# Enabled AND two AI layers on, but not in a tree yet (a scene still being assembled / a script-built overlay).
	var ov := _ai_only_overlay()
	ov.enabled = true
	ov.set_show_sight_cones(true)
	ov.set_show_trigger_zones(true)
	assert_eq(ov.get_child_count(), 0,
		"an off-tree overlay must not spawn its AiDebugDraw child even with the master and AI layers on")
	assert_false(ov.is_processing(),
		"an off-tree overlay must not arm per-frame drawing before it has a tree to draw into")
	# CONTROL: the very same overlay, once it enters the tree, gets past the guard and builds the renderer.
	add_child_autofree(ov)
	assert_eq(_live_renderers(ov).size(), 1,
		"entering the tree with the master + an AI layer on spawns exactly one AiDebugDraw")
	assert_true(ov.is_processing(), "in-tree with an AI layer on, the overlay redraws every frame")


func test_fresh_overlay_in_a_level_draws_nothing_and_listens_for_no_keys() -> void:
	var ov := NavDebugOverlay.new()
	add_child_autofree(ov)
	assert_eq(_live_renderers(ov).size(), 0, "a freshly placed overlay spawns no AI renderer")
	assert_false(ov.is_processing(), "a freshly placed overlay does no per-frame work (nothing is being drawn)")
	assert_false(ov.is_processing_input(),
		"with no toggle action bound the overlay must not inspect every input event")


func test_enabling_a_fresh_overlay_draws_navmesh_and_agent_paths_but_no_ai_layers() -> void:
	get_tree().debug_navigation_hint = false
	NavigationServer3D.set_debug_enabled(false)
	var agent := _add_agent()
	var ov := NavDebugOverlay.new()
	add_child_autofree(ov)
	ov.enabled = true
	assert_true(get_tree().debug_navigation_hint, "enabling a stock overlay turns on the navmesh debug draw")
	assert_true(NavigationServer3D.get_debug_enabled(), "enabling a stock overlay turns on NavigationServer debug")
	assert_true(agent.debug_enabled, "enabling a stock overlay draws every NavigationAgent3D's path line")
	assert_eq(_live_renderers(ov).size(), 0, "the AI layers ship off, so enabling alone spawns no AI renderer")
	assert_false(ov.is_processing(), "no AI layer on -> no per-frame AI drawing")
	ov.enabled = false
	assert_false(get_tree().debug_navigation_hint, "disabling the overlay clears the navmesh debug draw")
	assert_false(NavigationServer3D.get_debug_enabled(), "disabling the overlay clears NavigationServer debug")
	assert_false(agent.debug_enabled, "disabling the overlay hides the agent path lines again")


func test_navmesh_and_agent_path_layers_gate_independently_under_the_master() -> void:
	var agent := _add_agent()
	var ov := NavDebugOverlay.new()
	add_child_autofree(ov)
	ov.enabled = true
	ov.show_navmesh = false
	assert_false(get_tree().debug_navigation_hint, "unticking show_navmesh live hides the navmesh polys")
	assert_true(agent.debug_enabled, "unticking show_navmesh must leave the agent path lines drawn")
	ov.show_navmesh = true
	ov.agent_paths = false
	assert_true(get_tree().debug_navigation_hint, "re-ticking show_navmesh live brings the navmesh back")
	assert_false(agent.debug_enabled, "unticking agent_paths live hides the path lines")


func test_ai_renderer_exists_only_while_master_and_a_layer_are_both_on() -> void:
	var ov := _ai_only_overlay()
	add_child_autofree(ov)
	ov.set_show_sight_cones(true)
	assert_eq(_live_renderers(ov).size(), 0, "an AI layer ticked while the master is OFF must draw nothing")
	ov.enabled = true
	var first := _live_renderers(ov)
	assert_eq(first.size(), 1, "turning the master on with a layer ticked spawns the renderer")
	ov.set_show_sight_cones(false)
	assert_eq(_live_renderers(ov).size(), 0, "switching the last AI layer off frees the renderer (clears every line)")
	assert_false(ov.is_processing(), "with no AI layer on the per-frame redraw stops")
	ov.set_show_goap_labels(true)
	var second := _live_renderers(ov)
	assert_eq(second.size(), 1, "ticking a layer again after a teardown spawns a fresh renderer")
	if first.size() == 1 and second.size() == 1:
		assert_ne(second[0], first[0], "the re-spawned renderer is a new node, not the one queued for deletion")
	ov.enabled = false
	assert_eq(_live_renderers(ov).size(), 0, "turning the master off with a layer still ticked frees the renderer")
	assert_false(ov.is_processing(), "master off -> no per-frame redraw")


func test_draw_through_walls_reaches_the_renderer_at_spawn_and_live() -> void:
	var ov := _ai_only_overlay()
	ov.draw_through_walls = false
	ov.enabled = true
	ov.set_show_sight_cones(true)
	add_child_autofree(ov)
	var r := _live_renderers(ov)
	assert_eq(r.size(), 1, "precondition: the renderer spawned")
	if r.size() != 1:
		return
	assert_false(r[0].draw_through_walls,
		"a renderer spawned after the designer unticked draw_through_walls must depth-test (not show through walls)")
	ov.draw_through_walls = true
	assert_true(r[0].draw_through_walls, "re-ticking draw_through_walls live reaches the running renderer")


func test_bound_hotkeys_toggle_their_own_layer_and_ignore_other_actions() -> void:
	var ov := _ai_only_overlay()
	ov.toggle_action = &"ui_accept"
	ov.sight_cones_action = &"ui_select"
	add_child_autofree(ov)
	assert_true(ov.is_processing_input(), "a bound toggle action makes the overlay listen for input")
	var other := InputEventAction.new()
	other.action = &"ui_cancel"
	other.pressed = true
	ov._input(other)
	assert_false(ov.enabled, "an unrelated action must not toggle the overlay")
	assert_false(ov.show_sight_cones, "an unrelated action must not toggle the sight cones")
	var master := InputEventAction.new()
	master.action = &"ui_accept"
	master.pressed = true
	ov._input(master)
	assert_true(ov.enabled, "pressing the bound toggle action switches the overlay on")
	assert_false(ov.show_sight_cones, "the master hotkey must not flip an AI layer")
	var cones := InputEventAction.new()
	cones.action = &"ui_select"
	cones.pressed = true
	ov._input(cones)
	assert_true(ov.show_sight_cones, "pressing the sight-cone action switches the sight cones on")
	assert_false(ov.show_faction_colors, "the sight-cone hotkey must not flip a different AI layer")
	assert_eq(_live_renderers(ov).size(), 1, "master + sight cones switched on by hotkey spawns the renderer")
	ov._input(master)
	assert_false(ov.enabled, "pressing the bound toggle action again switches the overlay off")


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
