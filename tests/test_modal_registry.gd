extends GutTest

## M5: modal-exclusion guards are centralized on InputManager (any_modal_open / any_tab_blocking_open) instead of a
## long inline is_open() list duplicated in every screen. This fixes the asymmetry where a station screen
## (shop/heal/level-up/respec) would open OVER the QuestJournal (and level-up over Respec), and gates the ray_cast
## interact key AND the weapon hotbar's slot keys over ALL menus. The Pip-Boy tab group (Inventory/Stats/Implants/Map/
## Reputation/Journal) still opens over its OWN siblings (it switches via PlayerMenus.close_others), so those are NOT blocked.
## gameplay_suppressed() is unchanged.
##
## ⭐2026-08-09: NO SCREEN IN THE REGISTRY PAUSES THE TREE ANY MORE. The station screens froze the world because
## they were "a transaction with an NPC" — but every one of them except the ATM is opened from a CONVERSATION that
## already paused, so the freeze was invisible there and glaring at a walk-up kiosk. They are all real-time now
## (dialogue still pauses on its own), and the registry flag that used to be `pausing` is `blocks_tabs`: the
## question it always really answered was "does this screen own the player's hands?", not "does it stop time".
##
## Most tests flip autoload screens' _is_open directly — setting the flag has no open/close side effects (no mouse
## grab, no cue) — and after_each resets every one so the wider suite is untouched. The death / quickload SWEEP is
## driven for real (InputManager.close_all_modals, and Player._close_open_modals on an off-tree Player whose _ready
## never runs), as is OptionsMenu's refusal to stack and the F5 quicksave key's refusal under an open menu (on an
## off-tree Player, where GameState.quicksave cannot write). What stays a source scan is only the cross-file guard
## lints below (a rule every screen file must follow). NOT pinned here: GameState._load_and_reload's own sweep before
## its reload_current_scene() — driving it in-tree would reload the scene the test runner lives in.

## Autoloads that pass the screen-shape test (is_open() + close()) but are deliberately NOT registry rows.
## NameEntryDialog suppresses CONTROL (gameplay_suppressed) and is swept by close_all_modals, but it is not a menu a
## shop refuses to stack over — see InputManager._modal_screens. Anything else that quacks like a screen must be a row.
const NOT_MENU_AUTOLOADS: Array[StringName] = [&"NameEntryDialog"]

var _prev_mouse_mode: Input.MouseMode


func before_each() -> void:
	_prev_mouse_mode = Input.mouse_mode


func after_each() -> void:
	# Reset every registered screen (future-proof: covers Chess/ChipInstall and any new row) so the wider suite is untouched.
	if OptionsMenu.is_open():
		OptionsMenu.close()  # the control case opens it for real; close() is the path that tears its pages down
	for s in InputManager._modal_screens():
		s.set(&"_is_open", false)
	NameEntryDialog.set(&"_is_open", false)
	MenuStyle.set_quiet(false)
	Input.action_release(&"Quicksave")  # the quicksave-key test presses it; never leave a held key for the next file
	if is_instance_valid(MenuStyle._denied_player):
		MenuStyle._denied_player.stop()  # the quicksave control press plays the denied blip; do not leave it sounding
	Input.mouse_mode = _prev_mouse_mode
	await wait_process_frames(1)  # Options' rebuilt tab pages are detached then queue_free'd; let them go


