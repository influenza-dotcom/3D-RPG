extends Node

## @system Control-Lock And Immunity
## @seam world_frozen() (cutscene OR dialogue engaged) is the sole cinematic damage-immunity predicate, distinct from gameplay_suppressed()'s control gate.
## @risk Merging world_frozen() with gameplay_suppressed() silently grants immunity inside real-time menus, or strips it mid-cutscene — no crash, just wrong damage.
## @risk A new control-lock added only to gameplay_suppressed() leaves the frozen player takeable; adding only to world_frozen leaks immunity — both silent.
## @risk Immunity lives at 3 call sites (Player.take_damage, HazardZone._process, StatusEffectManager._process); a rename missing one silently un-gates that damage source.
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
## FLASHLIGHT toggle (defaults F **and** L on the keyboard, left-stick click on a pad). ⭐F is DELIBERATELY
## shared with `action_pickup` above, so the torch is a CONTEXTUAL FALLBACK on it exactly as the lean is on Q:
## flash_light.gd defers the press to Interact whenever the ray holds a live target, and toggles otherwise.
## ⭐L is the second binding and NEVER defers — it exists because `interact_available()` stays true for the whole
## time you carry a prop (and for any throwable within 3 m), which would otherwise pin the beam shut in exactly
## the cluttered dark room you want it in. Rebindable; rebinding replaces BOTH keyboard events with the one you
## pick, which ends the sharing and makes the torch unconditional — the same escape hatch a lean side gets.
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
## Open the Implants screen (default I) — its rows toggle an implant off/on. Rebindable; no controller default (the obvious pads are
## taken — matches Stats/Journal/Factions).
var action_implants: StringName = &"Implants"
## Open the MAP tab (default M) — the sixth Pip-Boy tab, a page-sized draw of the same floorplan widget the
## HUD minimap uses (scripts/ui/map_screen.gd). Polled by the screen itself (the WaitScreen/QuestJournal
## idiom — the surface owns its own key). ⭐M USED TO BE `MinimapZoom`; the zoom cycle moved to K when the map
## tab landed, because M is the map key every player already has muscle memory for and the two cannot share a
## binding (both fire during gameplay, so one press would open the map AND re-zoom the HUD box). Rebindable;
## no controller default (the obvious pads are taken — matches Stats/Journal/Factions/Implants).
var action_map: StringName = &"Map"
## Grab-to-throw (Z): picks up the aimed throwable to CARRY/THROW it. Distinct from PickUp/Interact (F),
## which adds a dual item to the inventory instead — so an item that's both takeable AND throwable uses E
## to stash and Z to throw.
var action_throw: StringName = &"Throw"
## Silent takedown (default Q): HOLD behind an unaware NPC to quietly kill it (Slice 6b). Polled by SilentTakedown.
## Rebindable; no controller default (the obvious pads are taken — matches Stats/Journal).
var action_takedown: StringName = &"Takedown"
## LEAN left / right (defaults Q / E on the keyboard, L1 / R1 on a pad): HOLD to peek the camera round a corner
## (scripts/player/lean.gd). ⭐LeanLeft DELIBERATELY SHARES Q with `Takedown` (itself already shared with the pet
## verb), so THAT side is CONTEXTUAL: the Lean component decides ON THE PRESS which of the two the key meant,
## using actions_share_binding() below plus whatever the verb drivers report as pending. LeanRight has E to
## itself — Interact/`PickUp` moved off E onto F — so the right peek is unconditional. That is the same escape
## hatch a player gets by rebinding a lean side onto its own key in Options → Controls: no shared event, no
## arbitration. Rebindable; the pad defaults are the shoulders, which nothing else uses.
var action_lean_left: StringName = &"LeanLeft"
var action_lean_right: StringName = &"LeanRight"
## Claim a pet (default B, for "Befriend" — the word the in-game prompt uses): TAP while aimed at a Claimable
## object (a stray dog) to adopt it — name it and make it follow you (see [[claim_interaction.gd]] /
## claimable.gd). Polled by ClaimInteraction. Rebindable; no controller default (the obvious pads are taken —
## matches Takedown/Stats/Journal). ⭐MOVED OFF T so Wait could take it: T is the Fallout 3/NV wait key and the
## muscle memory this game is trading on, while Claim is a rare contextual verb that only fires when you are
## aimed at a stray. If you rebind, keep them apart — they are both TAP verbs with no modifier.
var action_claim: StringName = &"Claim"
## Wait (default T, the Fallout 3/NV key): opens the WaitScreen, where the player picks a number of in-game
## hours to let pass. Polled by WaitScreen itself (the QuestJournal idiom — the screen owns its own key).
## Rebindable; no controller default (the obvious pads are taken — matches Takedown/Claim/Journal).
var action_wait: StringName = &"Wait"
## Hand verb (default H): with hands EMPTY it takes your WIELDED weapon (knife/gun) out of the holster and into your
## hands as a carriable/throwable prop; pressing it AGAIN on that weapon puts it straight back and re-wields it (a
## toggle). Carrying anything else — a world-grabbed or hotbar-pulled prop — it sets that down WITHOUT throwing it.
## Polled by PickupRay (ray_cast.gd). Rebindable; no controller default (the obvious pads are taken — matches
## Throw/Takedown/Claim).
var action_drop_held: StringName = &"DropHeld"
## Rotate the item being DRAGGED in the inventory grid (default R, shared with Reload — harmless since gameplay
## is suppressed while the bag is open). Read only by GridInventoryView mid-drag. Rebindable; no controller default.
var action_rotate_item: StringName = &"RotateItem"
## Cycle the HUD minimap's zoom (default K — it moved off M when the Map tab claimed that key; see action_map)
## through GameSettings.hud.minimap_zoom_steps, wrapping at the end.
## Polled by the Minimap widget itself (the WaitScreen/QuestJournal idiom — the surface owns its own key), which
## writes through Settings.set_minimap_zoom, so the key and the Options -> Accessibility "Minimap Zoom" slider
## move ONE value and the choice persists. Does nothing while the map is hidden or a modal is up — including
## over the MAP TAB, whose own zoom is Settings.map_zoom, driven by that screen's wheel and footer buttons
## (its Minimap instance ships zoom_key_enabled = false so one press can never move two maps). Rebindable; no
## controller default (the obvious pads are taken — matches Throw/Takedown/Claim/Wait).
var action_minimap_zoom: StringName = &"MinimapZoom"
## MARK WAYPOINT (default X): TAP to INSTANTLY pin the spot you are LOOKING AT — or, when the aim ray reaches
## nothing, the spot you are STANDING ON — into GameState's per-level waypoint ledger, auto-named, made THE
## tracked pin (the heading tape's nav pip), and confirmed with a toast. No dialog: mid-gameplay is no place
## to type, and the Map tab's edit card re-authors the pin later. Polled by the WaypointMarker player
## component (scripts/player/waypoint_marker.gd), which owns the ray and the physics-frame requirement that
## comes with it.
##
## ⭐ONE KEY FOR BOTH GESTURES, deliberately. "Mark what I see" and "mark where I stand" are the same intent
## with a different answer, and the ray already knows which one the player meant — a second binding would make
## the player choose in advance what the raycast can just tell them. X was the only unbound letter that reads
## as "mark" (O / P / U / Y were the others free).
##
## Rebindable; no controller default (the obvious pads are taken — matches Throw/Takedown/Claim/Wait/MinimapZoom).
var action_mark_waypoint: StringName = &"MarkWaypoint"
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

