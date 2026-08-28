extends GutTest

## GUT suite for the ZORKMIDS COIN TILE — the stack a LOOT SOURCE carries its cash as (a corpse / container
## seeded at spawn, a live pickpocket target's `money` float frozen into a tile for the length of a robbery).
## ⭐The PLAYER never holds one: their zorkmids are the `money` float, painted by the HUD + the backpack's
## wallet row and spilled through it as a physics money bag (see Zorkmids.ITEM_ID). Money stays a fractional
## float on Character (pinned by test_money.gd); this covers the two pieces the coin tile rests on:
##
##   * CharacterInventory.set_item_count — the SINGLE-stack "force exact quantity in place" primitive the
##     pickpocket freeze/thaw pushes a wallet float through. Create / update-in-place (placement preserved) /
##     remove-at-zero / no-op-when-equal / duplicate-collapse / footprint refit, with the grid both OFF
##     (an unbounded corpse-copy bag) and ON (a bounded Tetris bag).
##   * The coin<->wallet round-trip math: one coin = one Zorkmids.QUANTUM (0.01 zm), so coins = round(money/QUANTUM)
##     and the tile reprints fmt(coins × QUANTUM) VERBATIM as the wallet — the fraction survives the integer stack.
##
## SCOPE / testability: both angles are pure + off-tree (CharacterInventory is a bare Node built with .new(); its
## _grid is initialized at declaration, so set_item_count needs no _ready). The live freeze/thaw around a
## pickpocket session is covered against the real autoload in tests/test_loot_drop.gd.

const ZORKMIDS_UNIT := 0.01  ## == Zorkmids.QUANTUM; a local copy so a QUANTUM change trips test_money.gd, not this


## A bare MISC item standing in for the coin template (id + 1×1 footprint is all set_item_count reads).
func _coin() -> Item:
	var it := Item.new()
	it.id = Zorkmids.ITEM_ID
	it.display_name = "Zorkmids"
	it.category = Item.Category.MISC
	it.max_stack = 1000000000
	return it

func _misc(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	it.category = Item.Category.MISC
	return it


# ---------------------------------------------------------------------------
# set_item_count — the exact-quantity primitive (grid OFF: an unbounded bag)
# ---------------------------------------------------------------------------

func test_set_item_count_creates_then_removes_a_single_stack() -> void:
	var inv := CharacterInventory.new()
	var coin := _coin()
	assert_true(inv.set_item_count(coin, 1250),
		"seeding a fresh coin pile changes the bag — set_item_count returns true and creates the stack")
	assert_eq(inv.count_of(coin), 1250,
		"the pile holds exactly the count asked for (1250 units = 12.5 zorkmids at one coin per QUANTUM)")
	assert_eq(inv.contents().size(), 1,
		"a set quantity is ONE stack, never spilled across several — even 1250 units stay a single pile")
	assert_true(inv.set_item_count(coin, 0),
		"dropping the amount to 0 removes the pile and reports the change")
	assert_eq(inv.count_of(coin), 0,
		"a zeroed wallet leaves no coin stack in the bag")
	assert_true(inv.is_empty(),
		"removing the only (coin) stack empties the backpack")
	inv.free()


func test_set_item_count_updates_in_place_and_noops_when_equal() -> void:
	var inv := CharacterInventory.new()
	var coin := _coin()
	inv.set_item_count(coin, 100)
	assert_true(inv.set_item_count(coin, 250),
		"raising the amount is a real change (100 -> 250)")
	assert_eq(inv.count_of(coin), 250,
		"the stack count follows the wallet up to 250")
	assert_false(inv.set_item_count(coin, 250),
		"re-asserting the SAME amount is a no-op — returns false so a per-change re-sync never churns `changed`/autosave")
	assert_eq(inv.contents().size(), 1,
		"updates stay in the same single stack — no new pile is appended on every tick")
	inv.free()


func test_set_item_count_leaves_other_items_untouched() -> void:
	var inv := CharacterInventory.new()
	var coin := _coin()
	var lockpick := _misc(&"lockpick")
	inv.add(lockpick, 3)
	inv.set_item_count(coin, 500)
	assert_eq(inv.count_of(lockpick), 3,
		"seeding the coin pile must not disturb ordinary loot already in the bag")
	assert_eq(inv.count_of(coin), 500,
		"the coin pile sits alongside the other items at its own count")
	inv.set_item_count(coin, 0)
	assert_eq(inv.count_of(lockpick), 3,
		"removing the coin pile (wallet emptied) leaves the rest of the bag intact")
	inv.free()


# ---------------------------------------------------------------------------
# set_item_count — a BOUNDED grid (placement must survive an update)
# ---------------------------------------------------------------------------

func test_set_item_count_preserves_grid_key_and_placement_across_updates() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(6, 5)  # a Tetris-sized bag
	var coin := _coin()
	inv.set_item_count(coin, 100)
	var placed := _coin_row(inv, coin)
	assert_false(placed.is_empty(), "the coin pile auto-placed into the bounded grid on creation")
	var key0: int = placed["key"]
	var x0: int = placed["x"]
	var y0: int = placed["y"]
	assert_gte(x0, 0, "a placed pile has a real grid cell (x >= 0), so it renders a tile")
	inv.set_item_count(coin, 999)  # the wallet ticks up
	var placed2 := _coin_row(inv, coin)
	assert_eq(int(placed2["count"]), 999, "the amount updated to the new wallet value")
	assert_eq(int(placed2["key"]), key0,
		"the stack KEY is stable across an update — the live tile is the SAME node, so it doesn't rebuild its mesh/jump")
	assert_eq(int(placed2["x"]), x0, "the pile keeps its column when only the amount changes (no teleport as money ticks)")
	assert_eq(int(placed2["y"]), y0, "the pile keeps its row across an in-place amount update")
	inv.free()


func test_set_item_count_frees_the_grid_cell_when_the_wallet_empties() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 1)  # a tiny 2-cell bag
	var coin := _coin()
	var a := _misc(&"a")
	var b := _misc(&"b")
	inv.set_item_count(coin, 50)  # claims one of the two cells
	assert_true(inv.add(a, 1) > 0, "the second cell is still free for another item")
	inv.set_item_count(coin, 0)   # wallet emptied -> pile removed -> its cell frees
	assert_true(inv.add(b, 1) > 0,
		"emptying the coin pile frees its grid cell, so a new item can take the space it vacated")
	inv.free()


