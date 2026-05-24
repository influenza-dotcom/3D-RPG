extends Node3D

signal finished_reloading

@export var inventory

var current_weapon: Weapon
var current_ammo: int = 0
var _ammo_per_weapon: Dictionary = {}
var ammo_cost: int = 1


func get_inventory():
	inventory = get_parent().get_node("Inventory")
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon

func _on_weapon_changed(_weapon: Weapon):
	if current_weapon:
		_ammo_per_weapon[current_weapon] = current_ammo
	current_weapon = _weapon
	if _ammo_per_weapon.has(_weapon):
		current_ammo = _ammo_per_weapon[_weapon]
	else:
		set_to_max_ammo()

func set_to_max_ammo():
	current_ammo = current_weapon.max_ammo

func consume_ammo() -> bool:
	if current_ammo-ammo_cost > 0:
		current_ammo -= ammo_cost
		return true
	return false

func reload():
	set_to_max_ammo()
	finished_reloading.emit()

func _ready() -> void:
	get_inventory()
	set_to_max_ammo()

func _on_reload_timeout() -> void:
	reload()
