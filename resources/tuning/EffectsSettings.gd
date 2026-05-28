class_name EffectsSettings
extends Resource

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

@export_group("Explosion (visual)")
@export var explosion_light_grow_speed: float = 8.0
@export var explosion_flash_speed: float = 20.0
@export var explosion_spark_radius: float = 0.3
@export var explosion_min_flash_radius: float = 4.0
@export var explosion_flash_energy_per_radius: float = 4.0
