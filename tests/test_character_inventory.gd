extends GutTest

## CharacterInventory — the per-character backpack (Phase B of the inventory feature). GUT unit suite.
##
## COVERS:
##   - Empty defaults: is_empty/has false, count_of 0, contents() empty.
##   - add(): increments, returns the amount added, emits `changed`; fills existing non-full stacks
##     before spilling overflow into new stacks (max_stack respected); an unstackable (max_stack 1)
##     weapon makes one stack per unit.
##   - remove(): decrements newest-first, clamps to what's held, erases emptied stacks, emits `changed`
##     only when something was actually removed.
##   - has()/count_of() across multiple stacks.
##   - contents() is a defensive copy (mutating it can't corrupt the real inventory).
##   - transfer_to(): moves up to N, clamps to availability, removes from source + adds to dest.
##   - equip_item(): a weapon-item emits equip_weapon_requested(weapon) and does NOT consume the stack;
##     a non-weapon item returns false and emits nothing.
##
## Conventions match test_combat_data.gd: CharacterInventory extends Node but defines no _ready/_init,
## so instances are made with .new() and torn down with .free() WITHOUT add_child (nothing fires against
## a bare tree). Item is a Resource (RefCounted) -> made with .new(), released with `= null`.

const PISTOL := preload("res://resources/weapons/pistol.tres")
const PISTOL_ITEM := preload("res://resources/items/pistol_item.tres")


# A fresh stackable (non-weapon) item for the stacking/transfer cases.
func _stackable(max_stack: int) -> Item:
	var it := Item.new()
	it.id = &"ammo"
	it.display_name = "Ammo"
	it.category = Item.Category.AMMO
	it.max_stack = max_stack
	return it


func test_authored_item_weight_loads() -> void:
	assert_almost_eq(PISTOL_ITEM.weight, 1.5, 0.0001,
		"a weapon item's authored weight loads from its .tres")
	assert_almost_eq(Item.new().weight, 1.0, 0.0001,
		"a fresh Item defaults to weight 1.0")


func test_total_weight_sums_item_weight_times_count() -> void:
	var inv := CharacterInventory.new()
	assert_eq(inv.total_weight(), 0.0,
		"an empty backpack weighs nothing")
	var heavy := _stackable(1)
	heavy.weight = 2.5
	var light := _stackable(99)
	light.weight = 0.5
	inv.add(heavy, 1)
	inv.add(light, 4)
	assert_almost_eq(inv.total_weight(), 4.5, 0.0001,
		"total_weight sums item.weight x count across all stacks (2.5 + 0.5x4)")
	inv.free()
	heavy = null
	light = null


func test_total_weight_drops_after_remove() -> void:
	var inv := CharacterInventory.new()
	var it := _stackable(99)
	it.weight = 0.5
	inv.add(it, 6)
	assert_almost_eq(inv.total_weight(), 3.0, 0.0001, "6 x 0.5 = 3.0 carried")
	inv.remove(it, 4)
	assert_almost_eq(inv.total_weight(), 1.0, 0.0001, "removing 4 leaves 2 x 0.5 = 1.0")
	inv.free()
	it = null


func test_transfer_moves_weight_between_inventories() -> void:
	var src := CharacterInventory.new()
	var dst := CharacterInventory.new()
	var it := _stackable(99)
	it.weight = 0.5
	src.add(it, 4)  # 2.0
	src.transfer_to(dst, it, 3)
	assert_almost_eq(src.total_weight(), 0.5, 0.0001, "source keeps 1 x 0.5 after moving 3 out")
	assert_almost_eq(dst.total_weight(), 1.5, 0.0001, "dest gains 3 x 0.5 = 1.5")
	src.free()
	dst.free()
	it = null


# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

