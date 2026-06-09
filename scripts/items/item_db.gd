extends Node

## ItemDb (autoload) — the registry that maps a WeaponData to its weapon-Item, so the player seed, the
## NPC seed, and corpse loot all resolve a weapon to the SAME Item. Weapon-items + ammo-items are authored
## .tres in resources/items/; register a new one simply by DROPPING ITS .tres IN THAT FOLDER — the folder is
## scanned at boot, so there's no hand-maintained path list to forget. Lookups are O(1) keyed by the
## WeaponData resource (Godot caches a .tres to one instance, so identical refs share a key).

## Folder scanned at boot for item resources: a weapon-item buckets by its WeaponData, an ammo-item by caliber.
const ITEMS_DIR := "res://resources/items"

var _by_weapon: Dictionary = {}    ## WeaponData -> Item (weapon template)
var _by_caliber: Dictionary = {}   ## StringName caliber -> Item (ammo template)
var _all: Array[Item] = []

func _ready() -> void:
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		push_warning("ItemDb: cannot open %s — no items registered" % ITEMS_DIR)
		return
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")  # exported builds may append .remap to packed resources
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var item := load(ITEMS_DIR.path_join(f)) as Item
		if item == null:
			push_warning("ItemDb: '%s' in resources/items/ is not an Item resource (skipped)" % f)
			continue
		_all.append(item)
		if item.weapon != null:
			_by_weapon[item.weapon] = item
		elif item.caliber != &"":
			_by_caliber[item.caliber] = item

## The registered TEMPLATE weapon-Item for `weapon` (shared, for lookup), or null if none is registered.
## To ACQUIRE a weapon into an inventory, use make_weapon_item() instead so each one is its own object.
func weapon_item_for(weapon: WeaponData) -> Item:
	if weapon == null:
		return null
	return _by_weapon.get(weapon, null)

## A FRESH, UNIQUE weapon-Item for `weapon` — a duplicate of the registered template, so every acquired
## weapon is its own object: two pistols (seeded + looted) are DISTINCT items, and equipping one marks
## only that one. The WeaponData itself stays shared (duplicate() doesn't deep-copy sub-resources).
## null if the weapon isn't registered. Use this for the player seed, NPC seed, and loot.
func make_weapon_item(weapon: WeaponData) -> Item:
	var template := weapon_item_for(weapon)
	return template.duplicate() as Item if template != null else null

## The shared ammo-Item template for `caliber` (e.g. &"9mm"), or null if none is registered. Ammo stacks
## by type, so the SHARED template is used directly (no per-instance uniqueness like weapons). Used to
## seed reserve ammo and to author clip pickups.
func ammo_item_for(caliber: StringName) -> Item:
	if caliber == &"":
		return null
	return _by_caliber.get(caliber, null)

## Every registered item (copy, so callers can't mutate the registry). For tools / UI / debug.
func all_items() -> Array[Item]:
	return _all.duplicate()
