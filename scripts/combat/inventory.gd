class_name Inventory
extends Node

signal weapon_changed(_weapon: WeaponData)

@export var equipped_weapon: WeaponData

func equip(_weapon: WeaponData):
	equipped_weapon = _weapon
	weapon_changed.emit(_weapon)
