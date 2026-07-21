extends Node

## @system Control-Lock And Immunity
## @seam world_frozen() (cutscene OR dialogue engaged) is the sole cinematic damage-immunity predicate, distinct from gameplay_suppressed()'s control gate.
## @risk Merging world_frozen() with gameplay_suppressed() silently grants immunity inside real-time menus, or strips it mid-cutscene — no crash, just wrong damage.
## @risk A new control-lock added only to gameplay_suppressed() leaves the frozen player takeable; adding only to world_frozen leaks immunity — both silent.
## @risk Immunity lives at 3 call sites (player.gd:2068, hazard_zone.gd:52, status_effect_manager.gd:31); a rename missing one silently un-gates that damage source.
## @test res://tests/test_world_frozen.gd

## @system Options Settings
## @seam get_action_binding(action) is the sole binding-query seam (display_key is a kept alias); validate_action_sources() cross-checks the three action-name surfaces (project.godot [input] / action_* vars / ActionCatalog) and _warn_on_action_drift() push-warns per drifted name at boot on dev builds.
## @risk A new action_* var without an ActionCatalog row (or a catalog row on a dead InputMap action) still needs the catalog / _CONTROLLER_ONLY fixed by hand — the boot audit REPORTS the drift, it does not auto-repair it.
## @test res://tests/test_input_manager.gd

# InputManager — the CODE-side hub for input ACTION NAMES. It provides an `action_*` var per gameplay action so code
# CAN read InputManager.action_x instead of a bare "jump" literal — but many hot-loop sites still poll the literal
# directly, and a few gameplay names (the look_* pad axes) have no var at all, so the shared NAME, not the var, is
# the contract. It also applies the gamepad DEFAULT bindings in _ready and is the single seam for two cross-cutting
# jobs: querying a binding for display (get_action_binding) and AUDITING that the three action-name surfaces agree
# (validate_action_sources / the boot-time drift warning).
#
# Action names live on THREE surfaces, keyed by the same stable NAME:
#   • project.godot [input]              — the InputMap; keyboard/mouse DEFAULT bindings (editor Input Map panel).
#   • these `action_*` vars              — the code handles + the CONTROLLER default bindings (added in _ready).
#   • resources/input/ActionCatalog.tres — the CANONICAL rebindable list; drives Options → Controls, designer-edited.
# The BINDINGS are not duplicated (keyboard/mouse in [input], controller in code, player rebinds persisted by
# Settings) — only the NAME is shared, and rebinding just swaps the bound event so name-polling consumers keep
# working. InputManager doesn't OWN the other two surfaces, but it is the one place that CROSS-CHECKS them: at boot
# (dev builds) validate_action_sources() drives a push_warning per drifted name, and tests/test_input_manager.gd +
# tests/test_input_action_catalog.gd pin all three directions. Keep the three in sync — an `action_*` here must name
# a real [input] action, and a rebindable one must appear in ActionCatalog.

