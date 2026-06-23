extends GutTest
## Validator for the declarative Options catalog (resources/settings/SettingsCatalog.tres + SettingSpec).
## The OptionsMenu generates every row from this catalog and binds each control to a Settings method BY
## NAME, which trades compile-time checking for a runtime resolve — so a typo in a getter/setter/action only
## bites when the menu opens. These tests fail LOUDLY at test-time instead: every getter/setter resolves on
## Settings, every keybind action exists in the InputMap, every custom handler exists on OptionsMenu, slider
## ranges are sane, and the catalog still produces the 6 expected tabs. Pure data — no _ready, no scene tree.

const CATALOG_PATH := "res://resources/settings/SettingsCatalog.tres"

func _catalog() -> SettingsCatalog:
	return load(CATALOG_PATH) as SettingsCatalog

## Names of Settings' readable properties (so a property-style getter like &"fov" is recognised alongside
## method getters like &"get_volume").
func _settings_property_names() -> Dictionary:
	var names := {}
	for p in Settings.get_property_list():
		names[StringName(p.get("name", ""))] = true
	return names

func test_catalog_loads_and_is_populated() -> void:
	var cat := _catalog()
	assert_not_null(cat, "SettingsCatalog.tres must load (a parse error here = an empty Options menu)")
	if cat == null:
		return
	assert_true(cat.specs.size() >= 25,
		"the catalog must hold every migrated row (Video/Audio/Game/Controls/Accessibility) — got %d" % cat.specs.size())
	for spec in cat.specs:
		assert_not_null(spec, "no null entries in the specs array (a dangling SubResource ref)")

func test_every_spec_has_key_label_and_tab() -> void:
	var cat := _catalog()
	if cat == null:
		return
	var seen_keys := {}
	for spec in cat.specs:
		if spec == null:
			continue
		assert_ne(String(spec.key), "", "every spec needs a unique key (for de-dup / tests); label='%s'" % spec.label)
		assert_false(seen_keys.has(spec.key), "duplicate spec key '%s' — keys must be unique" % spec.key)
		seen_keys[spec.key] = true
		assert_ne(String(spec.tab), "", "spec '%s' must name a tab" % spec.key)
		assert_ne(spec.label, "", "spec '%s' must have a label" % spec.key)

func test_getters_resolve_on_settings() -> void:
	var cat := _catalog()
	if cat == null:
		return
	var props := _settings_property_names()
	for spec in cat.specs:
		if spec == null or spec.getter == &"":
			continue  # Section / Keybind / Custom rows bind nothing
		var ok: bool = props.has(spec.getter) or Settings.has_method(spec.getter)
		assert_true(ok, "spec '%s' getter '%s' must be a Settings property or method" % [spec.key, spec.getter])

func test_setters_resolve_on_settings() -> void:
	var cat := _catalog()
	if cat == null:
		return
	for spec in cat.specs:
		if spec == null or spec.setter == &"":
			continue
		assert_true(Settings.has_method(spec.setter),
			"spec '%s' setter '%s' must be a Settings method" % [spec.key, spec.setter])

func test_keybind_rows_migrated_out_to_action_catalog() -> void:
	# The rebind rows now live in resources/input/ActionCatalog.tres (generated via keybind_specs and appended
	# by OptionsMenu). This pins that they're NOT also hand-authored here — a re-added KEYBIND row would
	# double up the Controls tab. The InputMap coverage of those actions is asserted in test_action_catalog.
	var cat := _catalog()
	if cat == null:
		return
	for spec in cat.specs:
		if spec == null:
			continue
		assert_ne(spec.control, SettingSpec.Widget.KEYBIND,
			"SettingsCatalog must not hold KEYBIND rows anymore — '%s' belongs in the ActionCatalog" % spec.key)

func test_custom_handlers_exist_on_options_menu() -> void:
	var cat := _catalog()
	if cat == null:
		return
	for spec in cat.specs:
		if spec == null or spec.control != SettingSpec.Widget.CUSTOM:
			continue
		assert_ne(spec.custom_handler, &"", "Custom spec '%s' must name a handler" % spec.key)
		assert_true(OptionsMenu.has_method(spec.custom_handler),
			"Custom spec '%s' handler '%s' must be an OptionsMenu method" % [spec.key, spec.custom_handler])

func test_slider_ranges_are_sane() -> void:
	var cat := _catalog()
	if cat == null:
		return
	for spec in cat.specs:
		if spec == null or spec.control != SettingSpec.Widget.SLIDER:
			continue
		assert_lt(spec.min_value, spec.max_value,
			"slider '%s' must have min < max (got %s..%s)" % [spec.key, spec.min_value, spec.max_value])
		assert_gt(spec.step, 0.0, "slider '%s' must have a positive step" % spec.key)

func test_dropdowns_have_options() -> void:
	var cat := _catalog()
	if cat == null:
		return
	# window_mode/colorblind_mode are now CUSTOM (code-built) dropdowns, so this loop may match no generic DROPDOWN
	# specs. Any generic DROPDOWN that IS authored must still list its items (an empty array = an empty in-game menu).
	for spec in cat.specs:
		if spec == null or spec.control != SettingSpec.Widget.DROPDOWN:
			continue
		assert_true(spec.options.size() >= 2, "dropdown '%s' must list its items" % spec.key)
	# Pin the PERMANENT fix: window_mode + colorblind_mode must stay CUSTOM (their items are built in code), so the
	# editor cannot silently drop a PackedStringArray on a .tres re-save (the bug that recurred twice). A regression
	# back to a generic DROPDOWN — whose options the editor strips, leaving an empty in-game menu — fails here.
	var by_key := {}
	for spec in cat.specs:
		if spec != null:
			by_key[spec.key] = spec
	for key in [&"window_mode", &"colorblind_mode"]:
		assert_true(by_key.has(key), "the catalog must keep the '%s' row" % key)
		if by_key.has(key):
			assert_eq(by_key[key].control, SettingSpec.Widget.CUSTOM,
				"'%s' must stay a CUSTOM code-built dropdown (a generic DROPDOWN loses its options on a .tres re-save)" % key)

func test_catalog_covers_the_five_tabs() -> void:
	var cat := _catalog()
	if cat == null:
		return
	var tabs := {}
	for spec in cat.specs:
		if spec != null:
			tabs[spec.tab] = true
	for expected in [&"Video", &"Audio", &"Game", &"Controls", &"Accessibility"]:
		assert_true(tabs.has(expected), "the catalog must populate the '%s' tab" % expected)

func test_options_menu_builds_five_tabs_from_catalog() -> void:
	# The live autoload built its tabs from the catalog at startup (smoke-overlaps test_options_menu, kept
	# here so a catalog regression points straight at the catalog).
	assert_eq(OptionsMenu._tabs.get_tab_count(), 5,
		"OptionsMenu must build exactly the 5 catalog tabs")
