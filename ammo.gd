extends Node3D

var inventory
var current_weapon

var current_ammo
var max_ammo

func get_inventory():
	inventory = get_parent().get_node("Inventory")
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon

func _on_weapon_changed(_weapon: Weapon):
	current_weapon = _weapon

func set_to_max_ammo():
	current_ammo = current_weapon.max_ammo

func consume_ammo() -> bool:
	if current_ammo > 0.0:
		current_ammo -= 1.0
		return true
	else:
		return false

func reload():
	set_to_max_ammo()

func _ready() -> void:
	get_inventory()
	set_to_max_ammo()
