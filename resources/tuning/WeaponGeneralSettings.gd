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

@export_group("Swap & reload")
## Raise time (s) for the incoming weapon after a swap lowers the old one.
@export var swap_raise_duration: float = 0.5
## Pause (s) after running dry before the auto-reload kicks in.
@export var auto_reload_delay: float = 0.1
## Reload-key press shorter than this (s) reloads; held at least this long toggles the holster.
@export var reload_hold_threshold: float = 0.3

@export_group("Hitstop")
## Hitstop grows with damage: every this-many damage adds +1x on top of the 1x base
## (so a hit of exactly this deals 2x hitstop)...
@export var hitstop_damage_reference: float = 25.0
## ...crits multiply by this...
@export var hitstop_crit_multiplier: float = 2.0
## ...capped at this overall multiple.
@export var hitstop_max_multiplier: float = 6.0

@export_group("Tracers")
@export var tracer_thickness: float = 0.03
@export var tracer_lifetime: float = 0.1
## Distance (m) at which a tracer reads at its authored thickness (perspective compensation).
@export var tracer_reference_dist: float = 4.0
## Tracer length (m) drawn for a shot that hits nothing.
@export var visual_tracer_fallback_distance: float = 100.0
