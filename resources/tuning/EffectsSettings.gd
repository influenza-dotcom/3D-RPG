class_name EffectsSettings
extends Resource

## Visual-FX tuning, grouped below: decal fade/placement, dust puffs (jump/land/slide),
## the on-screen blood overlay (BloodSplatter), and explosion/muzzle-flash visuals.
## Consumed across the effects scripts, bloody_mess, the decals, and Explosion.

@export_group("Decals")
@export var decal_fade_rate: float = 0.9
@export var decal_fade_min_alpha: float = 0.01
@export var decal_normal_offset: float = 0.02
@export var decal_probe_distance: float = 0.5

@export_group("Dust")
@export var dust_jump_intensity: float = 0.7
@export var dust_land_base_intensity: float = 0.15
@export var dust_land_impact_bonus: float = 0.85
@export var dust_land_min_impact_to_spawn: float = 0.08
@export var dust_ground_probe_distance: float = 3.0
@export var dust_ground_offset: float = 0.05
@export var dust_amount_ratio_min: float = 0.1

@export_group("Blood Splatter (UI overlay)")
@export var blood_splatter_range: float = 3.5
@export var blood_splatter_fade_time: float = 1.5
@export var blood_splatter_min_blobs: float = 3.0
@export var blood_splatter_max_blobs: float = 8.0
@export var blood_splatter_min_scale: float = 0.6
@export var blood_splatter_max_scale: float = 1.8
@export var blood_splatter_base_size: float = 60.0
@export var blood_splatter_tint_r: float = 0.6
@export var blood_splatter_tint_g: float = 0.04
@export var blood_splatter_tint_b: float = 0.02

@export_group("Gore gibs")
## How many gibs a bloody-mess death bursts into, and where they spawn around the victim.
@export var gib_count: int = 6
@export var gib_spawn_offset_xz: float = 0.3
@export var gib_spawn_offset_y_min: float = 0.4
@export var gib_spawn_offset_y_max: float = 1.0
## Launch speed range (m/s) and the extra upward fling range.
@export var gib_vel_min: float = 7.0
@export var gib_vel_max: float = 14.0
@export var gib_up_bias_min: float = 0.8
@export var gib_up_bias_max: float = 2.2
## Max random tumble (rad/s per axis).
@export var gib_angular_range: float = 18.0
## Shots it takes to pop a gib.
@export var gib_hp_min: int = 1
@export var gib_hp_max: int = 2
## World cap on live gibs (oldest reclaimed first), how long one lingers, and its fade-out.
@export var gib_max_active: int = 24
@export var gib_lifetime: float = 12.0
@export var gib_fade_time: float = 1.0

@export_group("Blood drops (world)")
## Cone scatter of wound droplets and their speed range (m/s).
@export var blood_drop_scatter: float = 1.8
@export var blood_drop_vel_min: float = 3.0
@export var blood_drop_vel_max: float = 9.0

@export_group("Explosion (visual)")
@export var explosion_light_grow_speed: float = 8.0
@export var explosion_flash_speed: float = 20.0
@export var explosion_spark_radius: float = 0.3
@export var explosion_min_flash_radius: float = 4.0
@export var explosion_flash_energy_per_radius: float = 4.0
