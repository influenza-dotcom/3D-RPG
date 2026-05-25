class_name WeaponData
extends Resource

@export var effective_range: float = 20.0
@export var damage: int = 1
@export var projectile_scene: PackedScene
@export var hand_mesh: Mesh
@export var projectile_life_time: float = 10.0
@export var projectile_speed: float = 80.0 

@export var max_ammo: int = 10

@export var bullet_gravity_scale: float = 0.1
@export var launch_angle: float = 0.0 

@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0

@export var pellet_count: int = 1
@export var pellet_spread: float = .1

@export var audio: AudioStream

@export var attack_speed: float = 0.1 
@export var reload_time: float = 1.5 

@export var self_knockback: float = 0.0
@export var enemy_knockback: float = 5.0
