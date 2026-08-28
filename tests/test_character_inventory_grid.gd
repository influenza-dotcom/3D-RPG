extends GutTest

## CharacterInventory with the SPATIAL GRID turned ON (inventory T2) — the bounded, Tetris-style PLAYER bag.
## The grid is OPT-IN (off by default; the existing test_character_inventory suite covers the unlimited v1 path
## that NPC / corpse / container / merchant-stock bags keep), so here we enable_grid() and assert the cap:
##   - add() stops short when no footprint fits (returns fewer / 0), and topping an existing stack never fails;
##   - remove() frees the footprint so the space is reusable;
##   - placed_contents() reports each stack's {x, y, w, h};
##   - transfer_to() rolls back whatever a full destination can't take (no item loss);
##   - can_accept() gates a single-unit add; restore_stack() reproduces a saved layout (with auto-place fallback).
## Bare .new() off-tree per CLAUDE.md (CharacterInventory defines no _ready; the grid is pure data).

## A fresh MISC item with an explicit footprint + id (distinct ids so two test items don't stack onto each other).
func _item(id: StringName, w: int, h: int, max_stack := 1) -> Item:
	var it := Item.new()
	it.id = id
	it.display_name = String(id)
	it.category = Item.Category.MISC
	it.max_stack = max_stack
	it.grid_width = w
	it.grid_height = h
	return it


func test_grid_off_by_default() -> void:
	var inv := CharacterInventory.new()
	assert_false(inv.grid_enabled(), "a fresh backpack has no spatial cap (the NPC / corpse / test default)")
	# With the grid off, a huge add still always succeeds (v1 unlimited) — proves the opt-in.
	var big := _item(&"big", 9, 9)
	assert_eq(inv.add(big), 1, "grid off -> add is unlimited, footprint ignored")
	inv.free()
	big = null


func test_enable_grid_caps_new_stacks() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 2)  # 4 cells
	var big := _item(&"big", 2, 2)  # fills the whole grid in one stack
	assert_eq(inv.add(big), 1, "the 2x2 item fits the empty 2x2 grid")
	var another := _item(&"small", 1, 1)
	assert_eq(inv.add(another), 0, "with the grid full, a further add fits nothing (returns 0)")
	assert_eq(inv.count_of(another), 0, "...and nothing is stored")
	assert_eq(inv.count_of(big), 1, "the placed item stays")
	inv.free()
	big = null
	another = null


func test_topping_up_a_stack_needs_no_cell() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(1, 1)  # ONE cell
	var ammo := _item(&"ammo", 1, 1, 10)
	assert_eq(inv.add(ammo, 4), 4, "4 rounds land in one stack occupying the single cell")
	assert_eq(inv.add(ammo, 5), 5, "topping the SAME stack to 9 needs no new cell — still fits the one-cell grid")
	assert_eq(inv.count_of(ammo), 9, "all 9 stored in the one cell's stack")
	# Topping to the max (10) fits; the rest would need a SECOND cell — none free, so the overflow is rejected.
	assert_eq(inv.add(ammo, 5), 1, "1 tops the stack to its max of 10; the remaining 4 need a 2nd cell -> rejected")
	assert_eq(inv.count_of(ammo), 10, "stack capped at max_stack with no room to spill")
	inv.free()
	ammo = null


func test_remove_frees_the_footprint() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 2)
	var a := _item(&"a", 2, 2)
	inv.add(a)
	var b := _item(&"b", 2, 2)
	assert_eq(inv.add(b), 0, "no room for a second 2x2 while the first occupies the grid")
	inv.remove(a, 1)
	assert_eq(inv.add(b), 1, "removing the first frees the footprint so the second now fits")
	inv.free()
	a = null
	b = null


func test_placed_contents_reports_placement() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(4, 4)
	var it := _item(&"wide", 2, 1)
	inv.add(it)
	var rows := inv.placed_contents()
	assert_eq(rows.size(), 1, "one stack")
	var r: Dictionary = rows[0]
	assert_eq(r["x"], 0, "placed at the top-left x")
	assert_eq(r["y"], 0, "...and y")
	assert_eq(r["w"], 2, "footprint width recorded")
	assert_eq(r["h"], 1, "footprint height recorded")
	inv.free()
	it = null


