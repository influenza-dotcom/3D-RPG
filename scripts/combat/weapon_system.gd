class_name WeaponSystem
extends Node3D

@export var character: Character
@export var inventory: Inventory
@export var ammo: Ammo
@export var attack: Attack
@export var scope_in: ScopeIn
@export var camera: Camera3D

func _ready() -> void:
	if !character:
		character = get_parent()
