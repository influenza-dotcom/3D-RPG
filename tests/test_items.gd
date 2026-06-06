extends GutTest

## Item model + ItemDb registry — GUT unit suite (Phase A of the inventory feature).
##
## COVERS:
##   - Item SOURCE defaults via Item.new() (NOT a .tres): category MISC, max_stack 1,
##     empty id/display_name, null weapon, is_weapon()/is_stackable() false, generic label().
##   - Item.is_weapon(): true ONLY when category==WEAPON AND weapon!=null (a WEAPON item
##     with no WeaponData, and a non-WEAPON item carrying one, are both non-weapons).
##   - Item.label() priority ladder: display_name > id > "Item".
##   - Item.is_stackable(): keyed off max_stack > 1.
##   - pistol_item.tres wiring: loads as an Item, WEAPON category, wraps the SAME pistol
##     WeaponData the rig uses (cached by path), equippable, labelled "Pistol".
##   - ItemDb autoload: all 7 weapon-items registered; weapon_item_for() round-trips a
##     WeaponData to its item; distinct weapons -> distinct items; null and an
##     unregistered WeaponData both resolve to null.
##
## Conventions match test_combat_data.gd: extends GutTest, func test_*() -> void,
## class_name Item used directly. Item extends Resource (RefCounted), so instances are
## made with .new() and released with `= null` (NEVER .free() — that errors on a
## RefCounted), exactly like the WeaponData/ThrowableData cases there. ItemDb is reached
## as the autoload singleton, like AudioManager/InputManager in test_autoload_order.gd.

const PISTOL := preload("res://resources/weapons/pistol.tres")
const SHOTGUN := preload("res://resources/weapons/shotgun.tres")
const PISTOL_ITEM := preload("res://resources/items/pistol_item.tres")


# ---------------------------------------------------------------------------
# Item — source defaults (Item.new(), NOT a .tres).
# ---------------------------------------------------------------------------

func test_item_defaults() -> void:
	var it := Item.new()
	assert_eq(it.category, Item.Category.MISC,
		"A fresh Item defaults to MISC — only an authored weapon/consumable .tres picks a real category")
	assert_eq(it.max_stack, 1,
		"max_stack defaults to 1 (unstackable) — stackables must opt in by raising it")
	assert_eq(it.id, &"",
		"id defaults to the empty StringName until an authored .tres names it")
	assert_eq(it.display_name, "",
		"display_name defaults empty — label() then falls back to id, then a generic")
	assert_true(it.weapon == null,
		"weapon defaults null — only WEAPON-category items carry a WeaponData")
	assert_false(it.is_weapon(),
		"A default MISC item with no weapon is not equippable")
	assert_false(it.is_stackable(),
		"max_stack 1 means not stackable")
	it = null


func test_item_label_fallback_ladder() -> void:
	var it := Item.new()
	assert_eq(it.label(), "Item",
		"With no display_name and no id, label() returns the generic 'Item'")
	it.id = &"rock"
	assert_eq(it.label(), "rock",
		"With an id but no display_name, label() returns the id text")
	it.display_name = "Heavy Rock"
	assert_eq(it.label(), "Heavy Rock",
		"display_name wins over id when both are set")
	it = null


func test_item_is_weapon_requires_category_and_weapon() -> void:
	var it := Item.new()
	it.weapon = WeaponData.new()
	assert_false(it.is_weapon(),
		"A WeaponData on a MISC item is NOT equippable — the category must be WEAPON too")
	it.category = Item.Category.WEAPON
	assert_true(it.is_weapon(),
		"WEAPON category + a WeaponData = equippable")
	it.weapon = null
	assert_false(it.is_weapon(),
		"WEAPON category with no WeaponData is not equippable — nothing to equip")
	it = null


func test_item_is_stackable_tracks_max_stack() -> void:
	var it := Item.new()
	it.max_stack = 20
	assert_true(it.is_stackable(),
		"max_stack > 1 makes the item stackable (ammo/consumables)")
	it = null


# ---------------------------------------------------------------------------
# pistol_item.tres — load-bearing resource wiring.
# ---------------------------------------------------------------------------

func test_pistol_item_tres_is_equippable_pistol() -> void:
	assert_true(PISTOL_ITEM is Item,
		"pistol_item.tres must load as an Item so it can sit in a CharacterInventory")
	assert_eq(PISTOL_ITEM.category, Item.Category.WEAPON,
		"pistol_item.tres is a WEAPON-category item")
	assert_true(PISTOL_ITEM.is_weapon(),
		"pistol_item.tres must be equippable (WEAPON + a WeaponData)")
	assert_eq(PISTOL_ITEM.weapon, PISTOL,
		"pistol_item.tres must wrap the SAME pistol WeaponData the weapon rig uses (cached by path)")
	assert_eq(PISTOL_ITEM.label(), "Pistol",
		"pistol_item.tres is labelled 'Pistol' for the inventory list")