## THE single modal registry (M5 / T1). Every player-facing modal screen appears in ONE authored list, and all five
## surfaces derive from it: gameplay_suppressed (per-frame control gate), any_modal_open (don't-stack-a-menu guard),
## any_tab_blocking_open (Pip-Boy-tab refusal), any_station_music_open (the station-radio gate the StationMusic
## autoload polls), and close_all_modals (the death/quickload sweep). Registering a new screen = ONE row here + its
## project.godot [autoload] line — nothing else. A row carries BOTH flags, always: an omitted key is a crash, and
## writing `false` with a one-line reason is how the next screen author sees why a screen was left out.
## Built LAZILY: the screen autoloads register AFTER InputManager in [autoload], so they don't exist at _ready(); every
## query runs at runtime by which point they do.
##
## ⭐THE ROW FLAG IS `blocks_tabs`, NOT `pausing` (renamed 2026-08-09 when the station screens went REAL-TIME).
## It only ever fed the Pip-Boy-tab refusal, and "freezes the tree" was a PROXY for the real question — does this
## screen own the player's hands right now? That proxy died when shop / heal / level-up / respec / install / chess /
## atm stopped pausing (see atm_screen.gd's header for why), so the flag now names the question it actually answers.
## TRUE = a tab (Inventory / Stats / Implants / Map / Reputation / Journal) refuses to open over it; the tabs still switch
## freely among THEMSELVES via PlayerMenus.close_others. This is not cosmetic: two screens that both grabbed the
## mouse fight over Escape, and the loser restores the CAPTURED cursor under a menu that is still up — unclickable.
## NOTHING in this registry pauses the tree any more; the only remaining pause in the game is DialogueManager's.
var _modal_reg: Array[Dictionary] = []
var _modal_screens_cache: Array = []

