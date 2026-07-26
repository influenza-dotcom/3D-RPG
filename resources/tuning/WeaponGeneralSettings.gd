class_name WeaponGeneralSettings
extends Resource

## Weapon-wide tuning shared by all weapons (vs per-weapon WeaponData): swap timing,
## muzzle-flash duration, the ADS spread-tightening + move-speed penalty, and the
## bullet-time slow-mo parameters (consumed by BulletTime).

@export_group("Swap & Flash")
## Seconds the holster/draw swap takes before the new weapon is ready — the weapon-switch delay. Lower = faster swaps.
@export var swap_time: float = 0.4
## Seconds the muzzle flash stays lit per shot — the flash blink length.
@export var muzzle_flash_duration: float = 0.1

@export_group("Aim Down Sights")
## How much aiming down sights tightens spread: scoped spread = base spread / this. Bigger = ADS is much more accurate.
@export var scope_spread_divisor: float = 3.0
## Move-speed multiplier while scoped (0.4 = 40% speed) — the slowdown penalty for aiming down sights.
@export var scope_speed_mult: float = 0.4
## Hitscan effective-range multiplier while scoped (1.5 = +50% reach) — ADS lets a shot connect farther than the weapon's hip-fire effective_range. 1.0 = no range gain.
@export var scope_range_multiplier: float = 1.5
## OFF (default): holding Run while aiming down sights does nothing — ADS pins you to the walk tier (on top of
## scope_speed_mult), the sprint stamina drain never engages and the sprint FOV widen never fires. Turn ON to allow
## the old run-while-scoped behaviour. Read through Player.sprint_blocked_by_scope() (the single ADS/sprint gate).
@export var allow_sprint_while_scoped: bool = false

@export_group("Bullet Time")
## Engine time scale during bullet-time (0.4 = 40% speed) — how deep the slow-mo dips. Lower = slower world.
@export var bullet_time_scale: float = 0.4
## How fast time scale eases into/out of bullet-time (higher = a snappier slow-mo transition).
@export var bullet_time_lerp_speed: float = 12.0
## Wall-clock seconds bullet-time stays active before it exhausts.
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
## Visual thickness (metres) of a bullet tracer at its reference distance — fatter = more visible streaks.
@export var tracer_thickness: float = 0.03
## Seconds a tracer streak stays on screen before it fades. Shorter = quick zips; longer = lingering trails.
@export var tracer_lifetime: float = 0.1
## Distance (m) at which a tracer reads at its authored thickness (perspective compensation).
@export var tracer_reference_dist: float = 4.0
## Tracer length (m) drawn for a shot that hits nothing.
@export var visual_tracer_fallback_distance: float = 100.0
