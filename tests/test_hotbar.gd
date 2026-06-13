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


func test_hotbar_one_slot_per_weapon_kind() -> void:
	# Weapons are unique ITEM instances, so five looted pistols would otherwise flood five slots — the bar
	# keeps ONE slot per WeaponData kind; duplicates stay bag-only and inherit the slot when it vacates.
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var pistol_data := WeaponData.new()
	var pistol_a := _make_item(&"pistol", Item.Category.WEAPON)
	pistol_a.weapon = pistol_data
	var pistol_b := _make_item(&"pistol", Item.Category.WEAPON)
	pistol_b.weapon = pistol_data  # a second INSTANCE of the same kind
	var shotgun := _make_item(&"shotgun", Item.Category.WEAPON)
	inv.add(pistol_a)
	inv.add(pistol_b)
	inv.add(shotgun)
	var hb := Hotbar.new()
	hb.setup(p)
	assert_eq(hb._items[0], pistol_a, "the first pistol takes slot 1")
	assert_eq(hb._items[1], shotgun, "the DUPLICATE pistol is skipped — the shotgun takes slot 2")
	assert_null(hb._items[2], "only two slots used")
	inv.equip_item(pistol_b)  # the bag UI can equip the BAG-ONLY duplicate...
	assert_true(hb._is_equipped_kind(pistol_a, inv),
		"...and the slotted same-kind item still reads as equipped (kind-aware highlight / cycle anchor)")
	inv.remove(pistol_a, 1)
	assert_true(hb._items.has(pistol_b), "dropping the slotted pistol hands its slot to the duplicate")
	hb.free()
	p.free()
	inv.free()


func test_hotbar_scroll_cycles_weapons_only() -> void:
	# The wheel walks WEAPON slots with wrap — consumables are skipped (scrolling past a medkit must never
	# use it) and bare fists enters at the first weapon (down) / last (up).
	var p = load(PLAYER_PATH).new()
	var inv := CharacterInventory.new()
	p.inventory = inv
	var gun_a := _make_item(&"a", Item.Category.WEAPON)
	var medkit := _make_item(&"m", Item.Category.CONSUMABLE, 5)
	var gun_b := _make_item(&"b", Item.Category.WEAPON)
	inv.add(gun_a)
	inv.add(medkit)
	inv.add(gun_b)
	var hb := Hotbar.new()
	hb.setup(p)  # slots: [gun_a, medkit, gun_b]; nothing equipped (fists)
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_a, "from fists, wheel-down equips the FIRST weapon slot")
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_b, "next SKIPS the consumable straight to the next weapon")
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_a, "...and wraps back around")
	hb._cycle(-1)
	assert_eq(inv.equipped_item, gun_b, "wheel-up steps backward (wrapping)")
	inv.remove(gun_b, 1)  # the equipped weapon leaves the bag -> fists
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_a, "from fists with one weapon left, the wheel equips it")
	hb._cycle(1)
	assert_eq(inv.equipped_item, gun_a, "a single carried weapon has nowhere to scroll — stays equipped")
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
