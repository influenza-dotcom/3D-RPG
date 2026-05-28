class_name WeaponGeneralSettings
extends Resource

## Weapon-wide tuning shared by all weapons (vs per-weapon WeaponData): swap timing,
## muzzle-flash duration, the ADS spread-tightening + move-speed penalty, and the
## bullet-time slow-mo parameters (consumed by BulletTime).

@export var swap_time: float = 0.4
@export var muzzle_flash_duration: float = 0.1
@export var scope_spread_divisor: float = 3.0
@export var scope_speed_mult: float = 0.4
@export var bullet_time_scale: float = 0.4
@export var bullet_time_lerp_speed: float = 12.0
@export var bullet_time_duration: float = 1.0