func test_empty_inventory_defaults() -> void:
	var inv := CharacterInventory.new()
	assert_true(inv.is_empty(),
		"A fresh CharacterInventory holds nothing")
	assert_false(inv.has(PISTOL_ITEM),
		"has() is false for any item before anything is added")
	assert_eq(inv.count_of(PISTOL_ITEM), 0,
		"count_of() is 0 for an absent item")
	assert_eq(inv.contents().size(), 0,
		"contents() of an empty backpack is an empty list")
	inv.free()


# ---------------------------------------------------------------------------
# add()
# ---------------------------------------------------------------------------

func test_add_increments_and_emits_changed() -> void:
	var inv := CharacterInventory.new()
	watch_signals(inv)
	var added := inv.add(PISTOL_ITEM, 1)
	assert_eq(added, 1,
		"add() returns how many were actually added")
	assert_true(inv.has(PISTOL_ITEM),
		"After add(), has() reports the item present")
	assert_eq(inv.count_of(PISTOL_ITEM), 1,
		"count_of() reflects the added quantity")
	assert_signal_emitted(inv, "changed",
		"add() must emit `changed` so the UI refreshes")
	inv.free()


func test_add_zero_or_null_is_noop() -> void:
	var inv := CharacterInventory.new()
	watch_signals(inv)
	assert_eq(inv.add(PISTOL_ITEM, 0), 0,
		"add() of 0 adds nothing")
	assert_eq(inv.add(null, 5), 0,
		"add() of a null item adds nothing")
	assert_true(inv.is_empty(),
		"A no-op add() leaves the backpack empty")
	assert_signal_not_emitted(inv, "changed",
		"A no-op add() must NOT emit `changed`")
	inv.free()


func test_add_respects_max_stack_overflow() -> void:
	var inv := CharacterInventory.new()
	var ammo := _stackable(5)
	inv.add(ammo, 7)
	assert_eq(inv.count_of(ammo), 7,
		"All 7 are stored even when they overflow one stack")
	assert_eq(inv.contents().size(), 2,
		"7 of a max_stack-5 item splits into 2 stacks (5 + 2)")
	# A further add tops up the partial stack before making a new one.
	inv.add(ammo, 1)
	assert_eq(inv.count_of(ammo), 8,
		"The extra unit is stored")
	assert_eq(inv.contents().size(), 2,
		"It tops up the partial (2 -> 3) stack rather than opening a third")
	inv.free()
	ammo = null


func test_add_unstackable_makes_separate_stacks() -> void:
	var inv := CharacterInventory.new()
	inv.add(PISTOL_ITEM, 2)
	assert_eq(inv.count_of(PISTOL_ITEM), 2,
		"Two pistols are both held")
	assert_eq(inv.contents().size(), 2,
		"An unstackable (max_stack 1) weapon occupies one stack per unit")
	inv.free()


# ---------------------------------------------------------------------------
# remove()
# ---------------------------------------------------------------------------

func test_remove_decrements_and_clamps() -> void:
	var inv := CharacterInventory.new()
	var ammo := _stackable(10)
	inv.add(ammo, 3)
	var removed := inv.remove(ammo, 2)
	assert_eq(removed, 2,
		"remove() returns how many were actually removed")
	assert_eq(inv.count_of(ammo), 1,
		"The remaining count is correct after a partial remove")
	# Asking for more than is held removes only what's there.
	removed = inv.remove(ammo, 5)
	assert_eq(removed, 1,
		"remove() clamps to what's available (only 1 left)")
	assert_false(inv.has(ammo),
		"Removing the last unit empties the item out")
	assert_true(inv.is_empty(),
		"Emptied stacks are erased, leaving an empty backpack")
	inv.free()
	ammo = null


func test_remove_emits_changed_only_when_something_removed() -> void:
	var inv := CharacterInventory.new()
	inv.add(PISTOL_ITEM, 1)
	watch_signals(inv)
	inv.remove(PISTOL_ITEM, 1)
	assert_signal_emitted(inv, "changed",
		"A real remove emits `changed`")
	# Now empty — a second remove changes nothing and must stay silent.
	inv.remove(PISTOL_ITEM, 1)
	assert_signal_emit_count(inv, "changed", 1,
		"Removing an absent item must NOT emit `changed` again")
	inv.free()


