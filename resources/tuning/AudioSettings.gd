class_name AudioSettings
extends Resource

## Audio tuning, grouped below: landing thump, falling/fast-move wind swell, bullet/muzzle
## whiz pitch, impact pitch (incl. enemy-hit-by-HP), and the ammo-driven fire pitch.
## Consumed by player.gd, attack.gd, projectile.gd, and muzzle_whiz.gd.

@export_group("Landing")
## Impact strength (0..1, fall speed / landing_impact_divisor) below which the landing thump stays silent — a soft step-down plays nothing.
@export var land_sfx_min_impact_to_play: float = 0.08
## How many dB a SOFT landing is cut by (full subtraction at impact 0, none at impact 1) — bigger = gentler landings get quieter.
@export var land_sfx_volume_db_reduction: float = 18.0
## Random pitch wobble (±) on the landing thump so repeated landings don't sound identical — 0 = every landing same pitch.
@export var land_sfx_pitch_spread: float = 0.25

@export_group("Falling Air")
## Vertical fall speed (m/s) where the wind swell STARTS — below this the wind is silent (a normal jump barely clears it).
@export var falling_air_min_fall_speed: float = 4.0
## Vertical fall speed (m/s) where the wind reaches FULL volume — terminal-velocity roar.
@export var falling_air_max_fall_speed: float = 18.0
## Horizontal speed (m/s) where the SAME wind swell starts, so blitzing flat-out (bhop/dash/blast) rushes like a fall. Keep above base run speed (5.0) so ordinary walking stays silent. Sliding is excluded (it drives its own loop).
@export var falling_air_min_move_speed: float = 6.5
## Horizontal speed (m/s) where the speed-driven wind reaches full volume.
@export var falling_air_max_move_speed: float = 14.0
## Wind volume (dB) at the quiet end of the swell — where the rush is just becoming audible.
@export var falling_air_min_db: float = -40.0
## Wind volume (dB) at full fall/move speed — the loudest the swell gets. Keep above min_db so it swells UP with speed.
@export var falling_air_max_db: float = -6.0
## How fast the wind volume eases toward its target each frame (higher = snappier swell, lower = laggier).
@export var falling_air_fade_rate: float = 8.0
## Swell intensity (0..1) above which the wind loop is allowed to start playing — a tiny floor so it doesn't toggle on at a standstill.
@export var falling_air_audible_t: float = 0.01

@export_group("Bullet/Muzzle")
## Falloff distance (m) of the positional bullet-whiz crack — past this the whiz is inaudible. Bigger = bullets are heard from further.
@export var bullet_whiz_max_distance: float = 6.0
## Base volume (dB) of the bullet-whiz crack.
@export var bullet_whiz_volume_db: float = -2.0
## Low end of the random pitch range for the muzzle whiz so repeated shots vary — must stay below pitch_max.
@export var muzzle_whiz_pitch_min: float = 0.85
## High end of the muzzle-whiz random pitch range.
@export var muzzle_whiz_pitch_max: float = 1.2

@export_group("Impact")
## Low end of the random pitch range for generic bullet-impact sounds (each hit picks between min..max) — must stay below pitch_max.
@export var impact_pitch_min: float = 0.85
## High end of the impact-sound random pitch range.
@export var impact_pitch_max: float = 1.2
## Pitch of an enemy-hit sound at FULL HP — the bright high end. Hit pitch scales with the target's remaining HP fraction so you hear how hurt they are.
@export var enemy_hit_pitch_full_hp: float = 1.15
## Pitch of an enemy-hit sound at NEAR-DEATH HP — the deep/low end. Set below full_hp so wounded enemies sound progressively lower.
@export var enemy_hit_pitch_low_hp: float = 0.6
## Volume (dB) an NPC-fired impact one-shot plays at, so 3D distance attenuation applies (the .tscn authors the impact nodes very loud — volume_db 80 — for always-audible PLAYER feedback, which from a distant NPC reads as a flat 2D blast). The player's own shots keep the authored volume.
@export var npc_impact_volume_db: float = 0.0

@export_group("Fire Pitch")
## Fire-sound pitch with a FULL magazine — the gun's normal voice. The shot deepens as the mag empties (Cruelty Squad style).
@export var fire_pitch_full_ammo: float = 1.0
## Fire-sound pitch on the LAST round before empty — the deep/strained end. Set below full_ammo so the gun sags as it runs dry.
@export var fire_pitch_empty_ammo: float = 0.7
