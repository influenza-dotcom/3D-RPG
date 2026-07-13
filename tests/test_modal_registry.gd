extends GutTest

## M5: modal-exclusion guards are centralized on InputManager (any_modal_open / any_pausing_open) instead of a long
## inline is_open() list duplicated in every screen. This fixes the asymmetry where a pausing NPC-transaction screen
## (shop/heal/level-up/respec) would open OVER the QuestJournal (and level-up over Respec), and gates the ray_cast
## interact key AND the weapon hotbar's slot keys over ALL menus. The Pip-Boy tab group (Inventory/Stats/Reputation/
## Journal) still opens over its OWN siblings (it switches via PlayerMenus.close_others), so those are NOT blocked.
## gameplay_suppressed() is unchanged.
##
## The tests flip autoload screens' _is_open directly — setting the flag has no open/close side effects (no mouse
## grab, no pause) — and reset every one in after_each so the wider suite is untouched.


func after_each() -> void:
	# Reset every registered screen (future-proof: covers Chess/ChipInstall and any new row) so the wider suite is untouched.
	for s in InputManager._modal_screens():
		s.set(&"_is_open", false)


func test_any_pausing_open_detects_only_transaction_screens() -> void:
	assert_false(InputManager.any_pausing_open(), "no pausing screen open initially")
	ShopScreen._is_open = true
	assert_true(InputManager.any_pausing_open(), "an open Shop is a pausing modal")
	ShopScreen._is_open = false
	RespecScreen._is_open = true
	assert_true(InputManager.any_pausing_open(), "an open Respec is a pausing modal")
	RespecScreen._is_open = false
	QuestJournal._is_open = true
	assert_false(InputManager.any_pausing_open(), "the QuestJournal (a real-time Pip-Boy tab) is NOT a pausing modal")


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
	# Drift guard: pausing modals guard via any_modal_open(self); tab-group screens via any_pausing_open(); ray_cast's
	# interact gate via any_modal_open(). One place (InputManager) registers a screen, not every guard.
	for path in ["res://scripts/ui/shop_screen.gd", "res://scripts/ui/heal_screen.gd", "res://scripts/ui/level_up_screen.gd", "res://scripts/ui/respec_screen.gd"]:
		assert_string_contains(FileAccess.get_file_as_string(path), "InputManager.any_modal_open(self)", "%s (pausing) should guard via InputManager.any_modal_open(self)" % path)
	for path in ["res://scripts/ui/stats_screen.gd", "res://scripts/ui/reputation_screen.gd", "res://scripts/ui/inventory_screen.gd", "res://scripts/ui/quest_journal.gd"]:
		assert_string_contains(FileAccess.get_file_as_string(path), "InputManager.any_pausing_open()", "%s (tab group) should guard via InputManager.any_pausing_open()" % path)
	assert_string_contains(FileAccess.get_file_as_string("res://scripts/components/ray_cast.gd"), "InputManager.gameplay_suppressed()", "ray_cast interact gate should route through InputManager.gameplay_suppressed() (T2 hardened it from any_modal_open to also cover cutscenes + the name-entry dialog; gameplay_suppressed still derives from the modal registry)")
	# The weapon hotbar's slot-key gate is the same class of raw-input consumer, but it EXCLUDES the backpack
	# (InventoryScreen) — a slot key ASSIGNS the hovered item there instead of activating, so that path must fall
	# through the gate. Assert the exclusion arg, not just the routing (a bare any_modal_open() would swallow assign-mode).
	assert_string_contains(FileAccess.get_file_as_string("res://scripts/ui/hotbar.gd"), "InputManager.any_modal_open(InventoryScreen)", "hotbar slot-key gate should route through InputManager.any_modal_open(InventoryScreen)")


func test_registry_size_and_membership() -> void:
	# T1: pin the registry so the historically-forgotten screens force a deliberate test edit when a new screen lands.
	var screens := InputManager._modal_screens()
	assert_eq(screens.size(), 12, "the modal registry holds all 12 player-facing screens")
	assert_true(screens.has(ChessScreen), "ChessScreen is registered (the newest — was missed by the death sweep)")
	assert_true(screens.has(ChipInstallScreen), "ChipInstallScreen is registered")
	assert_true(screens.has(QuestJournal), "QuestJournal is registered (historically forgotten)")


func test_gameplay_suppressed_fires_for_every_registered_modal() -> void:
	# Pin the byte-identical truth set: gameplay_suppressed() is true iff any registry screen is open (plus the two
	# control-only suppressors, covered by their own paths).
	assert_false(InputManager.gameplay_suppressed(), "nothing open -> gameplay not suppressed")
	for s in InputManager._modal_screens():
		s.set(&"_is_open", true)
		assert_true(InputManager.gameplay_suppressed(), "an open %s suppresses gameplay" % s)
		s.set(&"_is_open", false)


func test_chess_and_chipinstall_are_pausing() -> void:
	ChessScreen._is_open = true
	assert_true(InputManager.any_pausing_open(), "an open Chess match pauses the tree")
	assert_true(InputManager.any_modal_open(), "...and counts as a modal")
	ChessScreen._is_open = false
	ChipInstallScreen._is_open = true
	assert_true(InputManager.any_pausing_open(), "an open chip-install screen pauses the tree")
	assert_true(InputManager.any_modal_open(), "...and counts as a modal")


func test_close_sweep_and_gates_route_through_registry() -> void:
	# T1 drift guard: the death sweep, the two surviving inline open-gates, and the quicksave/reload chokepoint all
	# derive from the one registry — a new screen is covered without editing any of these by hand.
	var player_src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_string_contains(player_src, "InputManager.close_all_modals()", "_close_open_modals delegates to the registry sweep")
	assert_string_contains(player_src, "if InputManager.gameplay_suppressed()", "quicksave/quickload is gated on gameplay_suppressed()")
	var im_src := FileAccess.get_file_as_string("res://managers/InputManager.gd")
	assert_string_contains(im_src, "NameEntryDialog.close()", "close_all_modals also closes the name-entry box")
	assert_string_contains(FileAccess.get_file_as_string("res://scripts/ui/options_menu.gd"), "InputManager.any_modal_open(self)", "OptionsMenu open-gate routes through the registry")
	assert_string_contains(FileAccess.get_file_as_string("res://scripts/ui/loot_screen.gd"), "InputManager.any_modal_open(self)", "LootScreen open-gate routes through the registry")
	assert_string_contains(FileAccess.get_file_as_string("res://managers/GameState.gd"), "close_all_modals()", "_load_and_reload closes modals before the scene reload")
