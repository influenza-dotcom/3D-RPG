class_name EffectsSettings
extends Resource

## Visual-FX tuning, grouped below: decal fade/placement, dust puffs (jump/land/slide),
## the on-screen blood overlay (BloodSplatter), and explosion/muzzle-flash visuals.
## Consumed across the effects scripts, bloody_mess, the decals, and Explosion.

@export_group("Decals")
## How fast a bullet-hole / blood decal fades its alpha toward 0 each frame (higher = decals vanish sooner).
@export var decal_fade_rate: float = 0.9
## Alpha at which a fading decal is removed from the world — the cleanup threshold (lower = it lingers fainter for longer).
@export var decal_fade_min_alpha: float = 0.01
## How far (metres) a decal is pushed off the hit surface along its normal so it doesn't z-fight the wall.
@export var decal_normal_offset: float = 0.02
## How far (metres) the raycast looks for a surface to stick a decal onto at the impact point. Bigger = decals attach across wider gaps.
@export var decal_probe_distance: float = 0.5

@export_group("Dust")
## Size/density (0..1) of the dust puff kicked up on a jump. Higher = a bigger jump cloud.
@export var dust_jump_intensity: float = 0.7
## Baseline dust puff size on ANY landing, before the impact bonus — the floor of a landing cloud.
@export var dust_land_base_intensity: float = 0.15
## Extra dust scaled by landing impact strength (added on top of the base) — bigger = harder landings throw much more dust.
@export var dust_land_impact_bonus: float = 0.85
## Landing impact strength (0..1) below which NO landing dust spawns — soft step-downs stay clean.
@export var dust_land_min_impact_to_spawn: float = 0.08
## How far down (metres) to raycast for the ground to spawn dust on. Bigger = dust still finds the floor from higher up.
@export var dust_ground_probe_distance: float = 3.0
## How far above the found ground (metres) the dust spawns so it sits on the surface, not buried in it.
@export var dust_ground_offset: float = 0.05
## Floor on a dust burst's particle-emission ratio so even a tiny puff shows some particles — clamps intensity from below.
@export var dust_amount_ratio_min: float = 0.1

@export_group("Blood Splatter (UI overlay)")
## How close (metres) a death must be to splash blood on the player's SCREEN overlay; closer kills splash harder. Bigger = gorier from further away.
@export var blood_splatter_range: float = 3.5
## Seconds each screen-overlay blood blob takes to fade out.
@export var blood_splatter_fade_time: float = 1.5
## Fewest blobs a faint (distant) splatter draws — the low end, used at intensity 0.
@export var blood_splatter_min_blobs: float = 3.0
## Most blobs a point-blank splatter draws — the high end, used at intensity 1. Keep above min_blobs.
@export var blood_splatter_max_blobs: float = 8.0
## Smallest random size multiplier a blob can roll — the low end of per-blob scale variety.
@export var blood_splatter_min_scale: float = 0.6
## Largest random size multiplier a blob can roll — the high end of per-blob scale variety.
@export var blood_splatter_max_scale: float = 1.8
## Base blob size (pixels, before the random scale) for the screen overlay — the overall splatter footprint.
@export var blood_splatter_base_size: float = 60.0
## Red channel (0..1) of the screen-overlay blood tint.
@export var blood_splatter_tint_r: float = 0.6
## Green channel (0..1) of the blood tint — small, keeps it dark.
@export var blood_splatter_tint_g: float = 0.04
## Blue channel (0..1) of the blood tint — small, keeps it dark/red.
@export var blood_splatter_tint_b: float = 0.02

@export_group("Gore gibs")
## How many gibs a bloody-mess death bursts into. More = a gorier explosion (and more physics bodies).
@export var gib_count: int = 6
## Horizontal random scatter (metres) of gib spawn points around the victim.
@export var gib_spawn_offset_xz: float = 0.3
## Lowest a gib can spawn above the victim's origin (metres) — the bottom of the spawn-height spread.
@export var gib_spawn_offset_y_min: float = 0.4
## Highest a gib can spawn above the victim's origin (metres) — the top of the spawn-height spread.
@export var gib_spawn_offset_y_max: float = 1.0
## Slowest a gib launches (m/s) — the low end of the burst speed range.
@export var gib_vel_min: float = 7.0
## Fastest a gib launches (m/s) — the high end of the burst speed range. Keep above vel_min.
@export var gib_vel_max: float = 14.0
## Least extra upward fling (m/s) added to a gib so they pop UP, not just outward — low end of the up-bias range.
@export var gib_up_bias_min: float = 0.8
## Most extra upward fling (m/s) added to a gib — high end of the up-bias range.
@export var gib_up_bias_max: float = 2.2
## Max random tumble (rad/s per axis) spun onto each gib as it launches — bigger = wilder spinning.
@export var gib_angular_range: float = 18.0
## Fewest shots it takes to pop a gib — the low end of a gib's random HP.
@export var gib_hp_min: int = 1
## Most shots it takes to pop a gib — the high end of a gib's random HP.
@export var gib_hp_max: int = 2
## World cap on simultaneously-live gibs; spawning past it reclaims the oldest first (keeps a gory scene from tanking framerate).
@export var gib_max_active: int = 24
## Seconds a gib lingers in the world before it begins fading out.
@export var gib_lifetime: float = 12.0
## Seconds a gib takes to fade out once its lifetime expires.
@export var gib_fade_time: float = 1.0

