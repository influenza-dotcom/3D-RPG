extends GutTest

## The Deus Ex hotbar's AUTO-ASSIGNMENT: weapons + consumables take the first free slot, ammo/misc are
## skipped, and items that leave the bag vacate their slot. Off-tree: a bare player is handed a bare
## CharacterInventory directly (no _ready anywhere), and the Hotbar builds its Control chrome unparented.
## The key handling + equip/use activation are in-tree behaviour (playtested).

const PLAYER_PATH := "res://scripts/player/player.gd"


func _make_item(id: StringName, category: int, stack: int = 1) -> Item:
	var it := Item.new()
	it.id = id
	it.category = category as Item.Category
	it.max_stack = stack
	if category == Item.Category.WEAPON:
		it.weapon = WeaponData.new()  # is_weapon() requires a real WeaponData
	elif category == Item.Category.AMMO:
		it.caliber = &"9mm"  # is_ammo() requires a caliber
	return it


func test_hotbar_auto_assigns_and_vacates() -> void:
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var gun := _make_item(&"gun", Item.Category.WEAPON)
	var rounds := _make_item(&"rounds", Item.Category.AMMO, 30)
	var medkit := _make_item(&"medkit", Item.Category.CONSUMABLE, 5)
	inv.add(gun)
	inv.add(rounds, 12)
	inv.add(medkit, 3)
	var hb := Hotbar.new()
	hb.setup(p)  # wires inventory.changed + does the first sync
	assert_eq(hb._items[0], gun, "the weapon takes slot 1 (insertion order)")
	assert_eq(hb._items[1], medkit, "the consumable takes the NEXT free slot — ammo is skipped entirely")
	assert_null(hb._items[2], "nothing else assigned")
	inv.remove(gun, 1)
	assert_null(hb._items[0], "an item that left the bag vacates its slot (changed -> re-sync)")
	assert_eq(hb._items[1], medkit, "other slots keep their assignment (stable layout)")
	inv.add(gun)
	assert_eq(hb._items[0], gun, "a re-acquired item fills the first FREE slot again")
	hb.free()
	p.free()
	inv.free()


func test_hotbar_overflow_stays_in_the_bag() -> void:
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var items: Array[Item] = []
	for i in 12:  # two more than the bar holds
		var it := _make_item(StringName("w%d" % i), Item.Category.WEAPON)
		items.append(it)
		inv.add(it)
	var hb := Hotbar.new()
	hb.setup(p)
	assert_eq(hb._items[9], items[9], "the tenth weapon takes the last slot")
	assert_false(hb._items.has(items[10]), "the eleventh stays bag-only — the bar never exceeds 10 slots")
	hb.free()
	p.free()
	inv.free()
