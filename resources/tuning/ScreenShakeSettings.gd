class_name ScreenShakeSettings
extends Resource

## Tuning for ScreenShake (trauma decay + intensity) plus the explosion/death shake
## events: death_shake_* feed Player.on_nearby_death; kill_shake_amount feeds
## Player.on_scored_kill; explosion_* feed Explosion and its screen_shake_area trigger.

@export_group("Trauma & Intensity")
## How fast trauma bleeds off per second — higher = a hit shakes hard then settles fast (punchy); lower = a longer, mushier rumble.
@export var decay_rate: float = 5.0
## Master scale on the shake offset (trauma² * this) — the overall strength of every screen shake. 0 disables shake entirely.
@export var intensity_multiplier: float = 0.1
@export_group("Death Shake")
## How close (metres) a death must be to shake the player's screen; closer deaths shake harder.
@export var death_shake_range: float = 8.0
## Trauma added by a point-blank death (scaled down with distance) — the kick from a nearby kill.
@export var death_shake_amount: float = 1.6
@export_group("Kill Shake")
## Trauma added when YOU score a kill, at ANY distance — the punch you feel under the on-kill flash. Unlike death_shake_amount this does NOT fall off with distance, so a sniped kill lands as firmly as a point-blank one. 0 disables the kill kick without touching any other shake.
@export var kill_shake_amount: float = 0.4
@export_group("Explosion Shake")
## Trauma ceiling an explosion can add so a huge blast can't oversaturate the shake — caps the rumble.
@export var explosion_max_trauma: float = 1.6
## Floor (metres) on an explosion's screen-shake trigger radius so even a small blast shakes a sensible area.
@export var explosion_min_shake_radius: float = 5.0
## Trauma multiplier on an explosion's distance falloff — scales how hard blasts shake within their radius.
@export var explosion_shake_mult: float = 1.6
