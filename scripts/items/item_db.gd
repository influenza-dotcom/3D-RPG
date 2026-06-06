extends Node

## ItemDb (autoload) — the registry that maps a WeaponData to its weapon-Item, so the player seed, the
## NPC seed, and corpse loot all resolve a weapon to the SAME Item. Weapon-items are authored .tres in
## resources/items/; register a new one by adding its path to WEAPON_ITEM_PATHS. Lookups are O(1) keyed
## by the WeaponData resource (Godot caches a .tres to one instance, so identical refs share a key).

## res:// paths of the weapon-item resources to register at boot.
const WEAPON_ITEM_PATHS: Array[String] = [
	"res://resources/items/pistol_item.tres",
	"res://resources/items/rock_item.tres",
	"res://resources/items/shotgun_item.tres",
	"res://resources/items/smg_item.tres",
	"res://resources/items/melee_item.tres",
	"res://resources/items/spray_paint_item.tres",
	"res://resources/items/sniper_item.tres",
]

## res:// paths of the ammo-item resources (one per caliber) to register at boot.
const AMMO_ITEM_PATHS: Array[String] = [
	"res://resources/items/ammo_pistol.tres",
	"res://resources/items/ammo_smg.tres",
	"res://resources/items/ammo_shells.tres",
	"res://resources/items/ammo_rifle.tres",
	"res://resources/items/ammo_grenades.tres",
]

var _by_weapon: Dictionary = {}    ## WeaponData -> Item (weapon template)
var _by_caliber: Dictionary = {}   ## StringName caliber -> Item (ammo template)
var _all: Array[Item] = []

func _ready() -> void:
	for path in WEAPON_ITEM_PATHS:
		var item := load(path) as Item
		if item == null:
			push_warning("ItemDb: failed to load item '%s' (skipped)" % path)
			continue
		_all.append(item)
		if item.weapon != null:
			_by_weapon[item.weapon] = item
	for path in AMMO_ITEM_PATHS:
		var ammo := load(path) as Item
		if ammo == null:
			push_warning("ItemDb: failed to load ammo item '%s' (skipped)" % path)
			continue
		_all.append(ammo)
		if ammo.caliber != &"":
			_by_caliber[ammo.caliber] = ammo

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