func _ensure_modal_reg() -> void:
	if not _modal_reg.is_empty():
		return
	_modal_reg = [
		{screen = OptionsMenu, blocks_tabs = true, station_music = false},              # the settings menu is a takeover, not a tab — and it opens over the MAIN MENU where there is no world, and is where you go to turn music DOWN
		{screen = InventoryScreen, blocks_tabs = false, station_music = false},         # ⌄ the Pip-Boy tab group: these five switch among themselves; the PLAYER's own device, opened anywhere including mid-firefight — not a vendor's panel
		{screen = LootScreen, blocks_tabs = true, station_music = false},               # a container/corpse you are rummaging — owns the cursor; no proprietor and no speaker (it grabs the mouse BARE), so no radio
		{screen = ShopScreen, blocks_tabs = true, station_music = true},                # ⌄ the STATION screens: all real-time, all own the player's hands — and all answer with a StationSpeaker chirp, which is exactly why they all play the machine's radio
		{screen = StatsScreen, blocks_tabs = false, station_music = false},
		{screen = ReputationScreen, blocks_tabs = false, station_music = false},
		{screen = LevelUpScreen, blocks_tabs = true, station_music = true},
		{screen = RespecScreen, blocks_tabs = true, station_music = true},
		{screen = HealScreen, blocks_tabs = true, station_music = true},
		{screen = AtmScreen, blocks_tabs = true, station_music = true},                 # the Ledger terminal — the first station to go real-time (2026-08-08), and the chirp whose filter chain the radio's bus clones
		{screen = ChipInstallScreen, blocks_tabs = true, station_music = true},
		{screen = WeaponBenchScreen, blocks_tabs = true, station_music = true},         # the gunsmith bench — a station like its siblings: it grabs the mouse, and it chirps
		{screen = ChessScreen, blocks_tabs = true, station_music = true},               # a wagering kiosk is still a kiosk; flip this ONE word if a long match wears the loop thin
		{screen = QuestJournal, blocks_tabs = false, station_music = false},
		{screen = ImplantsScreen, blocks_tabs = false, station_music = false},          # the implants tab (rows toggle an implant off/on)
		{screen = MapScreen, blocks_tabs = false, station_music = false},               # the map tab — the HUD floorplan widget at panel size; read-only, and a tab like its siblings
		{screen = CharacterInspectScreen, blocks_tabs = false, station_music = false},  # fullscreen hero-view; a tab hotkey takes over FROM it by design
		{screen = SaveLoadScreen, blocks_tabs = false, station_music = false},          # manual save/load slot menu (the Options Dark-Souls posture)
		{screen = WaitScreen, blocks_tabs = true, station_music = false},               # the Wait panel — real-time, and it owns the cursor while you pick hours; waiting happens on a rooftop, not at a counter
	]
	for e in _modal_reg:
		_modal_screens_cache.append(e.screen)

## True while a NON-pausing overlay menu is up OR control is otherwise suppressed (a cutscene / the name-entry box).
## The gameplay control gates — move / jump / fire / aim / crouch / grapple — check this. Truth set is the
## 15 registry screens + the two control-only suppressors (byte-identical to the pre-registry OR-chain, plus
## each screen registered since).
##
## OS window focus is deliberately NOT a third suppressor here: the OS stops routing keyboard and clicks to an
## unfocused window, Godot itself releases held keys and every pressed action on focus loss (Input.release_pressed_events,
## from SceneTree's APPLICATION_FOCUS_OUT handler), and the pad is silenced by the ENGINE too — project.godot sets
## `input_devices/joypads/ignore_joypad_on_unfocused_application = true` (Project Settings → Input Devices → Joypads),
## which makes Input drop joypad events and release held joy buttons / axes / actions the moment the app loses focus.
## Without that flag SDL keeps reporting the stick through an alt-tab and the background window steers itself; with it
## nothing polls non-zero, so no gate is needed. tests/test_focus_input_lock.gd pins the flag ON. The one thing the
## flag can't cover — the CLICK that re-focuses the window firing the drawn weapon — is MouseInput's refocus latch.
## (Accepted residual: the mouse WHEEL is the one input Windows' hover-scroll still delivers to an unfocused window and
## Godot doesn't filter, so Hotbar Next/Prev can cycle a weapon in the background.)
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

## True if a screen that OWNS THE PLAYER'S HANDS is open (the `blocks_tabs` rows: Options, Loot, Wait, and the
## eight station screens). The Pip-Boy tabs (Inventory/Stats/Implants/Map/Reputation/Journal) refuse to open over these —
## but NOT over each other, since they switch siblings via PlayerMenus.close_others. THE WHOLE refusal set lives
## here: a guard that hand-names one more screen beside this call is the drift this registry exists to kill.
## (Was any_pausing_open() until 2026-08-09 — see the registry header for why the pause stopped being the test.)
func any_tab_blocking_open() -> bool:
	_ensure_modal_reg()
	for e in _modal_reg:
		if e.blocks_tabs and e.screen.is_open():
			return true
	return false

