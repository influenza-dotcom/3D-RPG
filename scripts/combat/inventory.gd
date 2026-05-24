class_name Inventory
extends Node

signal weapon_changed(_weapon: Weapon)
signal reload

@export var equipped_weapon: Weapon

func equip(_weapon: Weapon):
	equipped_weapon = _weapon
	weapon_changed.emit(_weapon)
	reload.emit()

func _on_swap_weapons_equip_this(_weapon: Weapon) -> void:
	equip(_weapon)
	
