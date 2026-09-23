extends GutTest
## CROSS-GRID DRAG + the merchant grid — the inventory/view primitives the two features are built on, plus the
## economy guard that gridding a merchant's shelf makes reachable.
##
## Scope note (CLAUDE.md): the DRAG ITSELF is mouse-driven and in-tree, so it stays playtest-gated exactly like
## the overflow strip's click routing. What IS unit-testable is every piece the drop depends on — the new
## CharacterInventory API (can_place_new / stack_keys / repack), the view's landing-cell helpers
## (can_accept_footprint / place_transferred) and its cross-grid release, built OFF-TREE with no add_child so
## _ready never runs, and
## Merchant.sell's pay-only-if-it-moved ordering. Those are what a regression would actually break.


## A 1x1-footprint item; distinct instances make distinct stacks (add() stacks by item identity).
func _item(id: StringName, w: int = 1, h: int = 1) -> Item:
	var it := Item.new()
	it.id = id
	it.display_name = String(id)
	it.grid_width = w
	it.grid_height = h
	return it


# --- CharacterInventory: the new primitives ------------------------------------------------------------------

func test_can_place_new_reports_free_cells_for_a_stack_this_bag_does_not_own() -> void:
	# The cross-grid preview's test: can an INCOMING footprint land here? can_place_stack can't answer it (it
	# demands a key this bag already holds), which is exactly why can_place_new exists.
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 2)
	inv.add(_item(&"a"), 1)  # lands at (0,0)
	assert_false(inv.can_place_new(0, 0, 1, 1), "an occupied cell refuses an incoming footprint")
	assert_true(inv.can_place_new(1, 0, 1, 1), "a free cell accepts one")
	assert_false(inv.can_place_new(2, 0, 1, 1), "off-grid refuses")
	assert_false(inv.can_place_new(0, 0, 3, 3), "a footprint bigger than the grid refuses")
	inv.free()

func test_can_place_new_is_false_with_the_grid_off() -> void:
	# Deliberate: placement is meaningless in an unbounded bag, so the CALLER (can_accept_footprint) treats
	# grid-off as "always accepts" before ever reaching here. Pinned so nobody 'fixes' it to true and makes a
	# grid-off bag claim a specific cell.
	var inv := CharacterInventory.new()
	inv.add(_item(&"a"), 1)
	assert_false(inv.can_place_new(0, 0, 1, 1), "an unbounded bag has no cells to reserve")
	inv.free()

func test_stack_keys_snapshots_the_bag_for_new_arrival_detection() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(4, 4)
	var a := _item(&"a")
	inv.add(a, 1)
	var before := inv.stack_keys()
	assert_eq(before.size(), 1, "one stack, one key")
	inv.add(_item(&"b"), 1)  # a DIFFERENT item instance -> a genuinely new stack
	var after := inv.stack_keys()
	assert_eq(after.size(), 2, "the arrival adds a key")
	var fresh: Array = []
	for k in after:
		if not before.has(k):
			fresh.append(k)
	assert_eq(fresh.size(), 1, "set-difference identifies exactly the newly-arrived stack (what place_transferred keys off)")
	inv.free()

func test_repack_reorders_the_grid_into_the_given_key_order() -> void:
	# The Sort button on a GRID has to physically move tiles — display-only reordering is invisible when the
	# order IS the layout. repack re-places top-left-first in the order it is handed.
	var inv := CharacterInventory.new()
	inv.enable_grid(3, 1)
	var a := _item(&"a")
	var b := _item(&"b")
	var c := _item(&"c")
	inv.add(a, 1)
	inv.add(b, 1)
	inv.add(c, 1)
	var key_of := {}
	for row in inv.placed_contents():
		key_of[(row["item"] as Item).id] = int(row["key"])
	inv.repack([key_of[&"c"], key_of[&"b"], key_of[&"a"]])
	var x_of := {}
	for row in inv.placed_contents():
		x_of[(row["item"] as Item).id] = int(row["x"])
	assert_eq(int(x_of[&"c"]), 0, "the first key in the order takes the top-left cell")
	assert_eq(int(x_of[&"b"]), 1, "the second follows it")
	assert_eq(int(x_of[&"a"]), 2, "and the third")
	inv.free()

func test_repack_places_stacks_the_caller_omitted() -> void:
	# A partial order must not strand the rest UNPLACED — anything not listed is re-placed after, in bag order.
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 1)
	var a := _item(&"a")
	var b := _item(&"b")
	inv.add(a, 1)
	inv.add(b, 1)
	var b_key := -1
	for row in inv.placed_contents():
		if (row["item"] as Item).id == &"b":
			b_key = int(row["key"])
	inv.repack([b_key])  # only one key given
	var placed := 0
	for row in inv.placed_contents():
		if int(row["x"]) >= 0:
			placed += 1
	assert_eq(placed, 2, "the omitted stack is still placed, not left in the overflow strip")
	inv.free()

