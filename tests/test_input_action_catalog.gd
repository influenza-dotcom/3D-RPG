extends GutTest

## M4: action names have THREE surfaces that must stay in lockstep — project.godot [input] (the InputMap), the
## InputManager `action_*` code vars, and resources/input/ActionCatalog.tres (the rebind UI + the drift source of
## truth). InputManager's header used to claim it was the "one place" for action names, but ActionCatalog is the
## canonical rebindable list. These pin: every InputManager var names a real InputMap action; every rebindable catalog
## action is a real InputMap action; every rebindable InputManager var is covered by the catalog; and Run /
## NightVision (once polled by bare literal with NO var) are now canonicalized.

const CATALOG_PATH := "res://resources/input/ActionCatalog.tres"

# Controller-only actions that legitimately have an InputManager var but no rebindable ActionCatalog row (e.g. a
# future look_* pad axis). EMPTY today — add a specific name here (never a blanket skip) if one is introduced.
const CONTROLLER_ONLY: Array[StringName] = []


func _input_manager_action_names() -> Array:
	var out := []
	for p in InputManager.get_property_list():
		var vname := String(p.get("name", ""))
		if not vname.begins_with("action_"):
			continue
		var act = InputManager.get(vname)
		if act is StringName or act is String:
			out.append({"var": vname, "action": StringName(act)})
	return out


func test_input_manager_vars_are_real_inputmap_actions() -> void:
	for e in _input_manager_action_names():
		assert_true(InputMap.has_action(e["action"]), "InputManager.%s = '%s' must be a real InputMap action (mirror of project.godot [input])" % [e["var"], e["action"]])


func test_catalog_rebindable_actions_are_real_inputmap_actions() -> void:
	var catalog := load(CATALOG_PATH) as ActionCatalog
	assert_not_null(catalog, "ActionCatalog.tres should load")
	for act in catalog.rebindable_actions():
		assert_true(InputMap.has_action(act), "ActionCatalog rebindable action '%s' must be a real InputMap action" % act)


func test_input_manager_rebindable_vars_are_covered_by_catalog() -> void:
	# Subset (not strict ==): every InputManager action var that isn't controller-only must appear in the catalog's
	# rebindable set, so a code-polled action can actually be rebound in the Options → Controls tab.
	var catalog := load(CATALOG_PATH) as ActionCatalog
	var covered := {}
	for a in catalog.rebindable_actions():
		covered[a] = true
	for e in _input_manager_action_names():
		if CONTROLLER_ONLY.has(e["action"]):
			continue
		assert_true(covered.has(e["action"]), "InputManager.%s = '%s' should be a rebindable ActionCatalog action (or listed CONTROLLER_ONLY)" % [e["var"], e["action"]])


func _keycodes_for(action: StringName) -> Array:
	var codes := []
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			codes.append(key.physical_keycode)
	return codes


func test_run_and_nightvision_are_canonicalized() -> void:
	# M4: Run + NightVision are code-polled actions and must stay behind InputManager vars.
	assert_eq(InputManager.action_run, &"Run", "action_run canonicalizes the Run action")
	assert_eq(InputManager.action_nightvision, &"NightVision", "action_nightvision canonicalizes the NightVision action")
	assert_true(InputMap.has_action(&"Run"), "Run is a real InputMap action")
	assert_true(InputMap.has_action(&"NightVision"), "NightVision is a real InputMap action")


func test_run_defaults_to_shift_and_crouch_to_ctrl() -> void:
	assert_true(_keycodes_for(&"Run").has(KEY_SHIFT), "Run defaults to Shift")
	assert_true(_keycodes_for(&"Crouch").has(KEY_CTRL), "Crouch defaults to Ctrl so Shift is free for Run")


func test_air_dash_defaults_to_left_alt_and_shares_with_nothing() -> void:
	# The air dash is the third BARE MODIFIER binding, alongside Run=Shift and Crouch=Ctrl — chosen because Alt is
	# the only free key the left thumb can reach without leaving WASD+Space, which a mid-air verb needs. The
	# rationale is argued at length in InputManager.gd; this pins it as data so a rebind of the DEFAULT is a
	# deliberate edit here, not a silent drift.
	assert_true(InputMap.has_action(&"AirDash"), "AirDash is a real InputMap action")
	assert_eq(InputManager.action_air_dash, &"AirDash", "action_air_dash canonicalizes the AirDash action")
	assert_true(_keycodes_for(&"AirDash").has(KEY_ALT), "AirDash defaults to Left Alt")
	# It must not collide with the other two bare modifiers — a shared event would fire both verbs on one press,
	# and unlike the Q lean/takedown pair there is no context to arbitrate a dash against.
	assert_false(_keycodes_for(&"Run").has(KEY_ALT), "Run must not also sit on Alt")
	assert_false(_keycodes_for(&"Crouch").has(KEY_ALT), "Crouch must not also sit on Alt")
	assert_false(_keycodes_for(&"AirDash").has(KEY_SHIFT), "the dash must not shadow Run")
	assert_false(_keycodes_for(&"AirDash").has(KEY_CTRL), "the dash must not shadow Crouch")