# ---------------------------------------------------------------------------
# has() / count_of() / contents()
# ---------------------------------------------------------------------------

func test_count_of_sums_across_stacks() -> void:
	var inv := CharacterInventory.new()
	var ammo := _stackable(5)
	inv.add(ammo, 12)
	assert_eq(inv.contents().size(), 3,
		"12 of a max_stack-5 item is 3 stacks (5 + 5 + 2)")
	assert_eq(inv.count_of(ammo), 12,
		"count_of() sums every stack of the item")
	inv.free()
	ammo = null


func test_contents_is_defensive_copy() -> void:
	var inv := CharacterInventory.new()
	inv.add(PISTOL_ITEM, 1)
	var snapshot := inv.contents()
	snapshot[0]["count"] = 999
	snapshot.clear()
	assert_eq(inv.count_of(PISTOL_ITEM), 1,
		"Mutating the contents() snapshot must not corrupt the real inventory")
	inv.free()


# ---------------------------------------------------------------------------
# transfer_to()
# ---------------------------------------------------------------------------

func test_transfer_moves_and_clamps() -> void:
	var src := CharacterInventory.new()
	var dst := CharacterInventory.new()
	var ammo := _stackable(10)
	src.add(ammo, 3)
	var moved := src.transfer_to(dst, ammo, 2)
	assert_eq(moved, 2,
		"transfer_to() returns how many moved")
	assert_eq(src.count_of(ammo), 1,
		"The moved units leave the source")
	assert_eq(dst.count_of(ammo), 2,
		"The moved units arrive in the destination")
	# Asking for more than remains moves only the remainder.
	moved = src.transfer_to(dst, ammo, 5)
	assert_eq(moved, 1,
		"transfer_to() clamps to what the source still holds")
	assert_true(src.is_empty(),
		"The source is emptied after moving its last unit")
	assert_eq(dst.count_of(ammo), 3,
		"The destination accumulated all transferred units")
	# Transferring from an empty source is a no-op.
	assert_eq(src.transfer_to(dst, ammo, 1), 0,
		"Transferring an item the source no longer has moves nothing")
	src.free()
	dst.free()
	ammo = null


# ---------------------------------------------------------------------------
# equip_item()
# ---------------------------------------------------------------------------

func test_equip_weapon_item_emits_and_keeps_stack() -> void:
	var inv := CharacterInventory.new()
	inv.add(PISTOL_ITEM, 1)
	# Capture the emitted payload directly — GUT's assert_signal_emitted_with_parameters takes an
	# `index` (int) as its last arg, not a message, so a lambda keeps a descriptive assertion.
	var captured: Array = []
	inv.equip_weapon_requested.connect(func(w: WeaponData) -> void: captured.append(w))
	var ok := inv.equip_item(PISTOL_ITEM)
	assert_true(ok,
		"equip_item() returns true for an equippable weapon-item")
	assert_eq(captured.size(), 1,
		"equip_item() must emit equip_weapon_requested exactly once so the owner draws the weapon")
	assert_eq(captured[0], PISTOL,
		"equip_weapon_requested must carry the item's WeaponData (PISTOL) — the owner draws that exact gun")
	assert_eq(inv.count_of(PISTOL_ITEM), 1,
		"Equipping must NOT consume the stack — the equipped weapon stays in the backpack")
	inv.free()


