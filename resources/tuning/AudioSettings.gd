class_name AudioSettings
extends Resource

## Audio tuning, grouped below: landing thump, falling/fast-move wind swell, bullet/muzzle
## whiz pitch, impact pitch (incl. enemy-hit-by-HP), and the ammo-driven fire pitch.
## Consumed by player.gd, attack.gd, projectile.gd, and muzzle_whiz.gd.

@export_group("Landing")
@export var land_sfx_min_impact_to_play: float = 0.08
@export var land_sfx_volume_db_reduction: float = 18.0
@export var land_sfx_pitch_spread: float = 0.25

@export_group("Falling Air")
# Vertical fall speed (m/s) range mapped onto the wind-volume swell.
@export var falling_air_min_fall_speed: float = 4.0
@export var falling_air_max_fall_speed: float = 18.0
# Horizontal speed (m/s) range that ALSO drives the same swell, so moving fast in
# general — bhop / dash / blast-launch — rushes like a fall, not just falling.
# Keep min above the base run speed (5.0) so ordinary movement stays silent.
# Sliding is excluded: it drives its own looping wind player (_slide_sfx).
@export var falling_air_min_move_speed: float = 6.5
@export var falling_air_max_move_speed: float = 14.0
@export var falling_air_min_db: float = -40.0
@export var falling_air_max_db: float = -6.0
@export var falling_air_fade_rate: float = 8.0
@export var falling_air_audible_t: float = 0.01

@export_group("Bullet/Muzzle")
@export var bullet_whiz_max_distance: float = 6.0
@export var bullet_whiz_volume_db: float = -2.0
@export var muzzle_whiz_pitch_min: float = 0.85
@export var muzzle_whiz_pitch_max: float = 1.2

@export_group("Impact")
@export var impact_pitch_min: float = 0.85
@export var impact_pitch_max: float = 1.2
# Enemy-hit pitch scales with the target's remaining HP fraction: full HP plays
# at the high end, near-death plays deep/low — audible feedback on enemy health.
@export var enemy_hit_pitch_full_hp: float = 1.15
@export var enemy_hit_pitch_low_hp: float = 0.6

@export_group("Fire Pitch")
# The gun's fire sound deepens as the magazine empties (Cruelty Squad style):
# a full mag fires at full pitch, near-empty fires deep/low.
@export var fire_pitch_full_ammo: float = 1.0
@export var fire_pitch_empty_ammo: float = 0.7