func test_tab_blocking_set_is_the_hands_owning_screens_not_the_pausing_ones() -> void:
	assert_false(InputManager.any_tab_blocking_open(), "nothing open -> a Pip-Boy tab may open")
	ShopScreen._is_open = true
	assert_true(InputManager.any_tab_blocking_open(), "an open Shop owns the player's hands — a tab must not stack on it")
	ShopScreen._is_open = false
	RespecScreen._is_open = true
	assert_true(InputManager.any_tab_blocking_open(), "…same for the respec confirm")
	RespecScreen._is_open = false
	# ⭐The whole point of the rename: these screens no longer pause, and they must STILL block tabs. Two screens
	# that both grabbed the mouse fight over Escape, and the loser restores the CAPTURED cursor under a menu that
	# is still up — an unclickable backpack. The ATM is the one that proved it (later autoload ⇒ eats Escape first).
	AtmScreen._is_open = true
	assert_true(InputManager.any_tab_blocking_open(), "the real-time ATM still blocks tabs — it owns the cursor even though it doesn't pause")
	assert_true(InputManager.any_modal_open(), "…and it is a modal (blocks stacking + suppresses gameplay while you bank)")
	AtmScreen._is_open = false
	ChessScreen._is_open = true
	assert_true(InputManager.any_tab_blocking_open(), "a real-time chess match blocks tabs too")
	ChessScreen._is_open = false
	QuestJournal._is_open = true
	assert_false(InputManager.any_tab_blocking_open(), "a Pip-Boy tab never blocks its own group — they switch via close_others")
	QuestJournal._is_open = false
	SaveLoadScreen._is_open = true
	assert_false(InputManager.any_tab_blocking_open(), "the SaveLoadScreen does NOT block tabs (the Options Dark-Souls posture)")
	assert_true(InputManager.any_modal_open(), "...but it IS a modal (blocks stacking + suppresses gameplay)")


func test_any_modal_open_covers_journal_and_excludes_self() -> void:
	assert_false(InputManager.any_modal_open(), "no modal open initially")
	QuestJournal._is_open = true
	assert_true(InputManager.any_modal_open(), "an open QuestJournal counts as a modal")
	# The M5 fix: a pausing modal's open() calls any_modal_open(self); an open QuestJournal must still block it (the
	# old inline lists omitted the Journal, so a shop opened over it).
	assert_true(InputManager.any_modal_open(ShopScreen), "an open QuestJournal blocks a Shop from opening over it")
	QuestJournal._is_open = false
	ShopScreen._is_open = true
	assert_false(InputManager.any_modal_open(ShopScreen), "a screen excludes ITSELF (its own open() guard won't self-block)")
	assert_true(InputManager.any_modal_open(), "...but with no exclude, the open Shop is detected")


func test_level_up_now_blocks_over_respec() -> void:
	# Regression for the level-up guard that omitted BOTH Respec and QuestJournal: any_modal_open(self) covers both.
	RespecScreen._is_open = true
	assert_true(InputManager.any_modal_open(LevelUpScreen), "an open Respec blocks LevelUp from opening over it (was omitted)")


func test_hotbar_slot_key_gate_blocks_realtime_tabs_but_not_backpack() -> void:
	# The hotbar's _unhandled_input evaluates exactly InputManager.any_modal_open(InventoryScreen) (the routing itself
	# is linted in test_guards_route_through_the_shared_helpers — the hotbar needs a live Player to drive). This pins
	# the predicate's answer for that call: a slot key must be SWALLOWED over the real-time Pip-Boy tabs (Stats/
	# Reputation/Journal) and the NPC-transaction screens — the pre-fix leak where the old inline list (options/loot
	# only) let a number key switch weapons over Stats / the Quest Journal. But with ONLY the backpack open the gate
	# must be FALSE, so the key falls through to assign-mode (New Vegas slotting) instead of being eaten.
	assert_false(InputManager.any_modal_open(InventoryScreen), "no menu open -> hotbar keys fire (gate open)")
	StatsScreen._is_open = true
	assert_true(InputManager.any_modal_open(InventoryScreen), "an open Stats tab (real-time, un-paused) blocks the slot key — the fixed leak")
	StatsScreen._is_open = false
	ShopScreen._is_open = true
	assert_true(InputManager.any_modal_open(InventoryScreen), "an open Shop blocks the slot key too")
	ShopScreen._is_open = false
	InventoryScreen._is_open = true
	assert_false(InputManager.any_modal_open(InventoryScreen), "the backpack is EXCLUDED — a slot key falls through to assign-mode, not swallowed")