func test_ammo_count_and_take_ammo() -> void:
	var inv := CharacterInventory.new()
	var nine := ItemDb.ammo_item_for(&"pistol")  # ammo uses the shared template (stacks by type)
	inv.add(nine, 30)
	assert_eq(inv.ammo_count(&"pistol"), 30,
		"ammo_count sums the reserve clips of a caliber")
	assert_eq(inv.ammo_count(&"shells"), 0,
		"a caliber with no reserve reports 0")
	var taken := inv.take_ammo(&"pistol", 12)
	assert_eq(taken, 12,
		"take_ammo returns how many clips it pulled")
	assert_eq(inv.ammo_count(&"pistol"), 18,
		"the pulled clips leave the reserve")
	taken = inv.take_ammo(&"pistol", 100)
	assert_eq(taken, 18,
		"take_ammo clamps to the reserve on hand")
	assert_eq(inv.ammo_count(&"pistol"), 0,
		"the reserve empties out")
	inv.free()


func test_equip_item_tracks_equipped_instance() -> void:
	# Two DISTINCT weapon items (the unique-weapon model) — equipping one marks ONLY that one, so the UI
	# can't show "(equipped)" on both copies of an identical weapon.
	var inv := CharacterInventory.new()
	var w1 := ItemDb.make_weapon_item(PISTOL)
	var w2 := ItemDb.make_weapon_item(PISTOL)
	inv.add(w1)
	inv.add(w2)
	assert_true(inv.equipped_item == null,
		"nothing is equipped until equip_item runs")
	inv.equip_item(w1)
	assert_eq(inv.equipped_item, w1,
		"equip_item records the exact instance drawn")
	assert_true(inv.equipped_item != w2,
		"the OTHER identical weapon is not marked equipped (fixes the double-EQUIPPED bug)")
	inv.equip_item(w2)
	assert_eq(inv.equipped_item, w2,
		"equipping the other instance moves the marker to it")
	inv.free()
	w1 = null
	w2 = null


func test_removing_equipped_item_clears_marker() -> void:
	var inv := CharacterInventory.new()
	var w := ItemDb.make_weapon_item(PISTOL)
	inv.add(w)
	inv.equip_item(w)
	assert_eq(inv.equipped_item, w, "precondition: it's the equipped instance")
	var lost := [0]
	inv.equipped_item_lost.connect(func() -> void: lost[0] += 1)
	inv.remove(w, 1)
	assert_true(inv.equipped_item == null,
		"removing the drawn weapon from the bag clears the equipped marker")
	assert_eq(lost[0], 1,
		"removing the drawn weapon (dropped / looted away) fires equipped_item_lost so the player falls back to fists")
	inv.free()
	w = null


func test_unequip_clears_marker_keeps_item_and_signals() -> void:
	# Unequip puts the weapon AWAY without removing it from the bag: the marker clears + equipped_item_lost
	# fires (player -> fists), but the item is still carried so it can be re-equipped later.
	var inv := CharacterInventory.new()
	var w := ItemDb.make_weapon_item(PISTOL)
	inv.add(w)
	inv.equip_item(w)
	assert_eq(inv.equipped_item, w, "precondition: it's the equipped instance")
	var lost := [0]
	inv.equipped_item_lost.connect(func() -> void: lost[0] += 1)
	inv.unequip()
	assert_true(inv.equipped_item == null,
		"unequip clears the equipped marker")
	assert_true(inv.has(w),
		"unequip keeps the weapon in the backpack (it's only put away, not dropped)")
	assert_eq(lost[0], 1,
		"unequip fires equipped_item_lost (owner falls back to fists)")
	inv.unequip()
	assert_eq(lost[0], 1,
		"unequip with nothing equipped is a no-op — no second equipped_item_lost")
	inv.free()
	w = null


func test_equip_non_weapon_returns_false_no_signal() -> void:
	var inv := CharacterInventory.new()
	var ammo := _stackable(5)
	inv.add(ammo, 1)
	watch_signals(inv)
	var ok := inv.equip_item(ammo)
	assert_false(ok,
		"equip_item() returns false for a non-weapon item — there's nothing to draw")
	assert_signal_not_emitted(inv, "equip_weapon_requested",
		"A non-weapon equip must emit no weapon request")
	inv.free()
	ammo = null
