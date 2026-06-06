extends GutTest
## Smoke tests for the InventoryScreen autoload — it builds its overlay at startup and its open/close API
## is SAFE with no player present (the start-menu path: open() must early-return, never crash or show an
## empty overlay). The WITH-player behaviour (list build + click-to-equip) needs a live Player in the tree
## and is verified by manual playtest, exactly as test_options_menu.gd leaves OptionsMenu's in-game freeze.

func after_each() -> void:
	if InventoryScreen.is_open():
		InventoryScreen.close()

func test_autoload_and_ui_built() -> void:
	assert_not_null(InventoryScreen, "InventoryScreen autoload should be registered")
	assert_not_null(InventoryScreen._root, "the overlay root Control should be built at startup")
	assert_not_null(InventoryScreen._list, "the item-list container should be built at startup")

func test_starts_closed() -> void:
	assert_false(InventoryScreen.is_open(), "the backpack starts closed")

func test_open_is_safe_and_respects_player_presence() -> void:
	# Calling open() must never crash. With no human player in the tree (the usual test + start-menu case)
	# it must early-return and stay closed; if some suite left a player in the tree, just keep state
	# consistent. The no-player invariant is the one that matters — it's the start-menu safety guard.
	var had_player := InventoryScreen._find_real_player() != null
	InventoryScreen.open()
	if had_player:
		assert_eq(InventoryScreen.is_open(), InventoryScreen._root.visible,
			"open state must match overlay visibility")
	else:
		assert_false(InventoryScreen.is_open(),
			"open() with no player must stay closed — the start menu has no backpack to show")
	InventoryScreen.close()

func test_close_when_closed_is_safe() -> void:
	assert_false(InventoryScreen.is_open(), "precondition: closed")
	InventoryScreen.close()  # must be a harmless no-op, not crash or flip state
	assert_false(InventoryScreen.is_open(), "close() while already closed stays closed")
