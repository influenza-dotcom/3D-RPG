@tool
class_name Item
extends Resource

## A single inventory item. Generic on purpose: WEAPONS are one category (carrying the equippable
## WeaponData in `weapon`), leaving room for consumables / ammo / junk later WITHOUT a per-type subclass.
## We deliberately keep ONE Item class with an optional `weapon` field rather than a `WeaponItem` subclass,
## because Godot 4's typed-array .tres serialization doesn't reliably resolve a script_class subclass
## inside an Array[Item] (same trap documented in swap_weapons.gd's weapon_slots).
## @tool only so an AMMO item's `caliber` self-populates its dropdown (see _validate_property) — no lifecycle.

## Drives the `caliber` dropdown from the ammo calibers on disk (const-preloaded, NO class_name — see calibers.gd).
const Calibers = preload("res://scripts/items/calibers.gd")

enum Category { WEAPON, CONSUMABLE, AMMO, MISC }

@export_group("Identity & Display")
## Stable lookup key — unique per item .tres. Used by ItemDb + (later) save/load.
@export var id: StringName = &""
## The item's name as shown in the inventory / loot UI and pickup prompts.
@export var display_name: String = ""
## Flavour / tooltip text describing the item (multiline). Shown in the inventory detail view.
@export_multiline var description: String = ""
## Optional inventory icon. None authored yet — the list UI falls back to the name.
@export var icon: Texture2D
@export_group("Classification & Stats")
## Which kind of item this is — WEAPON / CONSUMABLE / AMMO / MISC. Gates the helpers (is_weapon/is_ammo/is_consumable) and which fields below apply.
@export var category: Category = Category.MISC
## How many fit in one stack. 1 = unstackable (a weapon); >1 lets ammo / consumables stack.
@export var max_stack: int = 1
## The equippable weapon this item represents — set ONLY on WEAPON-category items; null otherwise.
@export var weapon: WeaponData
## For AMMO-category items: the caliber these rounds provide (e.g. &"9mm"), matched against a weapon's
## caliber on reload. Empty for non-ammo items.
@export var caliber: StringName = &""
## Carry weight (abstract units) of ONE of this item — summed into the carrier's load; weapons are heavy,
## ammo light, junk in between. A Character is ENCUMBERED (slowed) once its total exceeds carry_capacity.
@export var weight: float = 1.0
## Base trade value in zorkmids — what this item is worth at a merchant. The player BUYS it at value × the
## merchant's buy multiplier and SELLS it at value × the (lower) sell multiplier. 0 = worthless (can't sell).
## FRACTIONAL: zorkmids run in hundredths (0.5 = half a zorkmid), so cheap goods can price under 1 zm.
@export var value: float = 0.0
## For CONSUMABLE-category items: HP restored when used from the inventory (Player.use_consumable). The
## first consumable effect — later ones (stims, buffs) hang off the same category without a subclass.
@export var heal_amount: float = 0.0
@export_group("World Model")
## OPTIONAL unique 3D model for this item when it sits in the WORLD — a dropped / looted / code-spawned
## CanPickUp with `build_model_from_item` set instantiates this and auto-fits its hover hitbox to it. Null =
## the pickup keeps whatever visual it was authored with. Inventory + UI still use display_name / icon; this
## is purely the dropped-in-world look, so different items can litter the ground as their own models.
@export var world_model: PackedScene = null

## True when this item can be equipped as a weapon (WEAPON category carrying a real WeaponData).
func is_weapon() -> bool:
	return category == Category.WEAPON and weapon != null

## True when this item is reserve ammo (AMMO category carrying a caliber).
func is_ammo() -> bool:
	return category == Category.AMMO and caliber != &""

## True when this item can be USED from the inventory (CONSUMABLE category — e.g. a health pack).
func is_consumable() -> bool:
	return category == Category.CONSUMABLE

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

## Self-populate the `caliber` dropdown from the ammo calibers on disk (a SUGGESTION hint, so blank for a
## non-ammo item stays valid and a brand-new caliber is still typable when defining a new ammo type). Keeps an
## ammo item's caliber spelled consistently with the weapons that draw from it.
func _validate_property(property: Dictionary) -> void:
	if property.name == "caliber":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Calibers.ids_csv()
