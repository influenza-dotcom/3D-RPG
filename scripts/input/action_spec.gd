class_name ActionSpec
extends Resource

## One rebindable input ACTION declared as DATA, for the Options Controls tab. The ActionCatalog holds an
## ordered list of these; OptionsMenu generates the tab's rebind rows from them (ActionCatalog.keybind_specs),
## so a rebindable action is one catalog row instead of a hand-authored KEYBIND + SECTION SettingSpec pair.
##
## The KEYBOARD/MOUSE default binding stays in project.godot [input] (Godot-native, + the editor Input Map
## panel); the CONTROLLER default stays in InputManager (named JoyButton/JoyAxis constants). This row carries
## only what those don't: the Options label, the section it groups under, and whether it's rebindable.

## The InputMap action name — must match the action in project.godot [input] (the stable key; rebinding only
## swaps the bound event). e.g. &"jump", &"Attack".
@export var action: StringName = &""
## The label shown on the Options rebind row, e.g. "Jump", "Aim".
@export var label: String = ""
## The Controls-tab SECTION header this row groups under, e.g. "Movement", "Combat". A new section emits a
## header before its first row (rows are grouped in catalog order). DISPLAY text only — the generated
## header's stable key comes from section_key below.
@export var section: String = ""
## Stable id for that section's generated SECTION SettingSpec.key (e.g. &"sec_movement"). Authored so
## display prose is never itself the persisted key — retitling `section` must not mint a new key. Blank
## falls back to the legacy derivation StringName("sec_" + section.to_lower()) so an unauthored catalog
## keeps its old keys (compat). Only the section's FIRST rebindable row's value is read (see keybind_specs);
## author it identically on every row of the section so reordering can't change which value wins.
@export var section_key: StringName = &""
## Whether to emit an Options rebind row for it (true for everything a player can rebind).
@export var rebindable: bool = true
