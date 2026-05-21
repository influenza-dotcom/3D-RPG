class_name Weapon
extends Resource

@export var effective_range: float = 20.0
@export var damage: float = 1.0
@export var projectile_scene: PackedScene
@export var projectile_life_time: float = 10.0
@export var projectile_speed: float = 80.0 

@export var max_ammo: float = 10.0

@export var bullet_gravity_scale: float = 0.1
@export var launch_angle: float = 0.0 

@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0