# ---------------------------------------------------------------------------
# ItemDb autoload — the WeaponData -> Item registry.
# ---------------------------------------------------------------------------

func test_item_db_registers_all_weapon_items() -> void:
	assert_not_null(ItemDb,
		"ItemDb autoload must be loaded — player/NPC/loot all resolve weapons through it")
	assert_eq(ItemDb.all_items().size(), 12,
		"ItemDb registers all 7 weapon-items + 5 ammo-items (pistol/smg/shells/rifle/grenades); a smaller count means a .tres failed to load")


func test_item_db_weapon_item_for_round_trips() -> void:
	var item := ItemDb.weapon_item_for(PISTOL)
	assert_not_null(item,
		"weapon_item_for(pistol) must return the registered pistol item")
	assert_true(item.is_weapon(),
		"The item ItemDb returns for a weapon must itself be equippable")
	assert_eq(item.weapon, PISTOL,
		"weapon_item_for(pistol) must wrap the pistol WeaponData it was queried with")
	var shotgun_item := ItemDb.weapon_item_for(SHOTGUN)
	assert_true(shotgun_item != item,
		"Distinct weapons must resolve to distinct items")


func test_item_db_weapon_item_for_unknown_is_null() -> void:
	assert_true(ItemDb.weapon_item_for(null) == null,
		"weapon_item_for(null) must return null — no weapon, no item")
	var stray := WeaponData.new()
	assert_true(ItemDb.weapon_item_for(stray) == null,
		"An unregistered WeaponData (not one of the 7 authored .tres) has no item — returns null")
	stray = null


func test_item_db_make_weapon_item_is_unique() -> void:
	var a := ItemDb.make_weapon_item(PISTOL)
	var b := ItemDb.make_weapon_item(PISTOL)
	assert_not_null(a, "make_weapon_item returns an item for a registered weapon")
	assert_true(a != b,
		"each make_weapon_item call returns a DISTINCT instance — two pistols are their own objects")
	assert_true(a != ItemDb.weapon_item_for(PISTOL),
		"the acquired item is a fresh copy, not the shared registry template")
	assert_eq(a.weapon, PISTOL,
		"the unique copy still references the same (shared) WeaponData")
	assert_true(a.is_weapon(),
		"the unique copy is equippable")
	assert_true(ItemDb.make_weapon_item(null) == null,
		"make_weapon_item(null) is null — no weapon, no item")
	a = null
	b = null


func test_item_db_ammo_item_for_caliber() -> void:
	var clip := ItemDb.ammo_item_for(&"pistol")
	assert_not_null(clip, "ammo_item_for('pistol') returns the registered pistol-clip ammo item")
	assert_true(clip.is_ammo(),
		"the pistol clip is AMMO-category carrying a caliber")
	assert_eq(clip.caliber, &"pistol",
		"it carries the pistol caliber")
	assert_false(clip.is_weapon(),
		"ammo is not a weapon")
	assert_true(clip.is_stackable(),
		"ammo stacks (max_stack > 1) — spare clips pile up")
	assert_true(ItemDb.ammo_item_for(&"") == null,
		"ammo_item_for('') is null")
	assert_true(ItemDb.ammo_item_for(&"plasma") == null,
		"an unregistered caliber has no ammo item")


func test_weapons_have_distinct_magazines() -> void:
	# Each gun has its OWN magazine type: we track CLIPS, and a pistol mag (10) != an SMG mag (30), so
	# they can't share a pool even though both fire 9mm. Shotgun/sniper have their own; melee has none.
	assert_eq(PISTOL.caliber, &"pistol",
		"the pistol uses pistol magazines")
	var smg: WeaponData = preload("res://resources/weapons/smg.tres")
	assert_eq(smg.caliber, &"smg",
		"the SMG uses SMG magazines")
	assert_true(PISTOL.caliber != smg.caliber,
		"pistol and SMG must NOT share a magazine pool — different mag sizes (10 vs 30)")
	assert_eq(SHOTGUN.caliber, &"shells",
		"the shotgun uses shells")
	var melee: WeaponData = preload("res://resources/weapons/melee.tres")
	assert_eq(melee.caliber, &"",
		"melee has no caliber — it reloads free / uses no reserve ammo")