func test_repack_is_a_noop_with_the_grid_off() -> void:
	# An unbounded bag has no layout to tidy, so a Sort on it must change nothing AND must not announce a change:
	# `changed` is what every bag listener (the grid/list views, PassiveItemBuffs) rebuilds on. The emit is the one
	# thing that can tell a real no-op apart from a repack that ran anyway (repack never touches the stacks, and an
	# unconfigured grid has no cell to put anything in), so the control is the same repack on a GRIDDED bag.
	var gridded := CharacterInventory.new()
	gridded.enable_grid(2, 1)
	gridded.add(_item(&"a"), 1)
	watch_signals(gridded)
	gridded.repack([int(gridded.placed_contents()[0]["key"])])
	assert_signal_emit_count(gridded, "changed", 1,
		"control: a repack on a GRIDDED bag re-lays it out and tells its listeners exactly once")
	var inv := CharacterInventory.new()
	inv.add(_item(&"a"), 1)
	watch_signals(inv)
	inv.repack([0, 1, 2])  # must not error on an unbounded bag either
	assert_signal_not_emitted(inv, "changed",
		"a repack on an unbounded bag is a no-op, so it must not tell every listener the bag changed")
	assert_eq(inv.contents().size(), 1, "...and the bag still holds its one stack")
	assert_eq(int(inv.placed_contents()[0]["x"]), -1, "...still unplaced: an unbounded bag has no cells")
	gridded.free()
	inv.free()


# --- GridInventoryView: the landing-cell helpers (OFF-TREE, no _ready) ----------------------------------------

func test_can_accept_footprint_free_cell_full_grid_and_stackable_topup() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(1, 1)
	var a := _item(&"a")
	a.max_stack = 10
	inv.add(a, 1)  # the ONLY cell is now occupied by `a`
	var view := GridInventoryView.new()  # NO add_child -> _ready never runs, _overlay stays null (all guarded)
	view.bind(inv)
	assert_false(view.can_accept_footprint(0, 0, 1, 1, _item(&"other")),
		"a full grid refuses a DIFFERENT item (it needs a cell of its own)")
	assert_true(view.can_accept_footprint(0, 0, 1, 1, a),
		"…but accepts one that merely TOPS UP the existing stack — no new cell needed, so the preview must not read as blocked")
	view.free()
	inv.free()

func test_can_accept_footprint_always_true_for_an_unbounded_bag() -> void:
	var inv := CharacterInventory.new()  # grid OFF
	var view := GridInventoryView.new()
	view.bind(inv)
	assert_true(view.can_accept_footprint(0, 0, 2, 2, _item(&"a")),
		"an unbounded bag accepts anything — placement is meaningless there")
	view.free()
	inv.free()

func test_place_transferred_moves_only_the_new_stack_to_the_aimed_cell() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(3, 3)
	var a := _item(&"a")
	inv.add(a, 1)                  # the incumbent, auto-placed at (0,0)
	var before := inv.stack_keys()
	inv.add(_item(&"b"), 1)        # the "arrival", auto-placed at (1,0)
	var view := GridInventoryView.new()
	view.bind(inv)
	view.place_transferred(before, Vector2i(2, 2), 1, 1)
	var pos := {}
	for row in inv.placed_contents():
		pos[(row["item"] as Item).id] = Vector2i(int(row["x"]), int(row["y"]))
	assert_eq(pos[&"b"], Vector2i(2, 2), "the arrival lands on the cell the player aimed at")
	assert_eq(pos[&"a"], Vector2i(0, 0), "the stack that was already there is untouched")
	view.free()
	inv.free()

func test_place_transferred_is_a_noop_when_nothing_arrived() -> void:
	# A REFUSED transfer (equipped lock / unaffordable / caught pickpocketing) leaves no new stack, so the aimed cell
	# must not be handed to a stack that was already in the bag. The aimed cell is FREE, so a stack wrongly picked
	# as the arrival really would move there. test_place_transferred_moves_only_the_new_stack_to_the_aimed_cell is
	# the control: the same call does move a stack that arrived.
	# (The un-aimed drop, cell.x < 0, is not pinned: move_stack refuses an off-grid cell and InventoryGrid.place puts
	# the old slot back, so the early return and its absence read back identically.)
	var inv := CharacterInventory.new()
	inv.enable_grid(3, 3)
	inv.add(_item(&"a"), 1)
	var snapshot := inv.stack_keys()
	var view := GridInventoryView.new()
	view.bind(inv)
	view.place_transferred(snapshot, Vector2i(2, 2), 1, 1)  # nothing new arrived
	var row0: Dictionary = inv.placed_contents()[0]
	assert_eq(Vector2i(int(row0["x"]), int(row0["y"])), Vector2i(0, 0), "a refused transfer never moves the incumbent")
	view.free()
	inv.free()