func test_guards_route_through_the_shared_helpers() -> void:
	# Cross-file drift lint (a rule every screen file must follow, so it stays a scan): station screens and the other
	# don't-stack-a-menu screens (Options, Loot) guard via any_modal_open(self); tab-group screens via
	# any_tab_blocking_open(); ray_cast's interact gate via gameplay_suppressed(). One place (InputManager) registers a
	# screen, not every guard. Options' guard is also DRIVEN below (test_options_menu_refuses_to_open_over_another_modal);
	# Loot's can't be — every open path also refuses without a live Player, so a refusal proves nothing about the guard.
	for path in ["res://scripts/ui/shop_screen.gd", "res://scripts/ui/heal_screen.gd", "res://scripts/ui/level_up_screen.gd",
			"res://scripts/ui/respec_screen.gd", "res://scripts/ui/weapon_bench_screen.gd",
			"res://scripts/ui/options_menu.gd", "res://scripts/ui/loot_screen.gd"]:
		assert_true(FileAccess.get_file_as_string(path).contains("InputManager.any_modal_open(self)"), "%s should guard via InputManager.any_modal_open(self)" % path)
	# ⭐The tab guards must name NOTHING but the registry predicate. Hand-naming a screen beside it is exactly the
	# drift this registry exists to kill: the refusal set changed twice in two days (the ATM, then every station),
	# and a guard carrying its own list would have silently missed both.
	for path in ["res://scripts/ui/stats_screen.gd", "res://scripts/ui/reputation_screen.gd", "res://scripts/ui/inventory_screen.gd", "res://scripts/ui/quest_journal.gd", "res://scripts/ui/implants_screen.gd", "res://scripts/ui/map_screen.gd", "res://scripts/ui/character_inspect_screen.gd"]:
		var tab_src := FileAccess.get_file_as_string(path)
		assert_true(tab_src.contains("InputManager.any_tab_blocking_open()"), "%s (tab group) should guard via InputManager.any_tab_blocking_open()" % path)
		assert_false(tab_src.contains("LootScreen.is_open()"), "%s should NOT hand-name LootScreen — it is a blocks_tabs row in the registry now" % path)
		assert_false(tab_src.contains("AtmScreen.is_open()"), "%s should NOT hand-name AtmScreen — it is a blocks_tabs row in the registry now" % path)
	# ⭐NOTHING in the registry pauses the tree any more. A walk-up station must not stop the city (atm_screen.gd's
	# header carries the argument); a station opened from dialogue is already frozen by the conversation. Only the
	# screen itself can flip get_tree().paused, so the registry row cannot pin this — the source has to.
	for path in ["res://scripts/ui/atm_screen.gd", "res://scripts/ui/shop_screen.gd", "res://scripts/ui/heal_screen.gd",
			"res://scripts/ui/level_up_screen.gd", "res://scripts/ui/respec_screen.gd",
			"res://scripts/ui/chip_install_screen.gd", "res://scripts/ui/weapon_bench_screen.gd",
			"res://scripts/ui/chess_screen.gd"]:
		assert_false(FileAccess.get_file_as_string(path).contains("get_tree().paused"),
			"%s must NOT touch get_tree().paused — the station screens are real-time; the only pause left in the game is DialogueManager's" % path)
	assert_true(FileAccess.get_file_as_string("res://scripts/components/ray_cast.gd").contains("InputManager.gameplay_suppressed()"), "ray_cast interact gate should route through InputManager.gameplay_suppressed() (T2 hardened it from any_modal_open to also cover cutscenes + the name-entry dialog; gameplay_suppressed still derives from the modal registry)")
	# The weapon hotbar's slot-key gate is the same class of raw-input consumer, but it EXCLUDES the backpack
	# (InventoryScreen) — a slot key ASSIGNS the hovered item there instead of activating, so that path must fall
	# through the gate. Assert the exclusion arg, not just the routing (a bare any_modal_open() would swallow assign-mode).
	assert_true(FileAccess.get_file_as_string("res://scripts/ui/hotbar.gd").contains("InputManager.any_modal_open(InventoryScreen)"), "hotbar slot-key gate should route through InputManager.any_modal_open(InventoryScreen)")


