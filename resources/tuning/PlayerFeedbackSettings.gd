class_name PlayerFeedbackSettings
extends Resource

## The player's HIT/DEATH/SPAWN feel — every feedback number on one inspector page
## (resources/tuning/PlayerFeedbackSettings.tres), read as GameSettings.player_feedback.<field>.
## These were consts scattered across player.gd / player_hud.gd / character.gd; now a designer
## tunes the whole "getting rocked -> keeling over -> fading back in" arc without touching code.

@export_group("Hurt (getting rocked)")
## time_scale at the hit's slow-mo dip (lower = more brutal).
@export var hurt_freeze_scale: float = 0.15
## Real-time hold at the dip before easing back.
@export var hurt_freeze_hold: float = 0.12
## Real-time ease back to normal (slow-mo + muffle + screen drain recover in lockstep).
@export var hurt_recovery: float = 0.55
## Master-bus low-pass cutoff (Hz) at full hurt — lower = more muffled.
@export var hurt_lpf_cutoff: float = 350.0
## Cutoff when clear (effectively no filtering).
@export var hurt_lpf_clear: float = 20500.0
## Screen-shake punch the instant you're hit.
@export var hurt_shake: float = 0.4

@export_group("Hurt flash (HUD)")
## Peak opacity (0..1) of the full-screen red flash the instant the player takes damage — bigger = a more blinding hit.
@export var hurt_flash_peak_alpha: float = 0.4
## Seconds the damage red-flash takes to fade out.
@export var hurt_flash_time: float = 0.32
## The full-screen damage flash tint.
@export var hurt_flash_color: Color = Color(0.85, 0.0, 0.0)

@export_group("Damage thud")
## Min gap (ms) between damage thuds so a pellet burst plays ONE low body-blow, not a drumroll.
@export var damage_thud_cooldown_ms: int = 250
## How loud the thud sits under the hit.
@export var damage_thud_volume_db: float = -4.0

@export_group("Death & spawn")
## Wall-clock seconds of the death cinematic (keel-over / drain / fade).
@export var death_sequence_time: float = 1.6
## Slow-mo target the world eases down to as you die.
@export var death_time_scale: float = 0.3
## Radians the camera rolls onto its side (~83 degrees at 1.45) — the keel-over.
@export var death_camera_roll: float = 1.45
## Seconds held on the fully-black screen before the respawn.
@export var respawn_delay: float = 1.0
## Fade-up-from-black duration on a fresh spawn / respawn.
@export var spawn_fade_in_time: float = 0.8

@export_group("Air-dash recharge flash")
## Peak opacity (0..1) of the white flash when the air-dash recharges — the "ready again" pop.
@export var dash_flash_peak_alpha: float = 0.5
## Seconds the dash-recharge white flash takes to fade out.
@export var dash_flash_time: float = 0.18

@export_group("Toasts")
## Min gap (ms) between sneak-result toasts so a multi-pellet sneak shot shows one line.
@export var sneak_toast_cooldown_ms: int = 1200
