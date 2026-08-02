class_name SettingSpec
extends Resource

## @system Options Settings
## @seam One Options row as DATA (widget + getter/setter names); OptionsMenu emits each value row from SettingsCatalog.tres, resolving each spec's getter/setter on the Settings autoload BY NAME.
## @risk getter/setter resolve on Settings BY NAME (options_menu.gd _spec_current/_spec_setter): a typo or renamed setter breaks that one row only at menu-open; caught by test_settings_catalog if run.
## @risk A generic DROPDOWN loses its options on an editor .tres re-save -> empty in-game menu; window_mode/colorblind/difficulty stay CUSTOM (code-built) to dodge it (a recurred bug).
## @risk Hand-authoring a KEYBIND row in the catalog instead of ActionCatalog.tres double-authors the Controls tab (keybind rows are appended from the ActionCatalog).
## @test res://tests/test_settings_catalog.gd
## @test res://tests/test_options_menu.gd
## @test res://tests/test_difficulty.gd
## One row in the Options menu, declared as DATA. OptionsMenu reads a SettingsCatalog of these at build
## time and emits the matching control, binding it to the Settings autoload BY METHOD NAME — so adding an
## option is "add a typed var + setter to Settings.gd, then add one row here", never hand-wiring UI. This
## resource describes only the WIDGET and how it binds; Settings.gd stays the typed, tested persistence +
## apply core (the menu still routes every edit through the existing _pending/Apply staging cycle).
##
## Most rows are a TOGGLE / SLIDER / DROPDOWN bound to a Settings getter+setter. SECTION is an in-tab
## header; KEYBIND rebinds an InputMap action (binds live on key-press); CUSTOM delegates to a named
## OptionsMenu builder for the few rows that aren't pure value-binding (Resolution, the Controls hint).

enum Widget { SECTION, TOGGLE, SLIDER, DROPDOWN, KEYBIND, CUSTOM }
## Live readout format for a SLIDER (the per-row formatter lambdas, made declarative).
enum ValueFormat { RAW, PERCENT, INTEGER, UNCAPPED, SENSITIVITY, ONE_DECIMAL }

@export_group("Identity")
## Stable id for tests / de-dup; NOT a storage key — Settings keeps its own typed var.
@export var key: StringName = &""
## Tab page this row lives on. Tabs are created in the order their first spec is seen. `tab` is the KEY:
## it groups rows, names the page NODE, and is what tests pin — it is NOT the visible tab title.
@export var tab: StringName = &""
## Optional DISPLAY title for that tab page (what the TabContainer paints). Empty falls back to String(tab),
## so an unlabeled catalog keeps today's look with no .tres edit. The first non-empty tab_label among a
## tab's specs wins (catalog order). Display only — never used for grouping, node names, or lookups.
@export var tab_label: String = ""
## Widget kind. SECTION uses `label` as the header; CUSTOM delegates to `custom_handler`.
@export var control: Widget = Widget.TOGGLE
## Row label (or the header text for SECTION, or the hint text for the Controls note).
@export var label: String = ""

@export_group("Binding")
## Settings property (e.g. &"fov") or method (e.g. &"get_volume") read to seed the control's current value.
@export var getter: StringName = &""
## Settings setter the control binds to (e.g. &"set_fov", &"set_volume"); staged and committed on Apply.
@export var setter: StringName = &""
## Optional LEADING bound arg for getter/setter — the volume bus. &"" = no bind. Preserves set_volume(bus, v).
@export var bind: StringName = &""

@export_group("Slider")
@export var min_value: float = 0.0
@export var max_value: float = 1.0
@export var step: float = 0.01
## Apply the slider value as an int (Max FPS, whose setter takes an int).
@export var as_int: bool = false
## How the right-aligned live readout is formatted.
@export var value_format: ValueFormat = ValueFormat.RAW

@export_group("Dropdown")
## Item labels for a DROPDOWN; the stored/staged value is the selected index.
@export var options: PackedStringArray = []

@export_group("Keybind / Custom")
## For KEYBIND: the InputMap action to rebind (binds live on key-press, like the old REBINDABLE list).
@export var rebind_action: StringName = &""
## For CUSTOM: name of the OptionsMenu method `func(tab: VBoxContainer, spec: SettingSpec) -> Control` that
## builds this row (returns the focusable control, or null). The escape hatch for non-value-binding rows.
@export var custom_handler: StringName = &""
