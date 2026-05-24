class_name Inventory
extends Node

signal weapon_changed(_weapon: Weapon)

@export var equipped_weapon: Weapon

func equip(_weapon: Weapon):
	equipped_weapon = _weapon
	weapon_changed.emit(_weapon)
