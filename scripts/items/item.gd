@tool
class_name Item
extends Resource

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## A single inventory item. Generic on purpose: WEAPONS are one category (carrying the equippable
## WeaponData in `weapon`), leaving room for consumables / ammo / junk later WITHOUT a per-type subclass.
## We deliberately keep ONE Item class with an optional `weapon` field rather than a `WeaponItem` subclass,
## because Godot 4's typed-array .tres serialization doesn't reliably resolve a script_class subclass
## inside an Array[Item] (same trap documented in swap_weapons.gd's weapon_slots).
## @tool only so the `caliber` (ammo) and `installs_ability` (upgrade chip) dropdowns self-populate from disk
## (see _validate_property) — no lifecycle, nothing instanced in-editor.

## Drives the `caliber` dropdown from the ammo calibers on disk (const-preloaded, NO class_name — see calibers.gd).
const Calibers = preload("res://scripts/items/calibers.gd")
## Drives the `installs_ability` dropdown from the ability scenes on disk (const-preloaded, NO class_name — see
## ability_registry.gd). Same source UpgradePickup uses for its unlock_id dropdown.
const AbilityRegistry = preload("res://scripts/components/abilities/ability_registry.gd")

enum Category { WEAPON, CONSUMABLE, AMMO, MISC }

@export_group("Identity & Display")
## Stable lookup key — unique per item .tres. Used by ItemDb + (later) save/load.
@export var id: StringName = &""
## The item's name as shown in the inventory / loot UI and pickup prompts.
@export var display_name: String = ""
## Flavour / tooltip text describing the item (multiline). Shown in the inventory detail view.
@export_multiline var description: String = ""
## Optional AUTHORED inventory icon — when set, grid tiles draw it (winning over any baked
## resources/icons/<id>.png and the live mesh render). Usually left null: the CYBER SUNDAY Icons baker covers
## EVERY item (an authored model when the item has one, else a procedural primitive stand-in), so this is the
## override for when a hand-made 2D icon should replace both.
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
## OPTIONAL StatusEffect applied to the user when this consumable is used (a stim / buff / poison). Works
## alongside or instead of heal_amount — using the item applies this to the player's StatusEffectManager.
@export var consumable_effect: StatusEffect
## OPTIONAL passive buff granted WHILE this item is merely CARRIED in the backpack — the Dota / ARTS idiom: no
## equip step, the bonus is on the instant the item enters the bag and off the instant it leaves. Reuses the
## StatusEffect resource purely as a data PAYLOAD: only its `stat_modifiers` (per-stat additive) and
## `speed_multiplier` are read — its duration / tick_interval / damage_per_tick / visual_effect are IGNORED
## (author duration = 0 by convention). UNLIKE `consumable_effect` (applied ONCE on use, then timed), this one is
## reconciled against inventory presence by the carrier's PassiveItemBuffs component. NOTE: a strength modifier
## re-stamps carry_capacity + max_hp here (unlike a timed StatusEffect, which can't move those spawn-stamped
## values). Buffs still never mutate get_stat(); DialogueView folds the live modifier into dialogue stat checks,
## while raw get_stat gates stay raw unless they explicitly add status_stat_modifier().
@export var held_passive_effect: StatusEffect
## For a held_passive_effect: when TRUE, carrying MULTIPLE copies still grants the buff only ONCE (the Dota
## "unique" items — boots, etc.). Default false = the buff STACKS additively with the count held (2 copies = 2×).
@export var passive_unique: bool = false
@export_group("Upgrade Chip")
## When set, this item is a MICROCHIP UPGRADE: carrying it does nothing on its own, but a ChipInstaller mechanic
## CONSUMES it to permanently grant the named player ability via Player.unlock_mechanic. The value is a mechanic
## id from scripts/components/abilities/ (wall_climb, grapple, slide, air_dash, fall_immunity) — the
## SAME registry UpgradePickup's grants/unlock_id draws from — picked from the dropdown below. Blank = an ordinary
## item (not a chip). Author the chip's microchip look via `world_model` and its install economy via `value` (the
## installer's fee/markup multiply it). See scripts/components/chip_installer.gd + scripts/ui/chip_install_screen.gd.
@export var installs_ability: StringName = &""
@export_group("Weapon Mod")
## When set, this item is a WEAPON PART: carrying it does nothing, but a WeaponBench FITS it into one of a
## weapon's six slots for a labour fee (and pulls it back out for a smaller one, returning the part). Blank =
## an ordinary item. The economy rides `value` exactly as a chip's does — the bench's fit / remove / buy
## multipliers all scale it — and `display_name` / `description` / `icon` stay HERE rather than on the payload,
## so a part is named once whether it's on a shelf, in your pack, or fitted to a gun.
## Authored INLINE (a new WeaponMod sub-resource on this .tres, with its WeaponStatDelta lines inline in turn),
## so a new part is one file in resources/items/ that ItemDb's boot folder scan registers for free.
## See scripts/items/weapon_mod.gd + scripts/components/weapon_bench.gd.
@export var weapon_mod: WeaponMod
@export_group("World Model")
## OPTIONAL unique 3D model for this item when it sits in the WORLD — a dropped / looted / code-spawned
## CanPickUp with `build_model_from_item` set builds this and auto-fits its hover hitbox to it. Accepts model
## scenes (.glb/.gltf/.blend) and raw Mesh resources (.obj). Null =
## the pickup keeps whatever visual it was authored with. Inventory + UI still use display_name / icon; this
## is purely the dropped-in-world look, so different items can litter the ground as their own models.
@export var world_model: Resource = null
## OPTIONAL full PROP scene this item BECOMES when dropped or hand-placed in the world (consumed by
## WorldItem.build, which Player.drop_item and the editor item-placer share). Unlike `world_model` (a plain
## VISUAL instanced as a pickup's mesh), this is the WHOLE authored object, so the dropped item keeps its own
## behaviour — a destructible crate that spawns a dog on break, a barrel with a loot table, a prop with custom
## ThrowableData. Takes precedence over the placeholder box. The scene should root a Node3D that wraps a
## `Throwable` (so Z carries/throws it) and a `CanPickUp` granting THIS item (so E re-stashes it); see
## `res://scenes/props/dogcrate.tscn`. Blank = the default placeholder/weapon-model drop. Best for unstackable props
## (one instance is spawned regardless of drop count).
##
## Stored as a PATH (not a PackedScene reference) ON PURPOSE: the prop's CanPickUp points back at THIS item, so a
## direct PackedScene export would form a load-time resource CYCLE ("Recursion detected, unable to assign resource
## to property"). A path is not a load-time dependency — WorldItem.build load()s it lazily at drop time, by when
## this item is already loaded — so the back-reference is fine. Use the inspector's file picker (or drag a .tscn in).
@export_file("*.tscn") var world_prop: String = ""
@export_group("Inventory grid")
## Width in inventory grid CELLS (Tetris-style spatial inventory). 1 = a single cell; a pistol might be 2×1,
## a rifle 4×2. Clamped to at least 1. The item occupies grid_width × grid_height cells (rotatable in the UI).
@export var grid_width: int = 1:
	set(value):
		grid_width = maxi(1, value)
