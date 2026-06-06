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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_weapon_slot_1):
		_try_equip(0)
	elif event.is_action_pressed(InputManager.action_weapon_slot_2):
		_try_equip(1)
	elif event.is_action_pressed(InputManager.action_weapon_slot_3):
		_try_equip(2)
	elif event.is_action_pressed(InputManager.action_weapon_slot_4):
		_try_equip(3)
	elif event.is_action_pressed(InputManager.action_weapon_slot_5):
		_try_equip(4)
	elif event.is_action_pressed(InputManager.action_weapon_slot_6):
		_try_equip(5)
	elif event.is_action_pressed(InputManager.action_weapon_slot_7):
		_try_equip(6)

func _try_equip(index: int) -> void:
	if index < 0 or index >= weapon_slots.size():
		return
	var weapon := weapon_slots[index] as WeaponData
	if weapon == null:
		return
	equip_this.emit(weapon)