@export_group("Death freeze")
## Seconds an enemy holds its pose — frozen in place — after the killing blow BEFORE it bursts into gore (the
## gib + ragdoll "explosion"). A short beat that makes a kill read as a punchy freeze-then-pop instead of an
## instant vanish. NPCs only (the player death is its own sequence); a per-archetype opt-out lives on
## NpcData.freeze_on_death. 0 disables it entirely (the body gores immediately, the pre-freeze behaviour).
## Suppressed in headless/tests via GameSettings.allow_timescale_changes, like the other death "juice".
@export var death_freeze_duration: float = 0.15

@export_group("Blood drops (world)")
## How many physics blood drops a bloody-mess death bursts into (spread over a few frames).
@export var blood_drop_count: int = 24
## Drops spawned per frame while the burst empties — caps the per-frame spawn spike.
@export var blood_drop_per_frame: int = 8
## How many blood drops a destroyed gib flings (the confetti-pop bleed).
@export var gib_destroy_drops: int = 3
## How wide (metres) wound droplets scatter from the hit point — bigger = a messier spray cone.
@export var blood_drop_scatter: float = 1.8
## Slowest a wound droplet flies (m/s) — the low end of the random launch speed.
@export var blood_drop_vel_min: float = 3.0
## Fastest a wound droplet flies (m/s) — the high end of the random launch speed. Keep above vel_min.
@export var blood_drop_vel_max: float = 9.0
## Seconds the blood DECAL a landed drop leaves takes to grow to full size — higher = a slower bloom-in of the splat on the surface.
@export var blood_decal_grow_time: float = 0.4
## Seconds a landed blood decal stays at full before it begins fading out — higher = blood lingers longer on the world surface.
@export var blood_decal_fadeout_delay: float = 4.0

@export_group("Explosion (visual)")
## How fast the explosion light scales up to full size (higher = a snappier flash bloom).
@export var explosion_light_grow_speed: float = 8.0
## Flicker frequency of the explosion flash mesh — how fast its brightness pulses (higher = a faster, more frantic flash).
@export var explosion_flash_speed: float = 20.0
## Radius (metres) of the small spark/paint burst used for hit sparks and paint splats — the mini-explosion size.
@export var explosion_spark_radius: float = 0.3
## Floor (metres) on the explosion flash-light radius so even a small blast lights the area noticeably.
@export var explosion_min_flash_radius: float = 4.0
## Flash-light brightness per metre of flash radius — scales the omni light's energy with blast size (bigger blast = brighter flash).
@export var explosion_flash_energy_per_radius: float = 4.0

@export_group("Sky FX")
## Seconds the on-kill sky flash snaps UP to full (StarSky.flash_kill — the Hotline-Miami whole-sky pop).
@export var sky_flash_up_time: float = 0.04
## Seconds the on-kill sky flash fades back out.
@export var sky_flash_down_time: float = 0.35
## Dim, cool-blue fixed ambient StarSky pins over the level so the bright horizon sky never washes the scene white (warmer/brighter to taste).
@export var sky_ambient_fill: Color = Color(0.05, 0.07, 0.13)

@export_group("Hit flash (per-part)")
## Additive strength the per-part hit flash drives flash_strength to at its peak (Character.flash_red / the NPC located-hit flash).
@export var hit_flash_peak_strength: float = 10.0
## Seconds the hit flash snaps UP to the peak.
@export var hit_flash_up_time: float = 0.03
## Seconds the hit flash SUSTAINS the peak, so it reads as a strong hit and not a 1-frame blip.
@export var hit_flash_hold_time: float = 0.12
## Seconds the hit flash fades back out (slower, so it lingers).
@export var hit_flash_down_time: float = 0.3

@export_group("Muzzle & Impact FX")
## World-space radius (metres) of the spray-can muzzle flash — kept tiny because it sits right at the camera (the impact-spark radius would read as screen-filling up close).
@export var muzzle_flash_radius: float = 0.06
## How far (metres) the bullet-impact spark / overkill burst is pulled back along the hit direction so it sits proud of the surface instead of inside it.
@export var hit_spark_backoff: float = 0.4
## Maps impact SPEED to the hit spark's grow-in scale (passed to the burst's speed_to_scale) — higher = a faster shot blooms a bigger spark.
@export var hit_spark_speed_to_scale: float = 32.0
## Radius (metres) of the overkill-penetration burst — bigger than the ordinary spark so a shot punching THROUGH an enemy into the next reads clearly.
@export var overkill_burst_radius: float = 0.9

@export_group("Gun Holster (view model)")
## Seconds to swing the view-model gun down (holster) / up (draw) — higher = a slower, more deliberate put-away/draw.
@export var gun_holster_animation_time: float = 0.35
## Lowered, off-screen rest OFFSET (local metres) the gun parks at while holstered — pushed down/back out of view.
@export var gun_holster_position_offset: Vector3 = Vector3(0.0, -1.4, 0.2)
## Rotation OFFSET (degrees) the gun tilts to while holstered — barrel pitched down as it's put away.
@export var gun_holster_rotation_offset: Vector3 = Vector3(-70.0, 0.0, 0.0)