## True while a screen whose MACHINE has a radio is open — the `station_music` rows: the seven STATION screens
## (shop / level-up / respec / heal / atm / install / chess), which are EXACTLY the set that answers with a
## StationSpeaker.chirp() at its commit point. That identity is the rule, and keeping it in this one table is
## what stops the music boundary and the chirp boundary from ever drifting apart: the bed plays through a
## clone of that speaker's filter chain, so the music is coming out of the thing that just chirped. The
## Pip-Boy tabs, Loot, Wait and Options are deliberately OUT — the player's own device, a corpse, a rooftop,
## and the volume sliders themselves. Deliberately NOT the same set as any_tab_blocking_open(), which is a
## strict superset by exactly those last three.
## The StationMusic autoload POLLS this every frame; it never hooks the screens' opened/closed signals, which
## fire on REFUSE paths too and so cannot be refcounted.
func any_station_music_open() -> bool:
	_ensure_modal_reg()
	for e in _modal_reg:
		if e.station_music and e.screen.is_open():
			return true
	return false

## Close EVERY open modal (the death/respawn sweep and the quickload/quicksave chokepoint). Drives off the one
## registry, so a newly-registered screen is closed here automatically — no more hand-list drift (T1). Includes the
## NameEntryDialog (not a menu, but must not survive a death cinematic / scene reload floating over the world).
## This is a SWEEP, not a player action: the world closed these menus, the player didn't back out of them.
## So the whole loop runs under MenuStyle's quiet latch — otherwise dying with a menu group open fires a wall
## of close cues at once (up to one per registered screen) through a 4-voice pool. Set/cleared in the SAME
## function so an early return can never strand the UI mute.
func close_all_modals() -> void:
	MenuStyle.set_quiet(true)
	for m in _modal_screens():
		if m.is_open():
			m.close()
	if NameEntryDialog.is_open():
		NameEntryDialog.close()
	MenuStyle.set_quiet(false)

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
	# The shoulders are the only face controls nothing else claims, and L1/R1 is where a console shooter puts lean.
	# On a pad they're NOT shared with Interact/Takedown (those are Y and unbound), so a pad lean is unconditional.
	_bind_button(action_lean_left, JOY_BUTTON_LEFT_SHOULDER)
	_bind_button(action_lean_right, JOY_BUTTON_RIGHT_SHOULDER)
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
## readout ("[F] Talk to Kyle", "[Z] Pick Up"), tutorial `{action}` tokens, and dialogue prompts all resolve a
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

## True when two actions are bound to the SAME physical control — the seam the CONTEXTUAL-KEY rule runs on
## (scripts/player/lean.gd): "would pressing my lean key ALSO fire the verb that's waiting?". Read LIVE from the
## InputMap, so a rebind answers correctly the instant it lands — bind Lean Right off E and it stops sharing with
## Interact, so the lean stops deferring to it. An action always shares with itself. Compares the CONTROL, not the
## event object: modifiers, echo and pressed-state are irrelevant to "same key".
func actions_share_binding(a: StringName, b: StringName) -> bool:
	if a == b:
		return true
	if not InputMap.has_action(a) or not InputMap.has_action(b):
		return false
	for ea in InputMap.action_get_events(a):
		for eb in InputMap.action_get_events(b):
			if same_binding(ea, eb):
				return true
	return false

## Do these two InputEvents name the same physical control? Keys match on physical_keycode when both carry one
## (this project's [input] defaults are all physical) and fall back to keycode, so a hand-authored keycode-only
## event still compares. Different event CLASSES never match.
func same_binding(a: InputEvent, b: InputEvent) -> bool:
	var ka := a as InputEventKey
	var kb := b as InputEventKey
	if ka != null and kb != null:
		if ka.physical_keycode != 0 and kb.physical_keycode != 0:
			return ka.physical_keycode == kb.physical_keycode
		return ka.keycode != 0 and ka.keycode == kb.keycode
	var ma := a as InputEventMouseButton
	var mb := b as InputEventMouseButton
	if ma != null and mb != null:
		return ma.button_index == mb.button_index
	var ja := a as InputEventJoypadButton
	var jb := b as InputEventJoypadButton
	if ja != null and jb != null:
		return ja.button_index == jb.button_index
	var xa := a as InputEventJoypadMotion
	var xb := b as InputEventJoypadMotion
	if xa != null and xb != null:
		return xa.axis == xb.axis and signf(xa.axis_value) == signf(xb.axis_value)
	return false

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
