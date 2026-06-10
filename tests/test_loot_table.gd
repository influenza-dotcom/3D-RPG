extends GutTest

## LootTable / LootEntry (Wave 2) — data-driven loot. roll() is PURE (a seeded RNG -> deterministic); grant()
## adds to an inventory with weapons as UNIQUE instances. Off-tree (Resources + a CharacterInventory node).

func _entry(item: Item, chance: float, lo: int, hi: int) -> LootEntry:
	var e := LootEntry.new()
	e.item = item
	e.chance = chance
	e.min_count = lo
	e.max_count = hi
	return e

func _stackable(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	it.max_stack = 99
	return it


func test_roll_is_deterministic_with_a_seeded_rng() -> void:
	var t := LootTable.new()
	var ammo := _stackable(&"ammo9mm")
	var es: Array[LootEntry] = [_entry(ammo, 1.0, 2, 2)]  # always drops, exactly 2
	t.entries = es
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var drops := t.roll(rng)
	assert_eq(drops.size(), 1, "a chance-1.0 entry always drops")
	assert_eq(drops[0]["item"], ammo, "the drop carries the entry's item")
	assert_eq(drops[0]["count"], 2, "min == max == 2 -> exactly 2")
	t = null
	ammo = null


func test_zero_chance_never_drops() -> void:
	var t := LootTable.new()
	var es: Array[LootEntry] = [_entry(_stackable(&"junk"), 0.0, 1, 5)]
	t.entries = es
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var total := 0
	for i in 25:
		total += t.roll(rng).size()
	assert_eq(total, 0, "a chance-0.0 entry never drops, across many rolls")
	t = null


func test_grant_adds_to_inventory_with_weapons_unique() -> void:
	var t := LootTable.new()
	var ammo := _stackable(&"ammo9mm")
	var weapon := Item.new()
	weapon.category = Item.Category.WEAPON
	weapon.weapon = WeaponData.new()
	var es: Array[LootEntry] = [_entry(ammo, 1.0, 3, 3), _entry(weapon, 1.0, 2, 2)]
	t.entries = es
	var inv := CharacterInventory.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	t.grant(inv, rng)
	assert_eq(inv.count_of(ammo), 3, "ammo granted as a stack of the SHARED item")
	assert_eq(inv.count_of(weapon), 0, "the shared weapon TEMPLATE is not added — weapons are duplicated")
	assert_eq(inv.contents().size(), 3, "3 stacks: 1 ammo + 2 distinct weapon instances")
	inv.free()
	t = null
	ammo = null
	weapon = null