func test_transfer_to_full_dest_rolls_back() -> void:
	var src := CharacterInventory.new()       # unbounded source (grid off)
	var dst := CharacterInventory.new()
	dst.enable_grid(1, 1)                      # one cell
	var a := _item(&"a", 1, 1)
	var b := _item(&"b", 1, 1)
	src.add(a, 1)
	src.add(b, 1)
	assert_eq(src.transfer_to(dst, a, 1), 1, "the first item moves into the one free cell")
	var moved := src.transfer_to(dst, b, 1)
	assert_eq(moved, 0, "the dest grid is full -> nothing moves")
	assert_eq(src.count_of(b), 1, "the un-moved item is rolled back into the source (never lost)")
	assert_eq(dst.count_of(b), 0, "...and never reached the dest")
	src.free()
	dst.free()
	a = null
	b = null


## A bounced transfer of the EQUIPPED weapon must NOT disarm the owner: when the destination can't fit it and
## the whole stack rolls back, the equipped_item marker is restored (remove() cleared it + fired the lost signal).
func test_transfer_to_full_dest_keeps_wielded_weapon_equipped() -> void:
	var src := CharacterInventory.new()       # unbounded source (grid off)
	var dst := CharacterInventory.new()
	dst.enable_grid(1, 1)                      # one cell
	# Fill the single dest cell so the weapon transfer can't land and must bounce fully back.
	var filler := _item(&"filler", 1, 1)
	dst.add(filler)
	# Build a real weapon-item and equip it in the source bag.
	var gun := Item.new()
	gun.id = &"gun"
	gun.display_name = "Gun"
	gun.category = Item.Category.WEAPON
	gun.weapon = WeaponData.new()
	gun.grid_width = 1
	gun.grid_height = 1
	src.add(gun)
	assert_true(src.equip_item(gun), "the weapon-item equips")
	assert_eq(src.equipped_item, gun, "...and is the drawn instance")
	# Watch for the disarm signal — it WILL fire transiently during remove(), but the equipped marker must end set.
	var moved := src.transfer_to(dst, gun, 1)
	assert_eq(moved, 0, "the full dest takes nothing — the weapon bounces fully back")
	assert_eq(src.count_of(gun), 1, "the weapon is back in the source bag")
	assert_eq(src.equipped_item, gun, "the wielded weapon stays equipped after a fully-rejected transfer (not disarmed)")
	src.free()
	dst.free()
	filler = null
	gun.weapon = null
	gun = null


func test_can_accept_reflects_room() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(1, 1)
	var a := _item(&"a", 1, 1, 5)
	assert_true(inv.can_accept(a), "an empty one-cell grid can accept a 1x1")
	inv.add(a)
	var b := _item(&"b", 1, 1)
	assert_false(inv.can_accept(b), "a full grid can't accept a distinct new item (needs a new cell)")
	assert_true(inv.can_accept(a), "...but it CAN accept more of the existing stack (tops up, no new cell)")
	inv.free()
	a = null
	b = null


func test_restore_stack_places_at_saved_spot() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(4, 4)
	var it := _item(&"wide", 2, 1)
	var placed := inv.restore_stack(it, 1, 1, 2, 2, 1)  # saved at (1,2), footprint 2x1
	assert_true(placed, "the saved placement is honoured")
	var r: Dictionary = inv.placed_contents()[0]
	assert_eq(r["x"], 1, "restored at the saved x")
	assert_eq(r["y"], 2, "restored at the saved y")
	assert_eq(inv.count_of(it), 1, "the restored stack is in the bag")
	inv.free()
	it = null


func test_restore_stack_auto_places_when_saved_spot_taken() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 1)  # two cells in a row
	var a := _item(&"a", 1, 1)
	inv.restore_stack(a, 1, 0, 0, 1, 1)  # occupies (0,0)
	var b := _item(&"b", 1, 1)
	var placed := inv.restore_stack(b, 1, 0, 0, 1, 1)  # saved spot collides -> auto-place to (1,0)
	assert_true(placed, "a collision at the saved spot falls back to auto-place")
	assert_eq(inv.count_of(b), 1, "the item is still in the bag, just relocated")
	inv.free()
	a = null
	b = null


func _row_for(inv: CharacterInventory, id: StringName) -> Dictionary:
	for row in inv.placed_contents():
		var it: Item = row["item"]
		if it != null and it.id == id:
			return row
	return {}