# --- the transfer_partner contract: a cross-grid drop only REQUESTS the move ----------------------------------

func test_cross_grid_drop_requests_the_transfer_and_moves_nothing_itself() -> void:
	# The load-bearing invariant: the VIEW must never move items between two bags itself. Every gameplay gate
	# (equipped padlock, pickpocket steal-gate + caught roll, zorkmids->add_money, carry capacity, buy/sell
	# price + till) lives in the HOST's take/deposit/buy/sell, so a drop over the partner column only EMITS
	# transfer_requested with what was dragged and where it was aimed. The mouse drag that ARMS this state is
	# in-tree (it hit-tests the partner's global rect), so the drag state _update_partner_target leaves behind is set
	# by hand and the REAL _release runs off-tree.
	var src_inv := CharacterInventory.new()
	src_inv.enable_grid(2, 2)
	var dst_inv := CharacterInventory.new()
	dst_inv.enable_grid(2, 2)
	var goods := _item(&"goods", 2, 1)  # a 2x1 tile...
	src_inv.add(goods, 1)
	var key := int(src_inv.placed_contents()[0]["key"])
	var src_view := GridInventoryView.new()
	var dst_view := GridInventoryView.new()
	src_view.bind(src_inv)
	dst_view.bind(dst_inv)
	src_view.transfer_partner = dst_view
	dst_view.transfer_partner = src_view
	var requests: Array = []
	src_view.transfer_requested.connect(func(item: Item, k: int, cell: Vector2i, w: int, h: int) -> void:
		requests.append([item, k, cell, Vector2i(w, h)]))
	# ...dragged ROTATED (held 1x2) until the cursor sits over the partner's cell (1, 0).
	src_view._pressed_key = key
	src_view._dragging = true
	src_view._drag_key = key
	src_view._drag_w = 1
	src_view._drag_h = 2
	src_view._partner_active = true
	src_view._partner_target = Vector2i(1, 0)
	src_view._release(Vector2.ZERO)
	assert_eq(requests.size(), 1, "releasing a drag over the partner column asks the host for exactly one transfer")
	if requests.size() == 1:
		assert_eq(requests[0][0], goods, "the request names the dragged item")
		assert_eq(requests[0][1], key,
			"...and the exact dragged STACK key, so the host moves the tile the player grabbed, not another stack of that item")
		assert_eq(requests[0][2], Vector2i(1, 0),
			"...and the PARTNER cell the player aimed at, which the host hands back to place_transferred")
		assert_eq(requests[0][3], Vector2i(1, 2),
			"...and the footprint as HELD (rotated mid-drag), so the tile lands in the orientation the preview showed")
	assert_eq(src_inv.count_of(goods), 1,
		"the view moved nothing out of the source bag: only the host's transfer rules may move items between bags")
	assert_eq(dst_inv.count_of(goods), 0, "...and nothing arrived in the partner bag either")
	assert_false(src_view._dragging, "the drag is over once released, so a later mouse motion can't send it twice")
	src_view.free()
	dst_view.free()
	src_inv.free()
	dst_inv.free()


# --- Merchant: the guard that gridding the shelf makes reachable ----------------------------------------------

func test_sell_pays_nothing_when_the_bounded_shelf_cannot_take_the_item() -> void:
	# Gridding merchant stock (ShopScreen does it on open) means the shelf can FILL UP. sell() used to pay first
	# and transfer after, so a full shelf paid the player AND left them the item — a repeatable money dupe.
	var merchant := Merchant.new()
	merchant.stock = CharacterInventory.new()
	merchant.money = 1000.0
	var goods := _item(&"shelf_filler")
	merchant.stock.add(goods, 1)
	merchant.stock.enable_grid(1, 1)  # exactly one cell, already taken -> the shelf is full
	var player := Player.new()        # off-tree: never _ready()'d (CLAUDE.md forbids running Player._ready in a unit test)
	player.inventory = CharacterInventory.new()
	var wares := _item(&"wares")
	wares.value = 10.0
	player.inventory.add(wares, 1)
	var money_before := player.money
	var sold := merchant.sell(wares, player)
	assert_false(sold, "a full shelf refuses the sale")
	assert_eq(player.money, money_before, "and the player is NOT paid for an item that never moved (the dupe guard)")
	assert_eq(merchant.money, 1000.0, "the till is untouched too")
	assert_eq(player.inventory.count_of(wares), 1, "the item stays in the player's bag")
	player.inventory.free()
	player.free()
	merchant.stock.free()
	merchant.free()
