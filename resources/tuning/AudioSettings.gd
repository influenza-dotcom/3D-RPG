class_name AudioSettings
extends Resource

@export_group("Landing")
@export var land_sfx_min_impact_to_play: float = 0.08
@export var land_sfx_volume_db_reduction: float = 18.0
@export var land_sfx_pitch_spread: float = 0.25

@export_group("Falling Air")
@export var falling_air_min_fall_speed: float = 4.0
@export var falling_air_max_fall_speed: float = 18.0
@export var falling_air_min_db: float = -40.0
@export var falling_air_max_db: float = -6.0
@export var falling_air_fade_rate: float = 8.0
@export var falling_air_audible_t: float = 0.01

@export_group("Bullet/Muzzle")
@export var bullet_whiz_max_distance: float = 6.0
@export var bullet_whiz_volume_db: float = -2.0
@export var muzzle_whiz_pitch_min: float = 0.85
@export var muzzle_whiz_pitch_max: float = 1.2