func test_removing_a_placed_stack_rehomes_an_unplaced_one() -> void:
	# P0-3a: a stack kept in the bag but unplaced (the corpse-wallet-overflow shape — set_item_count keeps a mirrored
	# stack even when the grid is full) must get a footprint the instant cells free, or a coin tile stays unlootable
	# and the corpse never drains.
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 2)                      # 4 cells
	var big := _item(&"big", 2, 2)             # fills the whole grid
	assert_eq(inv.add(big), 1, "the 2x2 fills the grid")
	var coin := _item(&"coin", 1, 1)
	inv.set_item_count(coin, 1)                # kept in the bag, but no cell -> unplaced
	# set_item_count push_warning()s "kept unplaced (bag full)" — the expected diagnostic for the overflow we're
	# deliberately creating so the remove() below can rehome it. Consume it so GUT's tracker doesn't fail the test.
	for e in get_errors():
		e.handled = true
	assert_true(int(_row_for(inv, &"coin")["x"]) < 0, "the coin is unplaced while the grid is full")
	inv.remove(big)                            # frees all 4 cells
	assert_true(int(_row_for(inv, &"coin")["x"]) >= 0, "freeing cells re-homes the previously-unplaced coin")
	inv.remove(coin)
	assert_true(inv.is_empty(), "removing the now-takeable coin empties the bag (so a corpse can drain + fade)")
	inv.free()
	big = null
	coin = null


func test_restore_stack_auto_places_old_save_with_no_placement() -> void:
	# Back-compat: an old save's entry has no (x,y,w,h) — restore_stack(x<0) auto-places it instead of dropping it.
	var inv := CharacterInventory.new()
	inv.enable_grid(3, 3)
	var it := _item(&"old", 1, 1)
	var placed := inv.restore_stack(it, 1)  # no placement args -> auto-place
	assert_true(placed, "a placement-less (old-save) stack auto-places onto the grid")
	var r: Dictionary = inv.placed_contents()[0]
	assert_eq(r["x"], 0, "auto-placed top-left x")
	assert_eq(r["y"], 0, "...and y")
	inv.free()
	it = null


# --- the grid-UI manipulation API: placed_contents key, move_stack, can_place_stack (T3 drag) ---

## The row whose item is `item` (placed_contents is insertion-order; this is just clearer than indexing).
func _row_of(inv: CharacterInventory, item: Item) -> Dictionary:
	for r in inv.placed_contents():
		if r["item"] == item:
			return r
	return {}

func test_placed_contents_includes_a_unique_stack_key() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(4, 4)
	var a := _item(&"a", 1, 1)
	var b := _item(&"b", 1, 1)
	inv.add(a)
	inv.add(b)
	var rows := inv.placed_contents()
	assert_eq(rows.size(), 2, "two stacks")
	assert_true(rows[0].has("key") and rows[1].has("key"), "each row carries its grid key (the UI drags by it)")
	assert_true(rows[0]["key"] != rows[1]["key"], "stack keys are distinct")
	inv.free()
	a = null
	b = null

func test_move_stack_relocates_a_placed_tile() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(4, 4)
	var it := _item(&"a", 1, 1)
	inv.add(it)  # lands at (0,0)
	var key := int(inv.placed_contents()[0]["key"])
	assert_true(inv.move_stack(key, 2, 3, 1, 1), "moving to a free cell succeeds")
	var r := _row_of(inv, it)
	assert_eq(r["x"], 2, "the tile moved to x=2")
	assert_eq(r["y"], 3, "...and y=3")
	inv.free()
	it = null

func test_move_stack_rejects_an_occupied_target_and_stays_put() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 1)  # two cells
	var a := _item(&"a", 1, 1)
	var b := _item(&"b", 1, 1)
	inv.add(a)  # (0,0)
	inv.add(b)  # (1,0)
	var key_a := int(_row_of(inv, a)["key"])
	assert_false(inv.move_stack(key_a, 1, 0, 1, 1), "moving 'a' onto 'b' cell fails")
	assert_eq(_row_of(inv, a)["x"], 0, "...and 'a' stays at its original spot (rollback)")
	inv.free()
	a = null
	b = null

func test_move_stack_can_rotate_via_a_swapped_footprint() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(3, 3)
	var it := _item(&"wide", 2, 1)  # placed 2x1 at (0,0)
	inv.add(it)
	var key := int(inv.placed_contents()[0]["key"])
	assert_true(inv.move_stack(key, 0, 0, 1, 2), "re-placing with swapped footprint (1x2) at (0,0) succeeds — a rotate")
	var r := _row_of(inv, it)
	assert_eq(r["w"], 1, "the footprint is now 1 wide")
	assert_eq(r["h"], 2, "...and 2 tall (rotated)")
	inv.free()
	it = null

