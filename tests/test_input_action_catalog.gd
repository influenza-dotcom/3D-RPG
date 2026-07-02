extends GutTest

## M4: action names have THREE surfaces that must stay in lockstep — project.godot [input] (the InputMap), the
## InputManager `action_*` code vars, and resources/input/ActionCatalog.tres (the rebind UI + the drift source of
## truth). InputManager's header used to claim it was the "one place" for action names, but ActionCatalog is the
## canonical rebindable list. These pin: every InputManager var names a real InputMap action; every rebindable catalog
## action is a real InputMap action; every rebindable InputManager var is covered by the catalog; and Walk /
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


func test_walk_and_nightvision_are_canonicalized() -> void:
	# M4: Walk + NightVision used to be polled by bare literal with no InputManager var. Now canonicalized.
	assert_eq(InputManager.action_walk, &"Walk", "action_walk canonicalizes the Walk action")
	assert_eq(InputManager.action_nightvision, &"NightVision", "action_nightvision canonicalizes the NightVision action")
	assert_true(InputMap.has_action(&"Walk"), "Walk is a real InputMap action")
	assert_true(InputMap.has_action(&"NightVision"), "NightVision is a real InputMap action")
