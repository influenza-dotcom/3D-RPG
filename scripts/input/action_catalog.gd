class_name ActionCatalog
extends Resource

## @system Options Settings
## @seam keybind_specs() turns its ActionSpec rows into the Controls-tab SECTION+KEYBIND SettingSpecs OptionsMenu appends to SettingsCatalog; the action name is the stable rebind key.
## @risk A dropped/renamed ActionSpec silently drops its Controls rebind row (no runtime error) since keybind_specs skips it; caught only at test time by the EXPECTED_REBINDABLE pin.
## @risk Keybinds bind LIVE in _input via Settings.rebind_action, bypassing the _pending/Apply staging other rows use — the key-press IS the confirmation, not an Apply-staged value.
## @risk project.godot [input], InputManager action_* vars, and ActionCatalog.tres must stay in lockstep; drift yields an un-rebindable action or a catalog row on a dead InputMap action — now caught at boot (dev builds) by InputManager.validate_action_sources()'s push_warning, not only at test time.
## @test res://tests/test_action_catalog.gd
## @test res://tests/test_input_action_catalog.gd
## @test res://tests/test_input_manager.gd
## The ordered list of rebindable input ACTIONS, declared as DATA (one ActionSpec per action). Authored as
## resources/input/ActionCatalog.tres and preloaded by scripts/ui/options_menu.gd, which appends
## keybind_specs() onto the SettingsCatalog rows — so the Options "Controls" tab's section headers + rebind
## rows are GENERATED from this list. Adding a rebindable key becomes: one [input] entry (the editor Input
## Map panel / keyboard default), one controller default in InputManager, and ONE ActionSpec row here —
## instead of a hand-authored SECTION + KEYBIND SettingSpec pair in the big SettingsCatalog.
##
## This catalog owns ONLY the Options-menu metadata (label, section grouping, rebindable). It does NOT own
## the bindings: keyboard/mouse defaults stay in project.godot [input], controller defaults stay in
## InputManager. keybind_specs() turns the rows into the same SettingSpec the menu already renders, so the
## render path + Settings rebind/persistence are untouched.

@export var actions: Array[ActionSpec] = []

## Build the Controls-tab rows for OptionsMenu: in catalog order, the first rebindable action of each section
## emits a SECTION header SettingSpec, and every rebindable action emits a KEYBIND SettingSpec (tab "Controls",
## rebind_action = its action). Non-rebindable / null rows are skipped. Returns SettingSpecs so the menu's
## existing _emit_row renders them exactly like the hand-authored rows it replaced.
func keybind_specs() -> Array[SettingSpec]:
	var out: Array[SettingSpec] = []
	var seen_sections: Dictionary = {}
	for a in actions:
		if a == null or not a.rebindable or a.action.is_empty():
			continue  # a blank action would make a "kb_" key that collides with any other blank row
		if not a.section.is_empty() and not seen_sections.has(a.section):
			seen_sections[a.section] = true
			out.append(_section_spec(a.section))
		out.append(_keybind_spec(a))
	return out

## The ordered set of rebindable action names this catalog covers — for tests / drift checks against the
## InputMap and the actions consumers poll. Mirrors keybind_specs() (same skip rules), names only.
func rebindable_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in actions:
		if a == null or not a.rebindable or a.action.is_empty():
			continue  # mirror keybind_specs(): skip blank-action rows so the two stay in lockstep
		out.append(a.action)
	return out

## A SECTION header row for a Controls-tab group (e.g. "Movement").
func _section_spec(title: String) -> SettingSpec:
	var s := SettingSpec.new()
	s.key = StringName("sec_" + title.to_lower())
	s.tab = &"Controls"
	s.control = SettingSpec.Widget.SECTION
	s.label = title
	return s

## A KEYBIND rebind row for one action — routes to OptionsMenu's live rebinder by action name.
func _keybind_spec(a: ActionSpec) -> SettingSpec:
	var s := SettingSpec.new()
	s.key = StringName("kb_" + String(a.action))
	s.tab = &"Controls"
	s.control = SettingSpec.Widget.KEYBIND
	s.label = a.label
	s.rebind_action = a.action
	return s
