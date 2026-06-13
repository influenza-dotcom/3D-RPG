class_name PlayerCrouchSettings
extends Resource

## Tuning for Crouch: collision/camera height ratio when crouched, crouch-walk speed
## penalty, lerp rate in/out, ceiling clearance for the stand-up check, and the quieter
## footstep volume while crouched.

@export_group("Pose & Transition")
## Crouched height as a fraction of standing (0.6 = 60% tall) — sets both the collision capsule and camera drop. Lower = a deeper crouch.
@export var height_ratio: float = 0.6
## How fast the crouch eases in/out (units of crouch-fraction per second) — higher = a snappier duck/stand.
@export var lerp_speed: float = 14.0
@export_group("Movement")
## Move-speed multiplier while fully crouched (0.5 = half speed) — the crouch-walk penalty.
@export var speed_mult: float = 0.5
@export_group("Audio")
@export var quiet_footstep_db: float = -24.0  ## dB cut to footstep volume at FULL crouch — ~1/16 amplitude, genuinely sneaky (lerped by crouch_t)
@export_group("Stand-Up Check")
## Extra headroom (metres) the stand-up check probes for above the player — must be clear to uncrouch. Bigger = needs more clearance to stand.
@export var ceiling_clearance: float = 0.05
