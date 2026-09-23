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
##   * The wallet -> coin tile SEEDING a loot source does at spawn (ItemContainer._seed_contents for a crate's
##     authored `money`, LootableCorpse.setup for a dead NPC's wallet): one coin per hundredth of a zorkmid, so a
##     fractional wallet lands as an exact integer stack — including the wallets (0.29, 19.99, 1234.56 ...) whose
##     float division lands a hair UNDER the whole coin count, where a truncating conversion would steal a coin.
##
## SCOPE / testability: all off-tree (CharacterInventory is a bare Node built with .new(); its _grid is initialized
## at declaration, so set_item_count needs no _ready; the container is seeded by setting `inventory` and calling
## _seed_contents, the corpse through setup(), neither needing _ready). The live freeze/thaw around a pickpocket
## session is covered against the real autoload in tests/test_loot_drop.gd.

const ZORKMIDS_TRES := "res://resources/items/zorkmids.tres"

## [wallet in zorkmids, the coin count the player's cash must become]. Hand-written hundredths, NOT recomputed: the
## drifting rows are the whole point (0.29 / 0.01 == 28.999999999999996 in floating point, 1234.56 / 0.01 ==
## 123455.99999999999), next to exact ones (0.5, 12.5) and the smallest coin (0.01).
const WALLET_COINS := [
	[0.01, 1],
	[0.29, 29],
	[0.5, 50],
	[4.35, 435],
	[12.5, 1250],
	[19.99, 1999],
	[1234.56, 123456],
]


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
# wallet -> coin tile seeding: every hundredth of the wallet becomes exactly one coin, in ONE tile
# ---------------------------------------------------------------------------

func test_container_cash_seeds_one_coin_per_hundredth_as_a_single_tile() -> void:
	for row in WALLET_COINS:
		var wallet: float = row[0]
		var coins: int = row[1]
		var crate := ItemContainer.new()
		crate.inventory = CharacterInventory.new()  # _ready would build this; set it directly for the off-tree seed
		crate.money = wallet
		crate._seed_contents()
		assert_eq(crate.inventory.count_of_id(Zorkmids.ITEM_ID), coins,
			"a crate stashing %s zm must loot as %d coins — a lost coin here is cash the player can see authored but never collect" % [str(wallet), coins])
		assert_eq(crate.inventory.contents().size(), 1,
			"the %s zm stash must sit in ONE coin tile, not spill across several stacks" % str(wallet))
		var tile: Dictionary = crate.inventory.contents()[0]
		assert_eq((tile["item"] as Item).resource_path, ZORKMIDS_TRES,
			"the tile must be the shipped zorkmids.tres coin (the one Zorkmids.ITEM_ID resolves to), so the loot screen converts it to money")
		crate.inventory.free()
		crate.free()


func test_container_without_cash_seeds_no_coin_tile() -> void:
	for wallet in [0.0, -5.0]:
		var crate := ItemContainer.new()
		crate.inventory = CharacterInventory.new()
		crate.money = wallet
		crate._seed_contents()
		assert_true(crate.inventory.is_empty(),
			"a crate authored with %s zm must open empty — no zero-coin tile cluttering the loot grid" % str(wallet))
		crate.inventory.free()
		crate.free()


func test_corpse_wallet_seeds_one_coin_per_hundredth_as_a_single_tile() -> void:
	for row in WALLET_COINS:
		var wallet: float = row[0]
		var coins: int = row[1]
		var corpse := LootableCorpse.new()
		corpse.setup(null, "Mark", wallet)
		assert_eq(corpse.inventory.count_of_id(Zorkmids.ITEM_ID), coins,
			"a body that died carrying %s zm must loot as %d coins — the player must get back every hundredth the NPC held" % [str(wallet), coins])
		assert_eq(corpse.inventory.contents().size(), 1,
			"the dead NPC's %s zm wallet must be ONE coin tile" % str(wallet))
		assert_true(corpse.can_be_talked_to(),
			"a body holding only cash must still be lootable (the coin tile counts as loot)")
		corpse.free()
	var broke := LootableCorpse.new()
	broke.setup(null, "Broke", 0.0)
	assert_true(broke.inventory.is_empty(),
		"control: a body with an empty wallet gets no coin tile at all")
	assert_false(broke.can_be_talked_to(),
		"...so an empty-handed, penniless body does not advertise itself as lootable")
	broke.free()


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
	# The pile grows from 1×1 to 3×3 while another item sits INSIDE the 3×3 it would claim at its own corner. Growth must
	# route around it: the neighbour keeps its exact tile, and no cell ends up claimed by both. Counting stacks cannot
	# see this — a grid eviction leaves the stack list untouched — so the check reads the placements themselves.
	var inv := CharacterInventory.new()
	inv.enable_grid(6, 5)
	var coin := _coin()
	var keepme := _misc(&"keepme")
	inv.set_item_count(coin, 50, 1, 1)
	inv.add(keepme, 1)
	var before := _coin_row(inv, keepme)
	var before_cell := Vector2i(int(before["x"]), int(before["y"]))
	assert_true(Rect2i(0, 0, 3, 3).has_point(before_cell),
		"harness: the other item must sit inside the 3×3 the pile would grow into in place, or nothing is at stake")
	# CONTROL: the growth really happens (relocated, not refused), so the neighbour checks below grade a real refit.
	assert_true(inv.set_item_count(coin, 50, 3, 3), "the pile's footprint changed, so set_item_count reports a change")
	var grown := _coin_row(inv, coin)
	assert_eq(Vector2i(int(grown["w"]), int(grown["h"])), Vector2i(3, 3), "control: the pile did grow to 3×3")
	assert_gte(int(grown["x"]), 0, "control: ...and it is placed on the grid, not parked unplaced")
	var after := _coin_row(inv, keepme)
	assert_eq(Vector2i(int(after["x"]), int(after["y"])), before_cell,
		"growing the money pile never moves or unplaces another item — it keeps its exact tile")
	assert_true(inv.can_place_stack(int(after["key"]), before_cell.x, before_cell.y, 1, 1),
		"the other item's cell still belongs to it alone — the pile's growth claimed no cell under it")
	var grown_rect := Rect2i(int(grown["x"]), int(grown["y"]), int(grown["w"]), int(grown["h"]))
	assert_false(grown_rect.intersects(Rect2i(before_cell, Vector2i(int(after["w"]), int(after["h"])))),
		"the grown pile and the other item share no cell — growth only ever claims FREE cells, never evicts")
	assert_eq(inv.count_of(keepme), 1, "...and the other item is still in the bag")
	inv.free()