var action_forward: StringName = &"forward"
var action_backward: StringName = &"backward"
var action_left: StringName = &"left"
var action_right: StringName = &"right"
var action_jump: StringName = &"jump"
var action_crouch: StringName = &"Crouch"
var action_attack: StringName = &"Attack"
var action_reload: StringName = &"Reload"
var action_zoom: StringName = &"Zoom"
var action_pickup: StringName = &"PickUp"
var action_light: StringName = &"Light"
var action_grapple: StringName = &"Grapple"
## Run modifier (default Shift): HOLD to move at full speed while stamina allows. Polled by the Player movement loop.
var action_run: StringName = &"Run"
## Night-vision toggle (default N): flips the night-vision post-process look. Polled by the Player.
var action_nightvision: StringName = &"NightVision"
## Weapon slots 1-10 (keys 1-0): consumed by the HOTBAR (scripts/ui/hotbar.gd) — pressing one equips the
## weapon / uses the consumable auto-assigned to that slot. (Slots 1-7 are the original weapon-switch
## actions, revived; 8-10 were added with the hotbar. The Tab inventory remains the full bag UI.)
var action_weapon_slot_1: StringName = &"Weapon Slot 1"
var action_weapon_slot_2: StringName = &"Weapon Slot 2"
var action_weapon_slot_3: StringName = &"Weapon Slot 3"
var action_weapon_slot_4: StringName = &"Weapon Slot 4"
var action_weapon_slot_5: StringName = &"Weapon Slot 5"
var action_weapon_slot_6: StringName = &"Weapon Slot 6"
var action_weapon_slot_7: StringName = &"Weapon Slot 7"
var action_weapon_slot_8: StringName = &"Weapon Slot 8"
var action_weapon_slot_9: StringName = &"Weapon Slot 9"
var action_weapon_slot_10: StringName = &"Weapon Slot 10"
## The ten hotbar actions in slot order (index 0 = key "1" … index 9 = key "0") — the Hotbar iterates this.
var hotbar_actions: Array[StringName] = [
	&"Weapon Slot 1", &"Weapon Slot 2", &"Weapon Slot 3", &"Weapon Slot 4", &"Weapon Slot 5",
	&"Weapon Slot 6", &"Weapon Slot 7", &"Weapon Slot 8", &"Weapon Slot 9", &"Weapon Slot 10",
]
## Scroll-wheel hotbar cycling (wheel down = next weapon slot, wheel up = previous). The bare wheel always
## switches weapons; the spray paint's palette cycling moved to AIM (Zoom) + wheel, so the can doesn't
## trap the scroll.
var action_hotbar_next: StringName = &"Hotbar Next"
var action_hotbar_prev: StringName = &"Hotbar Prev"
## Opens/closes the backpack (Tab). The full bag UI; the hotbar covers the quick-equip keys.
var action_inventory: StringName = &"Inventory"
## Open the dedicated read-only Stats screen (default C). Rebindable; no controller default (the obvious pads are taken).
var action_stats: StringName = &"Stats"
## Open the dedicated read-only Faction Reputation screen (default V). Action is "Factions" to avoid colliding
## with the Reputation autoload's name. Rebindable; no controller default.
var action_reputation: StringName = &"Factions"
## Open the read-only Quest Journal (default J). Rebindable; no controller default (the obvious pads are taken).
var action_journal: StringName = &"Journal"
## Grab-to-throw (Z): picks up the aimed throwable to CARRY/THROW it. Distinct from PickUp/Interact (E),
## which adds a dual item to the inventory instead — so an item that's both takeable AND throwable uses E
## to stash and Z to throw.
var action_throw: StringName = &"Throw"
## Silent takedown (default Q): HOLD behind an unaware NPC to quietly kill it (Slice 6b). Polled by SilentTakedown.
## Rebindable; no controller default (the obvious pads are taken — matches Stats/Journal).
var action_takedown: StringName = &"Takedown"
## Claim a pet (default T): TAP while aimed at a Claimable object (a stray dog) to adopt it — name it and make it
## follow you (see [[claim_interaction.gd]] / claimable.gd). Polled by ClaimInteraction. Rebindable; no controller
## default (the obvious pads are taken — matches Takedown/Stats/Journal).
var action_claim: StringName = &"Claim"
## Rotate the item being DRAGGED in the inventory grid (default R, shared with Reload — harmless since gameplay
## is suppressed while the bag is open). Read only by GridInventoryView mid-drag. Rebindable; no controller default.
var action_rotate_item: StringName = &"RotateItem"
## Quicksave / quickload (F5 / F9) — the immersive-sim save loop (ML-1). Polled by the Player; quickload reloads
## the scene. Rebindable; no controller default (a pad shouldn't fat-finger a save/load).
var action_quicksave: StringName = &"Quicksave"
var action_quickload: StringName = &"Quickload"


func is_action_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action)

func is_action_just_pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action)

func is_action_just_released(action: StringName) -> bool:
	return Input.is_action_just_released(action)

func get_vector(neg_x: StringName, pos_x: StringName, neg_y: StringName, pos_y: StringName) -> Vector2:
	return Input.get_vector(neg_x, pos_x, neg_y, pos_y)

func get_movement_vector() -> Vector2:
	return Input.get_vector(action_left, action_right, action_forward, action_backward)

## THE single modal registry (M5 / T1). Every player-facing modal screen appears in ONE authored list tagged with
## whether it PAUSES the tree, and all four surfaces derive from it: gameplay_suppressed (per-frame control gate),
## any_modal_open (don't-stack-a-menu guard), any_pausing_open (Pip-Boy-tab refusal), and close_all_modals (the
## death/quickload sweep). Registering a new screen = ONE row here + its project.godot [autoload] line — nothing else.
## Built LAZILY: the screen autoloads register AFTER InputManager in [autoload], so they don't exist at _ready(); every
## query runs at runtime by which point they do. Order matches the old hand-lists; `pausing` matches the old any_pausing_open.
var _modal_reg: Array[Dictionary] = []
var _modal_screens_cache: Array = []