func test_set_item_count_places_a_pile_left_unplaced_once_the_bag_frees() -> void:
	# The bag is FULL the instant money first appears -> the pile is kept but UNPLACED (no tile). The moment a cell
	# frees, CharacterInventory._rehome_unplaced (P0-3a) auto-homes it ON the removal — so the coin can't stay
	# invisible forever, and no further set_item_count nudge is needed.
	var inv := CharacterInventory.new()
	inv.enable_grid(1, 1)  # a single-cell bag
	var coin := _coin()
	var a := _misc(&"a")
	inv.add(a, 1)  # claims the only cell
	inv.set_item_count(coin, 50)  # no free cell -> unplaced (push_warning "kept unplaced (bag full)")
	# That "kept unplaced" push_warning is the expected diagnostic here; consume it so GUT's tracker doesn't fail us.
	for e in get_errors():
		e.handled = true
	var unplaced := _coin_row(inv, coin)
	assert_false(unplaced.is_empty(), "the pile is kept in the bag even when it can't be placed (money is never lost)")
	assert_eq(int(unplaced["x"]), -1, "with the bag full the pile has no cell yet (x = -1 -> no tile renders)")
	inv.remove(a, 1)  # free the cell -> remove() auto-rehomes the unplaced coin immediately (P0-3a)
	var placed := _coin_row(inv, coin)
	assert_gte(int(placed["x"]), 0, "freeing a cell auto-homes the previously-unplaced coin, so its tile becomes visible again")
	assert_eq(int(placed["count"]), 50, "the amount is unchanged by the auto-placement")
	# The pile is already placed at the right footprint now, so re-asserting the same amount is a cheap no-op.
	assert_false(inv.set_item_count(coin, 50),
		"re-asserting the same amount+footprint after the auto-rehome changes nothing (no churn)")
	inv.free()


## The placed_contents() row for `coin` ({item,count,key,x,y,w,h}), or {} if the pile isn't in the bag.
func _coin_row(inv: CharacterInventory, coin: Item) -> Dictionary:
	for row in inv.placed_contents():
		if row["item"] == coin:
			return row
	return {}


# ---------------------------------------------------------------------------
# coin <-> wallet round-trip: the fraction survives the integer stack count
# ---------------------------------------------------------------------------

