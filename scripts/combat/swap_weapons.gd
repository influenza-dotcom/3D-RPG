class_name SwapWeapons
extends Node3D

signal equip_this(_weapon: WeaponData)

# Designer-facing weapon slot assignment. Drop WeaponData .tres references
# into this array in the inspector to override the defaults below. Index 0
# maps to "Weapon Slot 1" input, index 1 to "Weapon Slot 2", etc.
#
# Typed as Array[Resource] (not Array[WeaponData]) because Godot 4's typed-
# array serialization in .tscn doesn't reliably resolve script_class types
# at parse time — explicit assignment in the scene file fails silently. We
# validate the contents are WeaponData at use time via `as WeaponData`.
#
# Defaults are provided here via preload() so the game works out-of-box.
# To customize, populate the array on the SwapWeapons node in weapon.tscn
# (or any inheriting scene) — your assignment will override these defaults.
@export var weapon_slots: Array[Resource] = [
	preload("res://resources/weapons/pistol.tres"),
	preload("uid://bu7caixpr0wo"),
	preload("res://resources/weapons/shotgun.tres"),
	preload("res://resources/weapons/smg.tres"),
	preload("res://resources/weapons/melee.tres"),
	preload("res://resources/weapons/spray_paint.tres"),
	preload("uid://diw35ysd2f0lg") ##sniper weapon
]

## Optional data-driven loadout. When assigned (with a non-empty weapons list) its weapons REPLACE
## weapon_slots, and the Player reads its starting clips + money from it — so a difficulty / scenario kit is
## one Loadout resource instead of editing this array + the player's consts. Null = the defaults above.
@export var loadout: Loadout = null

# The number-key handler is GONE: the player equips weapons from the inventory UI (Tab), not keys 1-7.
# The slots stay as the authored STARTING LOADOUT (Player seeds its backpack from them in _ready) and the
# swap path is preserved — request_equip()/_try_equip() still drive the down/up swap animation by emitting
# equip_this, which weapon.tscn wires to Attack._on_swap_weapons_equip_this.

## Equip `weapon` through the swap path (Attack plays the swap animation on the equip_this connection,
## then updates the hub). The public entry the inventory equip bridge (Weapon.equip_weapon) calls.
func request_equip(weapon: WeaponData) -> void:
	if weapon == null:
		return
	equip_this.emit(weapon)

## Equip the weapon in slot `index` of the authored loadout. Kept for completeness / future rebinding now
## that the number keys are gone; routes through the same swap path as the UI.
func _try_equip(index: int) -> void:
	var slots := effective_slots()
	if index < 0 or index >= slots.size():
		return
	request_equip(slots[index] as WeaponData)

## The weapons the player actually starts with: a Loadout's list when one is assigned (and non-empty), else
## the authored weapon_slots defaults. weapon_system.weapon_loadout() + the player's backpack seed read this.
func effective_slots() -> Array:
	if loadout != null and not loadout.weapons.is_empty():
		return loadout.weapons
	return weapon_slots
