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
## What death MEANS — branched in Player._on_death_sequence_done (ML-2):
##  CHECKPOINT_RESPAWN: come back in place at the last checkpoint, the world UNTOUCHED (Dark Souls — the default).
##  RELOAD_LAST_SAVE: reload from the last autosave on disk (reverts unsaved progress; the world resets).
##  RELOAD_CHECKPOINT_FRESH: reload the current scene fresh (the world resets) but keep your in-memory profile.
enum DeathMode { CHECKPOINT_RESPAWN, RELOAD_LAST_SAVE, RELOAD_CHECKPOINT_FRESH }
@export var death_mode: DeathMode = DeathMode.CHECKPOINT_RESPAWN
## The line shown on the death card over the black hold before the respawn/reload. Designer-editable + themeable;
## set it to "" to show no card at all.
@export var death_message: String = "You were killed."
## The death card's text colour.
@export var death_message_color: Color = Color(0.85, 0.1, 0.1)
## The death card's font size (the small 396x216 viewport — keep it modest).
@export var death_message_size: int = 28
## Wall-clock seconds of the death cinematic (keel-over / drain / fade).
@export var death_sequence_time: float = 1.6
## Slow-mo target the world eases down to as you die.
@export var death_time_scale: float = 0.3
## Radians the camera rolls onto its side (~83 degrees at 1.45) — the keel-over.
@export var death_camera_roll: float = 1.45
## Seconds held on the fully-black screen before the respawn.
@export var respawn_delay: float = 1.0
## Fade-up-from-black duration on a fresh spawn / respawn -- a longer, cinematic emerge (the game-start intro
## the in-sky game title is timed to). Dial this for a snappier / slower entrance.
@export var spawn_fade_in_time: float = 2.5

@export_group("Air-dash recharge flash")
## Peak opacity (0..1) of the white flash when the air-dash recharges — the "ready again" pop.
@export var dash_flash_peak_alpha: float = 0.5
## Seconds the dash-recharge white flash takes to fade out.
@export var dash_flash_time: float = 0.18

@export_group("Kill flash (HUD)")
## Peak opacity (0..1) of the full-screen pop when YOU land a kill — the Hotline-Miami flash. Sky-independent, so it shows over the skybox too.
@export var kill_flash_peak_alpha: float = 0.45
## Seconds the kill flash takes to fade out.
@export var kill_flash_time: float = 0.22
## The full-screen kill-flash tint.
@export var kill_flash_color: Color = Color(1.0, 1.0, 1.0)

@export_group("Toasts")
## Min gap (ms) between sneak-result toasts so a multi-pellet sneak shot shows one line.
@export var sneak_toast_cooldown_ms: int = 1200
## "Sneak Attack!" toast colour — a successful off-guard hit (was the player.gd SNEAK_HIT_COLOR const).
@export var sneak_toast_color: Color = Color(0.4, 1.0, 0.45)
## Limb-cripple toast colour — e.g. "Your head is crippled!" (was the player.gd CRIPPLE_TOAST_COLOR const).
@export var cripple_toast_color: Color = Color(1.0, 0.42, 0.38)