## Height in inventory grid CELLS. 1 = a single cell. Clamped to at least 1.
@export var grid_height: int = 1:
	set(value):
		grid_height = maxi(1, value)

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

## True when this item is a MICROCHIP UPGRADE — carrying it grants nothing, but a ChipInstaller can consume it to
## install `installs_ability` on the player. The mechanic + ChipInstallScreen key on this.
func is_upgrade_chip() -> bool:
	return installs_ability != &""

## True when this item is a WEAPON PART a WeaponBench can fit into a gun. The WeaponMod payload keys on this —
## the bench, the bench screen and ItemInfo's part tooltip all gate here, never on `category` (a part is an
## ordinary MISC item so it loots / stacks / sells like one).
func is_weapon_mod() -> bool:
	return weapon_mod != null

## True when this item can be pulled from the HOTBAR and CARRIED in your hands as a physics prop — a `world_prop`
## like the dog / crate, or any item with a `world_model` (WorldItem.build wraps both in a Throwable). Excludes
## weapons (equipped), consumables (used), ammo, upgrade chips (installed) and weapon parts (FITTED at a bench)
## — those have their own slot/UI action. Also EXCLUDES the Zorkmids coin tile a LOOT bag carries: it wears a
## `world_model` (the money-bag mesh) but is MONEY, not a carryable prop. Drives Hotbar.assign + _activate's "hold" branch
## (Player.hold_item does the pull-out/stash-back).
func is_holdable() -> bool:
	# A coin tile carries a `world_model` (the bag mesh) yet is MONEY, not a prop. Slotting it on the hotbar
	# (hotbar.assign) then activating it (hotbar._activate) would pull a physics money-bag into the hands out of
	# nothing — cash that no wallet was ever debited for. The player's own zorkmids never reach a bag any more
	# (they are the `money` float), but a LOOT source's coin tile is a real Item, so the guard still earns its
	# keep. One chokepoint covers both the assign guard and the _activate holdable branch. (F-C13-C28)
	if id == Zorkmids.ITEM_ID:
		return false
	# A weapon PART is fitted at a bench, never carried in the hands as a physics prop — the same reasoning that
	# excludes a chip. It ships a `world_model` for its dropped/loot look, which is exactly what would otherwise
	# let the hotbar pull a scope out into your fists.
	if is_weapon() or is_consumable() or is_ammo() or is_upgrade_chip() or is_weapon_mod():
		return false
	return not world_prop.is_empty() or world_model != null

## A readable label for the UI: display_name, else the id, else a generic fallback.
func label() -> String:
	if not display_name.is_empty():
		return display_name
	if id != &"":
		return String(id)
	return "Item"

## A fully INDEPENDENT copy of this item, deep-copying the `weapon` sub-resource so the copy's WeaponData stats
## can diverge from the template (and from sibling instances) without aliasing them. This is the per-instance
## weapon-state seam (EL-3): the acquire pipeline still shares the template WeaponData by default — because the
## codebase keys a weapon's KIND off WeaponData object identity (hotbar grouping, the swap-system no-op) — so
## callers opt into uniqueness ONLY when they actually need a divergent stat block (loot rarity / variance /
## future weapon mods). Roll the copy, then mutate `copy.weapon` freely. Non-weapon items stack by shared-
## template identity, so this returns the shared template unchanged for them.
func clone_unique() -> Item:
	if not is_weapon():
		return self
	var copy := duplicate() as Item
	copy.weapon = weapon.duplicate()  # its OWN WeaponData — mutating it won't touch the template or other instances
	return copy

## Self-populate the `caliber` dropdown from the ammo calibers on disk (a SUGGESTION hint, so blank for a
## non-ammo item stays valid and a brand-new caliber is still typable when defining a new ammo type). Keeps an
## ammo item's caliber spelled consistently with the weapons that draw from it.
func _validate_property(property: Dictionary) -> void:
	if property.name == "world_model":
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT
	if property.name == "caliber":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Calibers.ids_csv()
	if property.name == "installs_ability":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = AbilityRegistry.ids_csv()
