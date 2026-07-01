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
	assert_not_null(InventoryScreen._grid_view, "the Tetris grid view should be built at startup")

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


func test_grid_hover_ring_tracks_stack_by_key_not_item() -> void:
	# Regression: the grid's hover ring positions by the hovered STACK's KEY, so two stacks of the SAME item (two
	# dog crates share one Item template) ring the tile actually under the cursor — not the first stack of that item
	# (the old draw_overlay looped _rows and rang the FIRST row matching _hovered_item). Off-tree: no add_child ->
	# no _ready -> _overlay is null, so _set_hovered safely skips its redraw; we assert the tracked key directly.
	var view := GridInventoryView.new()
	var crate := Item.new()  # one shared template, carried as two stacks
	view._set_hovered(7, crate)
	assert_eq(view._hovered_key, 7, "hovering the first crate stack tracks its key")
	view._set_hovered(9, crate)  # SAME item, DIFFERENT stack (the second crate tile)
	assert_eq(view._hovered_key, 9,
		"hovering the SECOND stack of the same item moves the tracked key — the ring follows the actual tile, not stack #1")
	view._set_hovered(-1, null)
	assert_eq(view._hovered_key, -1, "leaving the grid clears the hovered key so no ring lingers")
	view.free()
	crate = null