func _ensure_modal_reg() -> void:
	if not _modal_reg.is_empty():
		return
	_modal_reg = [
		{screen = OptionsMenu, pausing = false},
		{screen = InventoryScreen, pausing = false},
		{screen = LootScreen, pausing = false},
		{screen = ShopScreen, pausing = true},
		{screen = StatsScreen, pausing = false},
		{screen = ReputationScreen, pausing = false},
		{screen = LevelUpScreen, pausing = true},
		{screen = RespecScreen, pausing = true},
		{screen = HealScreen, pausing = true},
		{screen = ChipInstallScreen, pausing = true},
		{screen = ChessScreen, pausing = true},
		{screen = QuestJournal, pausing = false},
		{screen = CharacterInspectScreen, pausing = false},  # fullscreen hero-view overlay; real-time like the Pip-Boy tabs
	]
	for e in _modal_reg:
		_modal_screens_cache.append(e.screen)

## True while a NON-pausing overlay menu is up OR control is otherwise suppressed (a cutscene / the name-entry box).
## The gameplay control gates — move / jump / fire / aim / crouch / grapple — check this. Truth set is byte-identical
## to the old OR-chain: the 12 registry screens + the two control-only suppressors.
func gameplay_suppressed() -> bool:
	return any_modal_open() or CutscenePlayer.is_active() or NameEntryDialog.is_open()

## CINEMATIC control-lock predicate — DISTINCT from gameplay_suppressed(). This is true only while the player's
## agency is scripted away by a cutscene OR a conversation, and it is the SINGLE source of truth for cinematic
## damage immunity (F-C34): Player.take_damage, HazardZone, and StatusEffectManager all gate on it so a control-locked
## player takes no hazard/DoT/NPC-fire damage and no effect duration burns while frozen. Deliberately does NOT include
## the real-time Pip-Boy/loot/shop overlays that gameplay_suppressed() counts — those pause menus keep the player at
## risk in the world and must NOT grant immunity. Two vectors:
##   • CutscenePlayer.is_active() — a cutscene is playing. A cutscene NEVER pauses the tree (staged actors keep moving),
##     so immunity must ride this predicate, not the pause (C34).
##   • DialogueManager.is_engaged() — a conversation exists AT ALL, including the ~0.5s pre-pause intro beat where
##     _active != null but the tree isn't paused yet; that window let an enemy shoot the frozen player (C66). A full
##     conversation additionally pauses the tree, but is_engaged() covers the unpaused intro this guard exists for.
## Must be an INSTANCE method on this autoload (mirrors gameplay_suppressed(); per the autoload-helpers-are-instance-methods
## rule). CutscenePlayer.is_active() is a static class call; DialogueManager is the autoload global.
func world_frozen() -> bool:
	return CutscenePlayer.is_active() or DialogueManager.is_engaged()

## The player-facing MODAL screens (the registry, screen objects only). A subset of gameplay_suppressed()'s truth set
## (excludes CutscenePlayer + NameEntryDialog — those suppress CONTROL but aren't menus you'd stack a shop over).
func _modal_screens() -> Array:
	_ensure_modal_reg()
	return _modal_screens_cache

## True if ANY player-facing modal screen is open, EXCLUDING `exclude` (by identity — a screen's own open() guard
## passes `self` so it doesn't self-block).
func any_modal_open(exclude: Object = null) -> bool:
	_ensure_modal_reg()
	for e in _modal_reg:
		var m: Object = e.screen
		if m != exclude and m.is_open():
			return true
	return false

## True if any PAUSING screen is open (the `pausing` rows). The real-time Pip-Boy tabs (Inventory/Stats/Reputation/
## Journal) refuse to open over these — but NOT over each other (they switch siblings via PlayerMenus.close_others).
func any_pausing_open() -> bool:
	_ensure_modal_reg()
	for e in _modal_reg:
		if e.pausing and e.screen.is_open():
			return true
	return false

## Close EVERY open modal (the death/respawn sweep and the quickload/quicksave chokepoint). Drives off the one
## registry, so a newly-registered screen is closed here automatically — no more hand-list drift (T1). Includes the
## NameEntryDialog (not a menu, but must not survive a death cinematic / scene reload floating over the world).
func close_all_modals() -> void:
	for m in _modal_screens():
		if m.is_open():
			m.close()
	if NameEntryDialog.is_open():
		NameEntryDialog.close()

var using_controller: bool = false  ## true when the last significant input was a gamepad — drives haptics

func _ready() -> void:
	_add_default_controller_bindings()
	# Cross-source input audit (see the SINGLE-SOURCE INPUT AUDIT section). Dev builds only — a release template bakes
	# the data, so the check would be pointless console noise there. Runs AFTER the controller binds so any future
	# controller-only action already exists in the InputMap when the audit reads it.
	if OS.is_debug_build():
		_warn_on_action_drift()