## Every screen a PLAYER can summon on their own — a hotkey, Escape, or the Options row — must ALSO consult the
## shared mid-death gate (PlayerMenus.player_alive), not just the registry guard above. These screens all run
## PROCESS_MODE_ALWAYS and none of them pauses the tree, so their open hotkeys keep firing right through the death
## cinematic AND the in-place checkpoint revive, where the player is still in-tree with the _dead latch set.
## Player.die() sweeps them shut (close_all_modals) and _respawn_at_checkpoint sweeps again, but a sweep can only
## close what is open — nothing but this gate stops a key press RE-opening a menu over the black screen.
##
## OptionsMenu was the hole this test exists for: it was the ONE self-opening screen without the gate, so Escape
## opened the full settings menu (freed cursor, Main Menu / Save-Load / Quit rows, live rebind capture) over the
## death card. The gate is per-screen by necessity — it can't be folded into the registry, because the world-driven
## screens (Loot/Shop/Heal/LevelUp/Respec/ChipInstall/Chess) are opened BY an interaction that is already blocked
## while dead. So the list is hand-maintained, and this sweep is what keeps the next one from being forgotten.
func test_self_opening_screens_all_gate_on_the_mid_death_predicate() -> void:
	for path in [
		"res://scripts/ui/options_menu.gd",             # Escape — the regression this test was written for
		"res://scripts/ui/inventory_screen.gd",         # Tab
		"res://scripts/ui/stats_screen.gd",             # Pip-Boy tab hotkey / tab strip
		"res://scripts/ui/reputation_screen.gd",
		"res://scripts/ui/quest_journal.gd",
		"res://scripts/ui/implants_screen.gd",          # the implants tab (I)
		"res://scripts/ui/map_screen.gd",               # the map tab (M)
		"res://scripts/ui/character_inspect_screen.gd", # fullscreen hero-view takeover
		"res://scripts/ui/save_load_screen.gd",         # reached from the Options bottom row
		"res://scripts/ui/wait_screen.gd",              # Wait (T)
	]:
		assert_true(FileAccess.get_file_as_string(path).contains("PlayerMenus.player_alive("),
			"%s opens from a player hotkey while PROCESS_MODE_ALWAYS, so its open() must refuse mid-death via PlayerMenus.player_alive() — else the key re-opens it over the death cinematic / in-place revive" % path)


## Membership DERIVED from the live autoload set instead of a hand count: every autoload shaped like a screen
## (is_open() + close()) must be a registry row. A screen that forgets its row is invisible to every guard at once —
## a shop stacks over it, gameplay keeps firing under it, and the death sweep leaves it floating over the cinematic.
## This is the test that historically-forgotten screens (QuestJournal, Chess, CharacterInspect, ...) would have failed.
func test_every_screen_shaped_autoload_is_a_registry_row() -> void:
	var registered := InputManager._modal_screens()
	var screen_autoloads := 0
	for prop in ProjectSettings.get_property_list():
		var key := String(prop.name)
		if not key.begins_with("autoload/"):
			continue
		var autoload_name := key.trim_prefix("autoload/")
		var node := get_tree().root.get_node_or_null(NodePath(autoload_name))
		if node == null or not (node.has_method(&"is_open") and node.has_method(&"close")):
			continue
		screen_autoloads += 1
		if NOT_MENU_AUTOLOADS.has(StringName(autoload_name)):
			assert_false(registered.has(node),
				"%s is a control-only suppressor, not a menu row — registering it would make every shop refuse to open over a name box" % autoload_name)
			continue
		assert_true(registered.has(node),
			"the %s autoload has is_open()/close() but no row in InputManager._modal_reg — shops would stack over it, gameplay would fire under it, and the death sweep would leave it open" % autoload_name)
	assert_gt(screen_autoloads, NOT_MENU_AUTOLOADS.size(), "the autoload scan found no screens at all — the scan is broken, so membership went unchecked")
	assert_eq(screen_autoloads, registered.size() + NOT_MENU_AUTOLOADS.size(),
		"every registry row must be a live screen autoload (a row pointing at anything else is dead weight in every guard)")


