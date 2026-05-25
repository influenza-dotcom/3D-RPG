class_name WeaponSystem
extends Node3D

@export var character: Character
@export var inventory: Inventory
@export var ammo: Ammo
@export var attack: Attack
@export var scope_in: ScopeIn
@export var projectile_spawner: ProjectileSpawner

@export var camera: Camera3D
@export var screen_shake: ScreenShake
@export var muzzle: Marker3D

func _enter_tree() -> void:
	ammo.inventory = inventory
	attack.character = character
	attack.inventory = inventory
	attack.clip = ammo
	attack.muzzle = muzzle
	attack.screen_shake = screen_shake
	scope_in.camera = camera
	projectile_spawner.inventory = inventory
	projectile_spawner.muzzle = muzzle
	projectile_spawner.player = character
