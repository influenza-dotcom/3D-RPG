class_name Item
extends Resource

## A single inventory item. Generic on purpose: WEAPONS are one category (carrying the equippable
## WeaponData in `weapon`), leaving room for consumables / ammo / junk later WITHOUT a per-type subclass.
## We deliberately keep ONE Item class with an optional `weapon` field rather than a `WeaponItem` subclass,
## because Godot 4's typed-array .tres serialization doesn't reliably resolve a script_class subclass
## inside an Array[Item] (same trap documented in swap_weapons.gd's weapon_slots).

enum Category { WEAPON, CONSUMABLE, AMMO, MISC }

## Stable lookup key — unique per item .tres. Used by ItemDb + (later) save/load.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Optional inventory icon. None authored yet — the list UI falls back to the name.
@export var icon: Texture2D
@export var category: Category = Category.MISC
## How many fit in one stack. 1 = unstackable (a weapon); >1 lets ammo / consumables stack.
@export var max_stack: int = 1
## The equippable weapon this item represents — set ONLY on WEAPON-category items; null otherwise.
@export var weapon: WeaponData

## True when this item can be equipped as a weapon (WEAPON category carrying a real WeaponData).
func is_weapon() -> bool:
	return category == Category.WEAPON and weapon != null

## True when more than one fits in a stack.
func is_stackable() -> bool:
	return max_stack > 1

## A readable label for the UI: display_name, else the id, else a generic fallback.
func label() -> String:
	if not display_name.is_empty():
		return display_name
	if id != &"":
		return String(id)
	return "Item"