func test_name_entry_box_suppresses_control_but_is_not_a_stackable_menu() -> void:
	assert_false(InputManager.gameplay_suppressed(), "setup: nothing open")
	NameEntryDialog._is_open = true
	assert_true(InputManager.gameplay_suppressed(),
		"typing a pet's name must not also walk / fire the character — the name box suppresses gameplay control")
	assert_false(InputManager.any_modal_open(),
		"...but it is not a registry menu: any_modal_open (the don't-stack-a-menu guard) does not count it")


func test_gameplay_suppressed_fires_for_every_registered_modal() -> void:
	# Pin the byte-identical truth set: gameplay_suppressed() is true iff any registry screen is open (plus the two
	# control-only suppressors, covered by their own paths).
	assert_false(InputManager.gameplay_suppressed(), "nothing open -> gameplay not suppressed")
	for s in InputManager._modal_screens():
		s.set(&"_is_open", true)
		assert_true(InputManager.gameplay_suppressed(), "an open %s suppresses gameplay" % s)
		s.set(&"_is_open", false)


## The blocks_tabs column, pinned as a whole. It is the one piece of registry DATA with no other test — and
## getting a row wrong is silent: a false where true belongs strands the cursor under a stacked menu, a true
## where false belongs makes a Pip-Boy tab refuse to open with no feedback at all.
func test_every_registry_row_declares_the_right_tab_posture() -> void:
	var blocks := [OptionsMenu, LootScreen, ShopScreen, LevelUpScreen, RespecScreen, HealScreen, AtmScreen,
			ChipInstallScreen, WeaponBenchScreen, ChessScreen, WaitScreen, CrashReportScreen]
	var allows := [InventoryScreen, StatsScreen, ReputationScreen, QuestJournal, ImplantsScreen, MapScreen,
			CharacterInspectScreen, SaveLoadScreen]
	for s in blocks:
		s.set(&"_is_open", true)
		assert_true(InputManager.any_tab_blocking_open(), "%s owns the player's hands — a Pip-Boy tab must refuse over it" % s)
		assert_true(InputManager.any_modal_open(), "%s is a modal — nothing else may stack over it" % s)
		s.set(&"_is_open", false)
	for s in allows:
		s.set(&"_is_open", true)
		assert_false(InputManager.any_tab_blocking_open(), "%s must NOT block a Pip-Boy tab (the group switches freely)" % s)
		s.set(&"_is_open", false)
	assert_eq(blocks.size() + allows.size(), InputManager._modal_screens().size(),
		"every registered screen is accounted for above — a new row must pick a side here, not inherit one silently")


