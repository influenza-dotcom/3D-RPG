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
## The tests flip autoload screens' _is_open directly — setting the flag has no open/close side effects (no mouse
## grab, no cue) — and reset every one in after_each so the wider suite is untouched.


func after_each() -> void:
	# Reset every registered screen (future-proof: covers Chess/ChipInstall and any new row) so the wider suite is untouched.
	for s in InputManager._modal_screens():
		s.set(&"_is_open", false)


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
	# The hotbar's _unhandled_input evaluates exactly InputManager.any_modal_open(InventoryScreen). Encode that
	# contract behaviorally: a slot key must be SWALLOWED over the real-time Pip-Boy tabs (Stats/Reputation/Journal)
	# and the NPC-transaction screens — the pre-fix leak where the old inline list (options/loot only) let a number
	# key switch weapons over Stats / the Quest Journal. But with ONLY the backpack open the gate must be FALSE, so
	# the key falls through to assign-mode (New Vegas slotting) instead of being eaten.
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
	# Drift guard: station screens guard via any_modal_open(self); tab-group screens via any_tab_blocking_open();
	# ray_cast's interact gate via gameplay_suppressed(). One place (InputManager) registers a screen, not every guard.
	for path in ["res://scripts/ui/shop_screen.gd", "res://scripts/ui/heal_screen.gd", "res://scripts/ui/level_up_screen.gd", "res://scripts/ui/respec_screen.gd", "res://scripts/ui/weapon_bench_screen.gd"]:
		assert_true(FileAccess.get_file_as_string(path).contains("InputManager.any_modal_open(self)"), "%s (station) should guard via InputManager.any_modal_open(self)" % path)
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


func test_registry_size_and_membership() -> void:
	# T1: pin the registry so the historically-forgotten screens force a deliberate test edit when a new screen lands.
	var screens := InputManager._modal_screens()
	assert_eq(screens.size(), 19, "the modal registry holds all 19 player-facing screens")
	assert_true(screens.has(AtmScreen), "AtmScreen is registered (the Ledger terminal; real-time, unlike its station siblings)")
	assert_true(screens.has(ChessScreen), "ChessScreen is registered (was missed by the death sweep)")
	assert_true(screens.has(ChipInstallScreen), "ChipInstallScreen is registered")
	assert_true(screens.has(WeaponBenchScreen), "WeaponBenchScreen is registered (the gunsmith bench — a station like its siblings: it grabs the mouse, and it chirps)")
	assert_true(screens.has(QuestJournal), "QuestJournal is registered (historically forgotten)")
	assert_true(screens.has(CharacterInspectScreen), "CharacterInspectScreen is registered")
	assert_true(screens.has(SaveLoadScreen), "SaveLoadScreen is registered (the manual save/load slot menu; non-pausing)")
	assert_true(screens.has(ImplantsScreen), "ImplantsScreen is registered (the implants tab; non-pausing)")
	assert_true(screens.has(WaitScreen), "WaitScreen is registered (the Wait panel; real-time, and it owns the cursor while you pick hours)")
	assert_true(screens.has(MapScreen), "MapScreen is registered (the newest — the map tab; non-pausing, and a tab like its five siblings)")


func test_gameplay_suppressed_fires_for_every_registered_modal() -> void:
	# Pin the byte-identical truth set: gameplay_suppressed() is true iff any registry screen is open (plus the two
	# control-only suppressors, covered by their own paths).
	assert_false(InputManager.gameplay_suppressed(), "nothing open -> gameplay not suppressed")
	for s in InputManager._modal_screens():
		s.set(&"_is_open", true)
		assert_true(InputManager.gameplay_suppressed(), "an open %s suppresses gameplay" % s)
		s.set(&"_is_open", false)


func test_chess_and_chipinstall_are_registered_stations() -> void:
	ChessScreen._is_open = true
	assert_true(InputManager.any_tab_blocking_open(), "an open Chess match owns the player's hands")
	assert_true(InputManager.any_modal_open(), "...and counts as a modal")
	ChessScreen._is_open = false
	ChipInstallScreen._is_open = true
	assert_true(InputManager.any_tab_blocking_open(), "an open chip-install screen owns the player's hands")
	assert_true(InputManager.any_modal_open(), "...and counts as a modal")


## The blocks_tabs column, pinned as a whole. It is the one piece of registry DATA with no other test — and
## getting a row wrong is silent: a false where true belongs strands the cursor under a stacked menu, a true
## where false belongs makes a Pip-Boy tab refuse to open with no feedback at all.
func test_every_registry_row_declares_the_right_tab_posture() -> void:
	var blocks := [OptionsMenu, LootScreen, ShopScreen, LevelUpScreen, RespecScreen, HealScreen, AtmScreen,
			ChipInstallScreen, WeaponBenchScreen, ChessScreen, WaitScreen]
	var allows := [InventoryScreen, StatsScreen, ReputationScreen, QuestJournal, ImplantsScreen, MapScreen,
			CharacterInspectScreen, SaveLoadScreen]
	for s in blocks:
		s.set(&"_is_open", true)
		assert_true(InputManager.any_tab_blocking_open(), "%s owns the player's hands — a Pip-Boy tab must refuse over it" % s)
		s.set(&"_is_open", false)
	for s in allows:
		s.set(&"_is_open", true)
		assert_false(InputManager.any_tab_blocking_open(), "%s must NOT block a Pip-Boy tab (the group switches freely)" % s)
		s.set(&"_is_open", false)
	assert_eq(blocks.size() + allows.size(), InputManager._modal_screens().size(),
		"every registered screen is accounted for above — a new row must pick a side here, not inherit one silently")


func test_close_sweep_and_gates_route_through_registry() -> void:
	# T1 drift guard: the death sweep, the two surviving inline open-gates, and the quicksave/reload chokepoint all
	# derive from the one registry — a new screen is covered without editing any of these by hand.
	var player_src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true(player_src.contains("InputManager.close_all_modals()"), "_close_open_modals delegates to the registry sweep")
	assert_true(player_src.contains("if InputManager.gameplay_suppressed()"), "quicksave/quickload is gated on gameplay_suppressed()")
	var im_src := FileAccess.get_file_as_string("res://managers/InputManager.gd")
	assert_true(im_src.contains("NameEntryDialog.close()"), "close_all_modals also closes the name-entry box")
	assert_true(FileAccess.get_file_as_string("res://scripts/ui/options_menu.gd").contains("InputManager.any_modal_open(self)"), "OptionsMenu open-gate routes through the registry")
	assert_true(FileAccess.get_file_as_string("res://scripts/ui/loot_screen.gd").contains("InputManager.any_modal_open(self)"), "LootScreen open-gate routes through the registry")
	assert_true(FileAccess.get_file_as_string("res://managers/GameState.gd").contains("close_all_modals()"), "_load_and_reload closes modals before the scene reload")