## Track whether the player is on a gamepad right now, so screen shake can rumble it (ScreenShake._rumble).
## Stick drift is ignored (only past-half-deflection counts); any key/mouse input flips back to false.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		using_controller = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		using_controller = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		using_controller = false

## Controller defaults, added in CODE so we don't hand-author InputEvent objects in project.godot. Left
## stick -> movement (so Input.get_vector picks it up automatically); right stick -> a new look_* action
## set read by MouseInput; face buttons / triggers / d-pad cover the rest. Each add is dup-guarded, so
## re-applying (or a future rebind layer) is safe.
func _add_default_controller_bindings() -> void:
	for a in [&"look_left", &"look_right", &"look_up", &"look_down"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
	_bind_axis(action_left, JOY_AXIS_LEFT_X, -1.0)
	_bind_axis(action_right, JOY_AXIS_LEFT_X, 1.0)
	_bind_axis(action_forward, JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis(action_backward, JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis(&"look_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_axis(&"look_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_axis(&"look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_axis(&"look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_bind_button(action_jump, JOY_BUTTON_A)
	_bind_button(action_crouch, JOY_BUTTON_B)
	_bind_button(action_reload, JOY_BUTTON_X)
	_bind_button(action_pickup, JOY_BUTTON_Y)
	_bind_button(action_light, JOY_BUTTON_LEFT_STICK)
	_bind_button(action_grapple, JOY_BUTTON_RIGHT_STICK)
	_bind_axis(action_attack, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_axis(action_zoom, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_bind_button(action_weapon_slot_1, JOY_BUTTON_DPAD_UP)
	_bind_button(action_weapon_slot_2, JOY_BUTTON_DPAD_RIGHT)
	_bind_button(action_weapon_slot_3, JOY_BUTTON_DPAD_DOWN)
	_bind_button(action_weapon_slot_4, JOY_BUTTON_DPAD_LEFT)

func _bind_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button:
			return  # already bound
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _bind_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		var m := e as InputEventJoypadMotion
		if m != null and m.axis == axis and signf(m.axis_value) == signf(value):
			return  # already bound
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)

## The display label for `action`'s CURRENT binding ("E", "Mouse 1", ...): prefer the keyboard/mouse event
## (what's usually rebound), else the first event. Read LIVE from the InputMap each call, so a rebind shows
## immediately. THE single binding-query seam — the Options rebind buttons, the interact key-hints on the hover
## readout ("[E] Talk to Kyle", "[Z] Pick Up"), tutorial `{action}` tokens, and dialogue prompts all resolve a
## key through here, so a rebind can't leave one surface stale. Returns "(none)" for an unknown action and
## "(unbound)" for a known action with no events.
func get_action_binding(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "(none)"
	var events := InputMap.action_get_events(action)
	for e in events:
		if e is InputEventKey or e is InputEventMouseButton:
			return event_label(e)
	if not events.is_empty():
		return event_label(events[0])
	return "(unbound)"

## Legacy alias for get_action_binding(). Kept so pre-existing call sites / tests keep resolving; prefer
## get_action_binding() in new code. Both read the same live InputMap logic — one implementation, two names.
func display_key(action: StringName) -> String:
	return get_action_binding(action)

## A short human label for one InputEvent binding ("E", "Mouse 1", "Pad 3", "Axis 5").
func event_label(e: InputEvent) -> String:
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	if e is InputEventMouseButton:
		return "Mouse %d" % (e as InputEventMouseButton).button_index
	if e is InputEventJoypadButton:
		return "Pad %d" % (e as InputEventJoypadButton).button_index
	if e is InputEventJoypadMotion:
		return "Axis %d" % (e as InputEventJoypadMotion).axis
	return "?"


# ---------------------------------------------------------------------------------------------------------------
# SINGLE-SOURCE INPUT AUDIT (M4 follow-up)
#
# The three name-surfaces (project.godot [input] / the `action_*` vars above / ActionCatalog.tres) share only the
# action NAME — bindings are not duplicated. These helpers make InputManager the ONE place that audits that those
# name-sets agree, at boot, so drift surfaces as a runtime warning the first time you run instead of only when the
# GUT suite runs. validate_action_sources() is pure (returns the drift, no logging) so tests/test_input_manager.gd
# and future tooling can assert on it; _warn_on_action_drift() is the boot-time console face of the same check.

const ACTION_CATALOG_PATH := "res://resources/input/ActionCatalog.tres"

# Actions with a code `action_*` var but deliberately NO rebindable ActionCatalog row (e.g. a controller-only pad
# axis). Mirrors tests/test_input_action_catalog.gd's CONTROLLER_ONLY — EMPTY today; add a specific name here (never
# a blanket skip) if one is introduced, and keep the two lists in step.
const _CONTROLLER_ONLY: Array[StringName] = []

var _action_catalog: ActionCatalog = null  ## lazily loaded once; the audited copy of the rebindable list

## The authored rebindable-action catalog (resources/input/ActionCatalog.tres), loaded once and cached. May be
## null if the .tres fails to load (a transient editor reimport) — callers must guard. This is the seam that lets
## InputManager audit the code/InputMap surfaces against the catalog; the DISPLAY binding query is
## get_action_binding(). Neither is a source of LIVE pressed/axis state — gameplay reads that straight from
## Input.is_action_pressed / Input.get_vector.
func action_catalog() -> ActionCatalog:
	if _action_catalog == null:
		_action_catalog = load(ACTION_CATALOG_PATH) as ActionCatalog
	return _action_catalog

## Reflect the `action_*` StringName vars into [{var, action}] rows — the code-side action-name set. Shared by the
## audit below (kept as the single definition of "which vars name actions"). `hotbar_actions` (an Array with no
## `action_` prefix) and any non-StringName member are excluded, matching tests/test_input_action_catalog.gd.
func _action_var_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in get_property_list():
		var vname := String(p.get("name", ""))
		if not vname.begins_with("action_"):
			continue
		var act: Variant = get(vname)
		if act is StringName or act is String:
			out.append({"var": vname, "action": StringName(act)})
	return out

## Cross-check the three name-surfaces and RETURN the drift (no logging, no side effects) so tests/tools can assert
## on it. Keys — each an Array[StringName], empty == in sync:
##   • "catalog_missing_in_map"  — a rebindable ActionCatalog action absent from the InputMap (its Options rebind
##                                 row would target a dead action). Empty when the catalog can't be loaded.
##   • "code_missing_in_map"     — an `action_*` var whose action isn't in the InputMap (gameplay polls a dead name).
##   • "code_missing_in_catalog" — an `action_*` var (excluding _CONTROLLER_ONLY) with no rebindable catalog row, so
##                                 the player can't rebind a key the code uses. Empty when the catalog can't be loaded.
## "catalog_loaded" (bool) distinguishes "in sync" from "couldn't reach the catalog this call".
func validate_action_sources() -> Dictionary:
	var catalog := action_catalog()
	var catalog_missing_in_map: Array[StringName] = []
	var code_missing_in_map: Array[StringName] = []
	var code_missing_in_catalog: Array[StringName] = []
	var rebindable: Dictionary = {}
	if catalog != null:
		for a in catalog.rebindable_actions():
			rebindable[a] = true
			if not InputMap.has_action(a):
				catalog_missing_in_map.append(a)
	for e in _action_var_entries():
		var act: StringName = e["action"]
		if not InputMap.has_action(act):
			code_missing_in_map.append(act)
		if catalog != null and not _CONTROLLER_ONLY.has(act) and not rebindable.has(act):
			code_missing_in_catalog.append(act)
	return {
		"catalog_loaded": catalog != null,
		"catalog_missing_in_map": catalog_missing_in_map,
		"code_missing_in_map": code_missing_in_map,
		"code_missing_in_catalog": code_missing_in_catalog,
	}

## Boot-time audit: push a warning per drifted name so a mis-authored input surface shows up in the console the
## first time you run, not only under GUT. Called from _ready() on dev builds. Non-fatal by design — a warning,
## never a crash, because a partially-authored input map is a common in-progress state.
func _warn_on_action_drift() -> void:
	var drift := validate_action_sources()
	if not bool(drift["catalog_loaded"]):
		# Usually a transient editor reimport; code-vs-map drift below is still reported (it doesn't need the catalog).
		push_warning("InputManager: could not load %s — skipping the catalog side of the input audit this boot." % ACTION_CATALOG_PATH)
	for a in drift["catalog_missing_in_map"]:
		push_warning("InputManager audit: ActionCatalog action '%s' is not in the InputMap (project.godot [input]) — its Options rebind row targets a dead action." % a)
	for a in drift["code_missing_in_map"]:
		push_warning("InputManager audit: an action var resolves to '%s', which is not in the InputMap — gameplay polls a dead action name." % a)
	for a in drift["code_missing_in_catalog"]:
		push_warning("InputManager audit: code action '%s' has no rebindable ActionCatalog row — the player can't rebind it (add an ActionSpec, or list it in _CONTROLLER_ONLY)." % a)