## THE sweep (death, respawn, quickload): every open screen AND the name-entry box close in one call, and the whole
## sweep runs under MenuStyle's quiet latch — dying with a menu group open must not fire a wall of close cues — which
## is released again afterwards, or every menu in the rest of the session plays silent.
func test_close_all_modals_shuts_open_screens_and_the_name_box_under_the_quiet_latch() -> void:
	var quiet_at_close: Array = []
	var record_quiet := func() -> void: quiet_at_close.append(bool(MenuStyle.get(&"_quiet")))
	WaitScreen.closed.connect(record_quiet)
	WaitScreen._is_open = true
	ReputationScreen._is_open = true
	NameEntryDialog._is_open = true
	assert_true(InputManager.gameplay_suppressed(), "setup: two screens and the name box are up")
	InputManager.close_all_modals()
	WaitScreen.closed.disconnect(record_quiet)
	assert_false(WaitScreen.is_open(), "the sweep must close an open standalone screen (Wait)")
	assert_false(ReputationScreen.is_open(), "the sweep must close an open Pip-Boy tab (Reputation)")
	assert_false(NameEntryDialog.is_open(),
		"the sweep must also close the name-entry box — it is not a registry row, and a box left open floats over the death cinematic")
	assert_eq(quiet_at_close, [true],
		"a screen closed BY the sweep must close under MenuStyle's quiet latch (one close event, muted) — else death fires a burst of close cues")
	assert_false(bool(MenuStyle.get(&"_quiet")),
		"the quiet latch must be released after the sweep, or every later menu cue in the session is silent")
	assert_false(InputManager.gameplay_suppressed(), "nothing is left suppressing control after the sweep")


## Player.die() / the respawn / quickload reach the sweep through Player._close_open_modals. Driven on an off-tree
## Player (its _ready never runs; weapon_system stays null, so the spray-picker leg is skipped) — the registry leg is
## the one that must close every screen, including one registered long after the Player was written.
func test_player_death_sweep_closes_every_open_screen() -> void:
	var player := Player.new()
	QuestJournal._is_open = true
	CrashReportScreen._is_open = true
	player._close_open_modals()
	assert_false(QuestJournal.is_open(), "the player's death sweep must close an open Quest Journal")
	assert_false(CrashReportScreen.is_open(),
		"the player's death sweep must close the newest registry row too — it delegates to the registry, not a hand list")
	assert_false(InputManager.any_modal_open(), "no registered screen survives the player's death sweep")
	player.free()


## The don't-stack guard on the screen a player opens from ANY state (Escape). The control case is the point: the
## same open() with nothing else up DOES open, so the refusal is the registry guard's, not some other bail.
func test_options_menu_refuses_to_open_over_another_modal() -> void:
	ShopScreen._is_open = true
	OptionsMenu.open()
	assert_false(OptionsMenu.is_open(),
		"Escape over an open Shop must not stack the Options menu on it (two screens would fight over the cursor and Escape)")
	ShopScreen._is_open = false
	OptionsMenu.open()
	assert_true(OptionsMenu.is_open(), "control: with nothing else up the same open() goes through")


## A HUD stand-in that records what the Player toasts (Player.notify_toast speaks only through `ui`). Never added to
## the tree, so none of the real HUD's build runs.
class _ToastSpy extends UI:
	var toasts: Array = []
	func push_toast(text: String, _color: Color) -> void:
		toasts.append(text)


## F5 under an open menu, DRIVEN on an off-tree Player (its _ready never runs). Off-tree, GameState.quicksave refuses to
## write (its own is_inside_tree guard, so no save file is touched on either pass) and the key handler answers that
## refused write with the "Quicksave failed" toast, which makes the toast the observable of whether the F5 branch ran.
## CONTROL: the same press with nothing open DOES reach the branch, so the silence under the menu is the
## gameplay_suppressed() gate's, not an unbound key or a press the handler never saw. Released in after_each.
func test_quicksave_key_does_nothing_under_an_open_menu() -> void:
	var player := Player.new()
	var spy := _ToastSpy.new()
	player.ui = spy
	WaitScreen._is_open = true
	Input.action_press(&"Quicksave")
	player._update_save_input()
	assert_eq(spy.toasts, [],
		"F5 under an open menu must not run the quicksave branch at all (no save attempt, no toast) - else F5/F9 act from behind a menu")
	WaitScreen._is_open = false
	player._update_save_input()
	assert_eq(spy.toasts, [PlayerText.TOAST_QUICKSAVE_FAILED],
		"control: the same F5 press with nothing open reaches the quicksave branch (off-tree, its refused write toasts the failure)")
	player.ui = null
	spy.free()
	player.free()
