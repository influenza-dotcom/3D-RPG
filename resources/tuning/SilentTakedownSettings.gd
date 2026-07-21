class_name SilentTakedownSettings
extends Resource

## Slice 6b global tuning for the silent-takedown verb (GameSettings.takedown). A global player verb (not
## per-instance authored), so it lives as ONE GameSettings .tres like the other tuning groups. See SilentTakedown.
## Note: the verb is now an UNLOCKABLE ability earned via the Takedown Chip (resources/items/chip_takedown.tres) —
## these knobs tune it globally, but a player still can't take anyone down until they install the chip.

## Global master switch, applied ON TOP OF the per-player unlock (has_mechanic(&"silent_takedown")). On by default,
## since the verb is now gated by the chip anyway — flip off to kill the takedown for EVERYONE (note: that disables
## it even for a player who has already PAID to install the chip, so leave it on in normal play).
@export var enabled: bool = true
## Seconds the Takedown key must be HELD over an eligible target to commit (a short beat, not a tap). This is the
## BASE hold at baseline stealth — SilentTakedown scales it by the attacker's CharacterStats.takedown_time_mult()
## (higher stealth = quicker press), so the actual wind-up a player feels is hold_time * that multiplier.
@export_range(0.0, 5.0, 0.05) var hold_time: float = 0.55
## Floor (seconds) the stealth-scaled hold can never drop below, so even a maxed-stealth operator still gets a brief
## press (not a zero-length instant kill). Applied AFTER the takedown_time_mult scale: max(min_hold_time, scaled).
@export_range(0.0, 3.0, 0.05) var min_hold_time: float = 0.3
## Max reach (m) from the camera to the target — melee range; the target must be under the crosshair within this.
@export_range(0.5, 6.0, 0.1) var max_range: float = 2.2
## Rear arc (degrees, FULL width) the attacker must be within behind the target — matches DamageApplier.is_behind.
@export_range(0.0, 360.0, 5.0) var behind_arc_degrees: float = 120.0
## Require the attacker to be BEHIND the target (within behind_arc_degrees). Off = a takedown from any angle.
@export var require_behind: bool = true
## Require the player to be CROUCHED to take down. Off by default — being unseen + behind is enough.
@export var require_crouch: bool = false

@export_group("Audio")
## The wind-up SFX (e.g. the hydraulic press) played WHILE the Takedown key is held over an eligible target.
## SilentTakedown starts it when the press begins and cuts it the instant you release OR the kill commits, so the
## sound tracks the hold exactly. It loops for the whole hold (the component reconnects `finished` -> play), so a
## clip shorter than the wind-up sustains instead of going silent. Null = no takedown sound. Routed to the "sfx"
## bus so the audio-options volume slider applies.
@export var takedown_sfx: AudioStream = null
## Volume (dB) the takedown wind-up SFX plays at. 0 = the clip's authored level.
@export_range(-40.0, 12.0, 0.5) var takedown_sfx_volume_db: float = 0.0