func test_can_place_stack_ignores_the_stacks_own_cells() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(4, 4)
	var it := _item(&"wide", 2, 1)
	inv.add(it)  # occupies (0,0)-(1,0)
	var key := int(inv.placed_contents()[0]["key"])
	assert_true(inv.can_place_stack(key, 1, 0, 2, 1), "sliding right one cell overlaps its OWN cells -> allowed (ignore_key)")
	inv.free()
	it = null

func test_can_place_stack_blocks_another_stacks_cells() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(2, 1)
	var a := _item(&"a", 1, 1)
	var b := _item(&"b", 1, 1)
	inv.add(a)
	inv.add(b)
	var key_a := int(_row_of(inv, a)["key"])
	assert_false(inv.can_place_stack(key_a, 1, 0, 1, 1), "'b' occupies (1,0) -> 'a' can't be placed there")
	inv.free()
	a = null
	b = null

func test_move_stack_unknown_key_is_false() -> void:
	var inv := CharacterInventory.new()
	inv.enable_grid(3, 3)
	assert_false(inv.move_stack(999, 0, 0, 1, 1), "an unknown grid key moves nothing")
	inv.free()

func test_move_stack_is_a_noop_with_grid_off() -> void:
	var inv := CharacterInventory.new()  # grid disabled (the NPC / corpse default)
	var it := _item(&"a", 1, 1)
	inv.add(it)
	assert_false(inv.move_stack(0, 0, 0, 1, 1), "no spatial cap -> move_stack is a no-op")
	inv.free()
	it = null


# --- transfer_to coalesces its own `changed` so a write-back listener can't grab a freed cell (F-C12) ---

## A stand-in for any listener that WRITES BACK on `changed` (the pickpocket wallet freeze is the shipped one):
## wired to the SOURCE bag's `changed`, it re-asserts a coin tile into a
## free cell the instant the bag looks emptied of `a`. If transfer_to did NOT coalesce its own emit, the remove()
## step's `changed` would fire this MID-transfer and the coin would eat the freed cell before the bounced remainder
## is rolled back — the exact interleave the deferral prevents. A bound method on an inner class, not a lambda, per
## the "connect a Callable, not a lambda" project rule.
class _CoinRefitter extends RefCounted:
	var inv: CharacterInventory
	var coin: Item
	var a: Item
	func on_changed() -> void:
		if inv != null and inv.count_of(a) == 0 and inv.count_of(coin) == 0:
			inv.set_item_count(coin, 1, 1, 1)  # grab a freed cell for the coin pile — models a self-healing view

func test_transfer_to_rollback_survives_listener_refit() -> void:
	# A partial-bounce deposit: src holds two 1×1 `a` (both cells), dst has room for only one. transfer_to removes
	# both, dst keeps one, the other bounces back. A write-back listener on src.changed tries to claim a freed cell the
	# instant `a` is gone. WITHOUT the deferral it fires mid-remove and mints a coin into that cell; WITH it, src
	# emits `changed` exactly once at the end (a already restored), so the listener's guard sees count_of(a)==1 and
	# never mints. (The spec's moved==0 shape is unreachable: transfer_to's can_accept guard early-returns a full
	# bounce before any removal, so a partial bounce is what actually exercises the remove+rollback path.)
	var src := CharacterInventory.new()
	src.enable_grid(1, 2)                      # two stacked cells
	var dst := CharacterInventory.new()
	dst.enable_grid(1, 1)                      # room for exactly one
	var a := _item(&"a", 1, 1)
	src.add(a, 2)                              # both cells full
	assert_eq(src.count_of(a), 2, "precondition: the source holds both units")
	var coin := _item(&"coin", 1, 1)
	var refit := _CoinRefitter.new()
	refit.inv = src
	refit.coin = coin
	refit.a = a
	src.changed.connect(refit.on_changed)     # bound Callable, not a lambda
	var moved := src.transfer_to(dst, a, 2)
	assert_eq(moved, 1, "the destination's single cell fits one unit; the other bounces back")
	assert_eq(src.count_of(a), 1, "the bounced unit is restored to the source, not eaten by the mid-transfer refit")
	assert_eq(src.count_of(coin), 0,
		"the mirror listener never fired mid-transfer (changed is coalesced), so it minted no coin into the freed cell")
	src.changed.disconnect(refit.on_changed)
	src.free()
	dst.free()
	refit = null
	a = null
	coin = null
