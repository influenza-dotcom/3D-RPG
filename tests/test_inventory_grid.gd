extends GutTest

## InventoryGrid: the pure, Node-free spatial placement model for the Tetris inventory. Every method takes only
## ints / opaque keys and touches no tree, no resources — so we .new() it and assert placement logic directly
## off-tree, releasing the ref per CLAUDE.md. Loaded by PATH (not the class_name) so the test resolves even if
## the global class cache hasn't scanned the new script yet.

const GRID := preload("res://scripts/inventory/inventory_grid.gd")
const ITEM := preload("res://scripts/items/item.gd")

func _grid(cols: int, rows: int):
	var g = GRID.new()
	g.configure(cols, rows)
	return g

# --- configure / bounds ---

func test_configure_sets_dimensions_and_starts_empty() -> void:
	var g = _grid(10, 6)
	assert_eq(g.cols, 10, "cols set")
	assert_eq(g.rows, 6, "rows set")
	assert_eq(g.count(), 0, "no placements yet")
	assert_true(g.is_free(0, 0), "top-left starts free")
	assert_true(g.is_free(9, 5), "bottom-right starts free")
	g = null

func test_in_bounds_rejects_offgrid_and_nonpositive() -> void:
	var g = _grid(4, 4)
	assert_true(g.in_bounds(0, 0, 4, 4), "the whole grid is in bounds")
	assert_false(g.in_bounds(2, 2, 3, 1), "a footprint running off the right edge is out of bounds")
	assert_false(g.in_bounds(-1, 0, 1, 1), "a negative origin is out of bounds")
	assert_false(g.in_bounds(0, 0, 0, 1), "a zero-width footprint is invalid")
	g = null

# --- can_place / place ---

func test_can_place_and_place_marks_cells() -> void:
	var g = _grid(5, 5)
	assert_true(g.can_place(1, 1, 2, 2), "a 2x2 fits on an empty grid")
	assert_true(g.place(&"box", 1, 1, 2, 2), "place succeeds")
	assert_eq(g.count(), 1, "one placement")
	assert_false(g.is_free(1, 1), "covered cell is occupied")
	assert_false(g.is_free(2, 2), "and the far corner of the footprint")
	assert_true(g.is_free(3, 3), "a cell outside the footprint stays free")
	assert_eq(g.placement_of(&"box"), {"x": 1, "y": 1, "w": 2, "h": 2}, "placement records the footprint")
	g = null

func test_place_rejects_overlap_and_out_of_bounds() -> void:
	var g = _grid(5, 5)
	g.place(&"a", 0, 0, 2, 2)
	assert_false(g.can_place(1, 1, 2, 2), "overlapping the existing 2x2 is blocked")
	assert_false(g.place(&"b", 1, 1, 2, 2), "so placing there fails")
	assert_false(g.has_key(&"b"), "the rejected placement was not recorded")
	assert_false(g.place(&"c", 4, 4, 2, 2), "a footprint off the edge fails")
	assert_eq(g.count(), 1, "only the first placement remains")
	g = null

func test_ignore_key_lets_a_placement_slide_over_its_own_cells() -> void:
	var g = _grid(5, 5)
	g.place(&"a", 1, 1, 2, 2)
	assert_false(g.can_place(2, 1, 2, 2), "without ignoring self, the overlap with its own cells blocks it")
	assert_true(g.can_place(2, 1, 2, 2, &"a"), "ignoring its own key, sliding one cell right is allowed")
	g = null

# --- move (re-place same key) ---

func test_place_same_key_moves_it() -> void:
	var g = _grid(5, 5)
	g.place(&"a", 0, 0, 2, 1)
	assert_true(g.place(&"a", 3, 3, 2, 1), "re-placing the same key moves it (frees the old cells first)")
	assert_eq(g.count(), 1, "still one placement (a move, not a duplicate)")
	assert_true(g.is_free(0, 0), "the old cells are freed")
	assert_false(g.is_free(3, 3), "the new cells are occupied")
	g = null

func test_failed_move_restores_the_old_placement() -> void:
	var g = _grid(5, 5)
	g.place(&"a", 0, 0, 2, 1)
	g.place(&"b", 0, 2, 2, 1)
	assert_false(g.place(&"a", 0, 2, 2, 1), "moving 'a' onto 'b' fails")
	assert_eq(g.placement_of(&"a"), {"x": 0, "y": 0, "w": 2, "h": 1}, "...and 'a' stays at its original spot")
	assert_false(g.is_free(0, 0), "its original cells are still occupied")
	g = null

# --- remove ---

func test_remove_frees_cells() -> void:
	var g = _grid(5, 5)
	g.place(&"a", 1, 1, 2, 2)
	assert_true(g.remove(&"a"), "remove an existing placement")
	assert_true(g.is_free(1, 1), "its cells are freed")
	assert_eq(g.count(), 0, "no placements left")
	assert_false(g.remove(&"a"), "removing a gone key returns false")
	g = null

# --- find_free_slot ---

func test_find_free_slot_scans_row_major() -> void:
	var g = _grid(3, 3)
	var slot = g.find_free_slot(1, 1)
	assert_true(slot["found"], "a 1x1 fits on an empty grid")
	assert_eq(slot["x"], 0, "first free cell is top-left x")
	assert_eq(slot["y"], 0, "...and y")
	assert_false(slot["rotated"], "no rotation needed")
	g = null

func test_find_free_slot_returns_not_found_when_full() -> void:
	var g = _grid(2, 1)
	g.place(&"a", 0, 0, 2, 1)  # fills the whole grid
	assert_false(g.find_free_slot(1, 1)["found"], "nothing fits on a full grid")
	g = null

func test_find_free_slot_rotates_to_fit() -> void:
	# A 1-row, 3-wide grid: a 1-wide×2-tall item can't fit (only 1 row), but rotated to 2-wide×1-tall it does.
	var g = _grid(3, 1)
	var slot = g.find_free_slot(1, 2, true)
	assert_true(slot["found"], "the item fits once rotated")
	assert_true(slot["rotated"], "and it reports the rotation")
	assert_eq(slot["w"], 2, "the chosen footprint is the rotated 2-wide")
	assert_eq(slot["h"], 1, "...by 1-tall")
	# Without rotation it cannot fit at all.
	assert_false(g.find_free_slot(1, 2, false)["found"], "no rotation -> 1x2 can't fit a 1-row grid")
	g = null

# --- Item grid fields ---

func test_item_grid_size_defaults_to_one_by_one() -> void:
	var it = ITEM.new()
	assert_eq(it.grid_width, 1, "items default to a single cell wide")
	assert_eq(it.grid_height, 1, "...and one cell tall (so every existing item occupies one cell)")
	it = null

func test_item_grid_size_clamps_to_at_least_one() -> void:
	var it = ITEM.new()
	it.grid_width = 0
	it.grid_height = -3
	assert_eq(it.grid_width, 1, "a zero width clamps to 1")
	assert_eq(it.grid_height, 1, "a negative height clamps to 1")
	it.grid_width = 4
	assert_eq(it.grid_width, 4, "a valid size is kept")
	it = null
