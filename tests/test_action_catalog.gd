extends GutTest
## Validator for the data-driven keybind catalog (resources/input/ActionCatalog.tres + ActionSpec). The
## OptionsMenu generates the Controls tab's section headers + rebind rows from this catalog's keybind_specs()
## (appended to SettingsCatalog.specs), so a dropped/typo'd action here = a missing rebind row at runtime.
## These tests fail LOUDLY at test-time instead: every rebindable action exists in the InputMap, keybind_specs
## emits a well-formed KEYBIND SettingSpec per action with a SECTION header per group, and a MIGRATION PIN
## guards that the set of rebindable actions matches the set the old SettingsCatalog Keybind rows covered (so
## the transcription out of the SettingsCatalog can't silently drop a binding). Pure data — no scene tree.

const CATALOG_PATH := "res://resources/input/ActionCatalog.tres"

## The rebindable actions the ActionCatalog covers (originally the SettingsCatalog's KEYBIND rows; "Walk" added
## by stealth Slice 3b; "Quicksave"/"Quickload" added by ML-1's save loop). Pinned here so a transcription
## mistake (a dropped or renamed action) fails this test instead of quietly removing a player's ability to
## rebind it. Keep in sync ONLY with a deliberate add/remove.
const EXPECTED_REBINDABLE := [
	&"forward", &"backward", &"left", &"right", &"jump", &"Crouch", &"Walk",
	&"Attack", &"Zoom", &"Reload", &"Throw", &"Light", &"Grapple", &"NightVision",
	&"PickUp", &"Inventory", &"Stats", &"Factions", &"Journal", &"RotateItem",
	&"Weapon Slot 1", &"Weapon Slot 2", &"Weapon Slot 3", &"Weapon Slot 4", &"Weapon Slot 5",
	&"Weapon Slot 6", &"Weapon Slot 7", &"Weapon Slot 8", &"Weapon Slot 9", &"Weapon Slot 10",
	&"Hotbar Next", &"Hotbar Prev", &"Quicksave", &"Quickload",
]

func _catalog() -> ActionCatalog:
	return load(CATALOG_PATH) as ActionCatalog

func test_catalog_loads_and_is_populated() -> void:
	var cat := _catalog()
	assert_not_null(cat, "ActionCatalog.tres must load (a parse error here = no rebind rows in Options)")
	if cat == null:
		return
	assert_eq(cat.actions.size(), EXPECTED_REBINDABLE.size(),
		"the catalog must hold one ActionSpec per rebindable action — got %d" % cat.actions.size())
	for a in cat.actions:
		assert_not_null(a, "no null entries in the actions array (a dangling SubResource ref)")

func test_every_action_has_name_label_and_section() -> void:
	var cat := _catalog()
	if cat == null:
		return
	for a in cat.actions:
		if a == null:
			continue
		assert_ne(String(a.action), "", "every ActionSpec needs an action name (label='%s')" % a.label)
		assert_ne(a.label, "", "ActionSpec '%s' must have a label" % a.action)
		assert_ne(a.section, "", "ActionSpec '%s' must name a section" % a.action)

func test_rebindable_actions_exist_in_inputmap() -> void:
	var cat := _catalog()
	if cat == null:
		return
	for action in cat.rebindable_actions():
		assert_true(InputMap.has_action(action),
			"ActionCatalog action '%s' must exist in the InputMap (project.godot [input] / InputManager)" % action)

func test_rebindable_set_matches_migration_pin() -> void:
	var cat := _catalog()
	if cat == null:
		return
	var got := {}
	for action in cat.rebindable_actions():
		got[action] = true
	var expected := {}
	for action in EXPECTED_REBINDABLE:
		expected[action] = true
	for action in EXPECTED_REBINDABLE:
		assert_true(got.has(action),
			"rebindable action '%s' was dropped from the ActionCatalog (it used to be in SettingsCatalog)" % action)
	for action in cat.rebindable_actions():
		assert_true(expected.has(action),
			"ActionCatalog adds a rebindable action '%s' not in the migration pin — update EXPECTED_REBINDABLE if intended" % action)

func test_keybind_specs_emit_keybind_rows_and_section_headers() -> void:
	var cat := _catalog()
	if cat == null:
		return
	var specs := cat.keybind_specs()
	var keybinds := 0
	var sections := 0
	for spec in specs:
		assert_not_null(spec, "keybind_specs must not emit null specs")
		if spec == null:
			continue
		assert_eq(String(spec.tab), "Controls", "generated spec '%s' must land on the Controls tab" % spec.key)
		match spec.control:
			SettingSpec.Widget.KEYBIND:
				keybinds += 1
				assert_ne(String(spec.rebind_action), "", "generated KEYBIND '%s' must name a rebind_action" % spec.key)
				assert_ne(spec.label, "", "generated KEYBIND '%s' must have a label" % spec.key)
			SettingSpec.Widget.SECTION:
				sections += 1
				assert_ne(spec.label, "", "generated SECTION header must have a label")
			_:
				fail_test("keybind_specs emitted an unexpected widget %d for '%s'" % [spec.control, spec.key])
	assert_eq(keybinds, EXPECTED_REBINDABLE.size(),
		"one KEYBIND row per rebindable action — got %d" % keybinds)
	assert_eq(sections, 5, "one SECTION header per group (Movement/Combat/Interface/Hotbar/System) — got %d" % sections)

func test_keybind_specs_skips_non_rebindable() -> void:
	# A non-rebindable / null ActionSpec must not produce a row (off-tree: build the catalog by hand).
	var cat := ActionCatalog.new()
	var rebindable := ActionSpec.new()
	rebindable.action = &"jump"
	rebindable.label = "Jump"
	rebindable.section = "Movement"
	var locked := ActionSpec.new()
	locked.action = &"pause"
	locked.label = "Pause"
	locked.section = "Movement"
	locked.rebindable = false
	cat.actions = [rebindable, locked, null]
	var specs := cat.keybind_specs()
	var actions := {}
	for spec in specs:
		if spec != null and spec.control == SettingSpec.Widget.KEYBIND:
			actions[spec.rebind_action] = true
	assert_true(actions.has(&"jump"), "the rebindable action must emit a KEYBIND row")
	assert_false(actions.has(&"pause"), "a non-rebindable action must NOT emit a KEYBIND row")
	cat = null
	rebindable = null
	locked = null

func test_section_header_precedes_its_first_action() -> void:
	# The first action of each section emits exactly one header before it; later actions of the same section
	# do not re-emit it (grouping is by first-seen section, in catalog order).
	var cat := _catalog()
	if cat == null:
		return
	var specs := cat.keybind_specs()
	var seen_sections := {}
	var current_section := ""
	for spec in specs:
		if spec == null:
			continue
		if spec.control == SettingSpec.Widget.SECTION:
			assert_false(seen_sections.has(spec.label), "section '%s' header emitted twice" % spec.label)
			seen_sections[spec.label] = true
			current_section = spec.label
		else:
			assert_ne(current_section, "", "a KEYBIND row appeared before any SECTION header")
