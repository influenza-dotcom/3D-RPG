extends GutTest
## F-P0-3b — the CLICK-ONLY overflow strip in GridInventoryView. An unplaced stack (placed_contents row x<0 —
## the grid is full, or the footprint is bigger than an empty grid; CharacterInventory._rehome_unplaced covers the
## free-cell case, so the strip handles the RESIDUAL) must be VISIBLE and takeable, not silently invisible: that's
## what lets a loot-only coin too big for a full corpse grid still be taken so the corpse drains and its ragdoll
## fades. Two layers of coverage: (1) an OFF-TREE build proves an unplaced stack actually gets a strip tile + is
## hit-tested (no _ready side effects — we never add_child the view, so no overlay / no mouse rig); (2) a
## source-string contract for the in-tree, mouse-driven bits (the click routing) that a unit can't exercise.

const VIEW_SRC := "res://scripts/ui/grid_inventory_view.gd"

## Build a bounded 1x1 bag carrying TWO 1x1 stacks: the second can't fit, so it's kept-but-unplaced (x<0). Seed
## with the grid OFF then enable_grid() too small — the documented "left unplaced (with a warning)" overflow path
## (add() with the grid on merely refuses a new stack, it never leaves one unplaced). Returns [inv, unplaced_key].
func _bag_with_one_unplaced() -> Array:
	var inv := CharacterInventory.new()
	var a := Item.new()  # distinct instances -> two separate stacks (add() stacks by item identity)
	var b := Item.new()
	inv.add(a, 1)
	inv.add(b, 1)
	inv.enable_grid(1, 1)  # one cell: the first stack places at (0,0), the second is left unplaced
	# enable_grid push_warning()s for the DOCUMENTED "left unplaced" overflow — an expected diagnostic on this path,
	# not a fault. GUT's error tracker would otherwise count it as an unexpected error and fail every test that binds
	# this fixture, so mark the tracked warning handled here (the strip's whole point is to render this overflow).
	for e in get_errors():
		e.handled = true
	var unplaced_key := -1
	for row in inv.placed_contents():
		if int(row["x"]) < 0:
			unplaced_key = int(row["key"])
	return [inv, unplaced_key, a, b]


func test_bag_actually_has_one_unplaced_stack() -> void:
	# Precondition for the rest: our fixture really produces exactly one unplaced (x<0) stack.
	var bag := _bag_with_one_unplaced()
	var inv: CharacterInventory = bag[0]
	assert_gte(int(bag[1]), 0, "the second 1x1 stack should be kept-but-unplaced in a 1x1 grid")
	var unplaced := 0
	for row in inv.placed_contents():
		if int(row["x"]) < 0:
			unplaced += 1
	assert_eq(unplaced, 1, "exactly one stack overflows a 1x1 grid holding two stacks")
	inv.free()


func test_unplaced_stack_renders_a_strip_tile_off_tree() -> void:
	# The core behavioural proof: binding a bag with one unplaced stack creates a tile for it in the strip BELOW
	# the grid. Off-tree (no add_child) so the view's _ready never runs — _overlay stays null and _sync_tiles'
	# move_child(_overlay,...) / queue_redraw guards all no-op, so every child is a GridTile.
	var bag := _bag_with_one_unplaced()
	var inv: CharacterInventory = bag[0]
	var view := GridInventoryView.new()  # NO add_child -> no _ready side effects
	view.bind(inv)
	# Two stacks -> two tiles now (before the fix the unplaced one was skipped -> only one tile).
	assert_eq(view.get_child_count(), 2, "both the placed and the unplaced stack get a tile (the strip renders the overflow)")
	assert_true(view._has_unplaced(), "the view sees the unplaced stack")
	assert_eq(view._unplaced_keys().size(), 1, "one stack is tracked for the strip")
	# Exactly one tile sits in the strip region (y at/below the strip's top edge); the placed tile is above it.
	var strip_top := view._strip_top()
	var in_strip := 0
	for child in view.get_children():
		if child.position.y >= strip_top:
			in_strip += 1
	assert_eq(in_strip, 1, "the one unplaced stack renders as a tile in the overflow strip below the grid")
	view.free()
	inv.free()


func test_strip_hit_test_resolves_a_position_to_the_unplaced_key() -> void:
	# The strip's hit-test (its whole click pathway — it's click-only, no drag) maps a local point inside the first
	# strip tile back to the unplaced stack's key, so the left/right-click branches in _gui_input can act on it.
	var bag := _bag_with_one_unplaced()
	var inv: CharacterInventory = bag[0]
	var unplaced_key: int = bag[1]
	var view := GridInventoryView.new()
	view.bind(inv)
	var rect := view._strip_rect(0)  # the first (only) unplaced tile's rect
	var hit := view._strip_key_at_local(rect.position + rect.size * 0.5)  # centre of that tile
	assert_eq(hit, unplaced_key, "clicking inside the strip tile resolves to the unplaced stack's key")
	# A point above the strip (up on the grid) is NOT a strip hit — the grid keeps its own hit-test.
	assert_eq(view._strip_key_at_local(Vector2(rect.position.x, -1.0)), -1,
		"a position off the strip returns no strip key")
	view.free()
	inv.free()


func test_strip_inert_when_grid_off() -> void:
	# With the grid OFF every row reads unplaced (x<0); the strip must stay inert then — no keys, no hit — so an
	# ungridded bag (a fresh corpse-copy / container before the loot screen grids it) renders as before.
	var inv := CharacterInventory.new()
	inv.add(Item.new(), 1)
	var view := GridInventoryView.new()
	view.bind(inv)
	assert_false(view._has_unplaced(), "grid off -> the strip is inert, not 'everything overflowed'")
	assert_eq(view._unplaced_keys().size(), 0, "no strip keys while the grid is off")
	assert_eq(view._strip_key_at_local(Vector2(1.0, 1.0)), -1, "no strip hit while the grid is off")
	view.free()
	inv.free()


func test_source_routes_strip_clicks_and_lays_out_the_strip() -> void:
	# Source-string contract for the in-tree, mouse-driven parts a unit can't drive. Assert _sync_tiles no longer
	# UNCONDITIONALLY skips x<0 (it now branches into the strip layout) and _gui_input routes strip clicks to the
	# same activate_requested / drop_requested signals the host already wires (so no host change).
	var src := FileAccess.get_file_as_string(VIEW_SRC)
	assert_true(src.contains("if rx < 0 and not strip_active:"),
		"_sync_tiles skips an unplaced row ONLY when the grid is off — no longer an unconditional continue")
	assert_true(src.contains("_strip_rect(strip_idx)"),
		"_sync_tiles lays unplaced stacks out into the overflow strip")
	assert_true(src.contains("_strip_key_at_local(mb.position)"),
		"_gui_input hit-tests the strip for both the left-click and right-click branches")
	assert_true(src.contains('activate_requested.emit(srow["item"])'),
		"a left-click on a strip tile emits activate_requested (take/equip) — same signal as a grid tile")
	assert_true(src.contains("key = _strip_key_at_local(mb.position)"),
		"a right-click on a strip tile routes into the existing drop_requested emit")
