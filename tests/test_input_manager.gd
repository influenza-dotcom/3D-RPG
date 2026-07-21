extends GutTest

## InputManager as the single input-audit + binding-query hub (the "Input Manager as True Single Source" pass).
## tests/test_input_action_catalog.gd pins the three name-surfaces from the catalog/InputMap side; THIS file pins
## InputManager's own runtime audit API:
##   • validate_action_sources() is CLEAN for the shipped project — every catalog action AND every code `action_*`
##     var is in the InputMap, and every code action is a rebindable catalog row. That is the task's "all actions in
##     catalog are in InputMap" check plus the two sibling directions, as one runtime assertion.
##   • the audit actually FIRES on injected drift, so a green result is never vacuous.
##   • get_action_binding() resolves a live binding and the display_key alias returns an identical string.
##   • the controller-only look_* pad axes exist after _ready() (added in code, not in [input] / the catalog) — the
##     reason the audit iterates the catalog + code vars and NOT the whole InputMap (which holds engine ui_* actions).


func test_validate_action_sources_is_clean_for_the_project() -> void:
	var drift := InputManager.validate_action_sources()
	assert_true(drift["catalog_loaded"],
		"ActionCatalog.tres must load for the audit (a parse error = no rebind rows in Options)")
	var cat_missing: Array = drift["catalog_missing_in_map"]
	var code_missing: Array = drift["code_missing_in_map"]
	var code_uncatalogued: Array = drift["code_missing_in_catalog"]
	assert_eq(cat_missing.size(), 0,
		"every ActionCatalog action must exist in the InputMap — drifted: %s" % [cat_missing])
	assert_eq(code_missing.size(), 0,
		"every InputManager action var must exist in the InputMap — drifted: %s" % [code_missing])
	assert_eq(code_uncatalogued.size(), 0,
		"every InputManager action var must be a rebindable ActionCatalog row (or _CONTROLLER_ONLY) — drifted: %s" % [code_uncatalogued])


func test_audit_detects_an_action_missing_from_the_inputmap() -> void:
	# Prove the audit isn't vacuously green: pull a real action out of the InputMap and confirm BOTH the catalog and
	# the code direction flag it, then restore the InputMap exactly. `jump` lives on all three surfaces. Restoration
	# runs unconditionally (GUT asserts don't halt the function), so a failed assert can't leak a broken InputMap into
	# the rest of the suite.
	var probe := &"jump"
	assert_true(InputMap.has_action(probe), "precondition: '%s' is a real action" % probe)
	var saved_events := InputMap.action_get_events(probe)
	var saved_deadzone := InputMap.action_get_deadzone(probe)

	InputMap.erase_action(probe)
	var drift := InputManager.validate_action_sources()
	var cat_missing: Array = drift["catalog_missing_in_map"]
	var code_missing: Array = drift["code_missing_in_map"]
	assert_true(cat_missing.has(probe),
		"a catalog action absent from the InputMap must be reported as catalog<->map drift")
	assert_true(code_missing.has(probe),
		"a code action var absent from the InputMap must be reported as code<->map drift")

	# Restore the InputMap to exactly what it was (events + deadzone).
	InputMap.add_action(probe, saved_deadzone)
	for e in saved_events:
		InputMap.action_add_event(probe, e)

	var after: Array = InputManager.validate_action_sources()["catalog_missing_in_map"]
	assert_eq(after.size(), 0,
		"InputMap must be fully restored after the detection probe — still drifted: %s" % [after])


func test_audit_detects_a_code_action_missing_from_the_catalog() -> void:
	# The highest-frequency authoring slip — a new action_* var with no ActionCatalog row — surfaces as
	# code_missing_in_catalog. The InputMap-erase probe above can't reach this branch (erasing from the map doesn't
	# touch the catalog), so inject a stand-in catalog that OMITS a known code action ('jump') and confirm it fires.
	# _action_catalog is restored unconditionally so the swap can't leak into other tests.
	var saved_catalog: ActionCatalog = InputManager._action_catalog  # whatever the boot audit cached
	var stub_spec := ActionSpec.new()
	stub_spec.action = &"Attack"  # a real rebindable action, so the stub's catalog<->map direction stays clean
	stub_spec.label = "Attack"
	stub_spec.section = "Combat"
	var stub := ActionCatalog.new()
	var specs: Array[ActionSpec] = [stub_spec]
	stub.actions = specs  # deliberately omits 'jump' (and every other code action)
	InputManager._action_catalog = stub

	var drift := InputManager.validate_action_sources()
	assert_true(drift["catalog_loaded"], "the injected stub catalog counts as loaded")
	var uncatalogued: Array = drift["code_missing_in_catalog"]
	assert_true(uncatalogued.has(&"jump"),
		"a code action var with no rebindable catalog row must be reported as code<->catalog drift")

	# Restore the cached catalog exactly (unconditional — GUT asserts don't halt the function).
	InputManager._action_catalog = saved_catalog
	stub_spec = null
	stub = null
	var after2: Array = InputManager.validate_action_sources()["code_missing_in_catalog"]
	assert_eq(after2.size(), 0,
		"restoring the real catalog clears the injected drift — still drifted: %s" % [after2])


func test_get_action_binding_resolves_and_display_key_is_an_alias() -> void:
	assert_ne(InputManager.get_action_binding(&"PickUp"), "(none)", "PickUp is a real project action")
	assert_ne(InputManager.get_action_binding(&"PickUp"), "(unbound)", "PickUp has a binding to display")
	assert_eq(InputManager.get_action_binding(&"NoSuchActionZZZ"), "(none)",
		"an unknown action reads (none) — guarded so the InputMap never errors")
	assert_eq(InputManager.display_key(&"PickUp"), InputManager.get_action_binding(&"PickUp"),
		"display_key must be a thin alias returning the same label as get_action_binding")


func test_action_catalog_accessor_returns_the_cached_authored_list() -> void:
	var cat := InputManager.action_catalog()
	assert_not_null(cat, "InputManager.action_catalog() must return the loaded ActionCatalog")
	if cat == null:
		return
	assert_gt(cat.actions.size(), 0, "the catalog holds the authored rebindable actions")
	assert_eq(InputManager.action_catalog(), cat, "the catalog is cached — the same instance across calls")


func test_controller_look_axes_exist_after_ready() -> void:
	# _add_default_controller_bindings() creates these right-stick look actions in CODE (no [input] / catalog row), so
	# the audit must NOT flag them — it iterates the catalog + code vars, never the whole InputMap.
	for a in [&"look_left", &"look_right", &"look_up", &"look_down"]:
		assert_true(InputMap.has_action(a), "controller look axis '%s' is added in InputManager._ready" % a)