func test_coin_count_round_trips_fractional_wallets_verbatim() -> void:
	# For each quantized wallet value: coins = round(money / QUANTUM), then the tile prints fmt(coins × QUANTUM).
	# The reprint must equal fmt(money) — i.e. the integer stack loses NOTHING, halves and quarters included.
	for money in [0.0, 0.01, 0.5, 0.75, 3.1, 12.5, 100.0, 1234.56]:
		var coins := int(round(money / Zorkmids.QUANTUM))
		var reprint := Zorkmids.fmt(float(coins) * Zorkmids.QUANTUM)
		assert_eq(reprint, Zorkmids.fmt(money),
			"a %s-zorkmid wallet is %d coins and prints back as itself — one coin per QUANTUM keeps fractions exact" % [Zorkmids.fmt(money), coins])

func test_half_a_zorkmid_is_fifty_coins() -> void:
	assert_eq(int(round(0.5 / Zorkmids.QUANTUM)), 50,
		"half a zorkmid is 50 coin-units (0.5 / 0.01) — the fractional wallet maps onto a whole integer stack count")
	assert_eq(Zorkmids.QUANTUM, ZORKMIDS_UNIT,
		"this suite's coin unit tracks Zorkmids.QUANTUM — if the quantum ever changes, test_money.gd is the deliberate gate")


# ---------------------------------------------------------------------------
# the coin id constant (the single source shared by loot_screen / grid_tile / GameState)
# ---------------------------------------------------------------------------

func test_item_id_constant_is_zorkmids() -> void:
	assert_eq(Zorkmids.ITEM_ID, &"zorkmids",
		"the coin Item's id is the stable key resources/items/zorkmids.tres carries — LootScreen converts a tile to money by it, grid_tile renders by it, and GameState.capture EXCLUDES a stray one from the save by it")


# ---------------------------------------------------------------------------
# grid FOOTPRINT — set_item_count(item, count, w, h) grows/shrinks in place, never evicts, never vanishes.
# (No caller scales a coin pile's footprint today — a loot tile is a fixed 1×1 so it always places on a
# bounded loot grid — but the refit path is the primitive's contract and stays pinned.)
# ---------------------------------------------------------------------------

func test_set_item_count_places_at_the_requested_footprint() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(6, 5)
	var coin := _coin()
	inv.set_item_count(coin, 100, 2, 2)
	var row := _coin_row(inv, coin)
	assert_eq(int(row["w"]), 2, "the pile claims the 2-wide footprint it was asked for")
	assert_eq(int(row["h"]), 2, "…and 2 tall — a 2×2 square")
	inv.free()


func test_footprint_grows_in_place_keeping_its_key() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(6, 5)
	var coin := _coin()
	inv.set_item_count(coin, 50, 1, 1)   # 1×1 at the top-left
	var key: int = int(_coin_row(inv, coin)["key"])
	assert_true(inv.set_item_count(coin, 50, 2, 2),
		"same amount but a bigger footprint IS a change — the grid grew, so it returns true")
	var after := _coin_row(inv, coin)
	assert_eq(int(after["key"]), key, "growing keeps the SAME stack (same key/tile), it isn't torn down and rebuilt")
	assert_eq(int(after["w"]), 2, "the pile grew to 2 wide")
	assert_eq(int(after["h"]), 2, "…and 2 tall")
	inv.free()


func test_footprint_stays_put_when_the_bigger_size_cannot_fit() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 2)  # only 4 cells
	var coin := _coin()
	var blocker := _misc(&"blocker")
	inv.set_item_count(coin, 50, 1, 1)  # top-left cell
	inv.add(blocker, 1)                 # another cell -> no free 2×2 block remains
	assert_false(inv.set_item_count(coin, 50, 2, 2),
		"can't grow to 2×2 (no free 2×2 block) and the amount didn't change -> a no-op, returns false")
	var row := _coin_row(inv, coin)
	assert_eq(int(row["w"]), 1, "the pile stays 1×1 rather than vanish — a resized stack must never lose its tile")
	assert_gte(int(row["x"]), 0, "…and it's still placed (visible), not stranded unplaced")
	inv.free()


func test_footprint_growth_never_evicts_another_item() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(6, 5)
	var coin := _coin()
	var keepme := _misc(&"keepme")
	inv.set_item_count(coin, 50, 1, 1)
	inv.add(keepme, 1)
	inv.set_item_count(coin, 50, 3, 3)  # grow — must route AROUND keepme, never over it
	assert_eq(inv.count_of(keepme), 1,
		"growing the money pile only ever claims FREE cells — it relocates around other items, never evicts them")
	inv.free()
