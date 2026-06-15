extends GutTest

## ItemStack.seed_into -- the count-based inventory authoring: a stackable seeds to its count, a weapon seeds as
## that many UNIQUE instances (distinct stacks), and null / null-item / zero-count rows are skipped. Off-tree:
## CharacterInventory.new() with NO add_child (add() only mutates _stacks + emits a signal -- no tree access).

const AMMO := "res://resources/items/ammo_pistol.tres"
const PISTOL := "res://resources/items/pistol_item.tres"

func _stack(it: Item, n: int) -> ItemStack:
	var s := ItemStack.new()
	s.item = it
	s.count = n
	return s

## Total carried count of `it` across all stacks (a large count may split across stacks at Item.max_stack).
func _total(inv: CharacterInventory, it: Item) -> int:
	var n := 0
	for s in inv.contents():
		if s["item"] == it:
			n += int(s["count"])
	return n

func test_stackable_seeds_to_its_count() -> void:
	var inv := CharacterInventory.new()
	var ammo: Item = load(AMMO)
	var stacks: Array[ItemStack] = [_stack(ammo, 30)]
	ItemStack.seed_into(inv, stacks)
	assert_eq(_total(inv, ammo), 30, "a stackable row seeds to its count")
	inv.free()

func test_weapon_count_seeds_unique_instances() -> void:
	var inv := CharacterInventory.new()
	var pistol: Item = load(PISTOL)
	assert_true(pistol.is_weapon(), "precondition: pistol_item is a weapon-item")
	var stacks: Array[ItemStack] = [_stack(pistol, 2)]
	ItemStack.seed_into(inv, stacks)
	# Weapons are unique instances (max_stack 1) -> two DISTINCT stacks, not one stack of 2.
	assert_eq(inv.contents().size(), 2, "a weapon row of 2 seeds two distinct instances")
	inv.free()

func test_empty_rows_are_skipped() -> void:
	var inv := CharacterInventory.new()
	var ammo: Item = load(AMMO)
	var stacks: Array[ItemStack] = [null, _stack(null, 5), _stack(ammo, 0)]
	ItemStack.seed_into(inv, stacks)
	assert_true(inv.is_empty(), "null row, null item, and zero count are all skipped")
	inv.free()
