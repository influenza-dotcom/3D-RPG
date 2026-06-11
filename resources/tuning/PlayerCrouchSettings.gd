class_name PlayerCrouchSettings
extends Resource

## Tuning for Crouch: collision/camera height ratio when crouched, crouch-walk speed
## penalty, lerp rate in/out, ceiling clearance for the stand-up check, and the quieter
## footstep volume while crouched.

@export var height_ratio: float = 0.6
@export var lerp_speed: float = 14.0
@export var speed_mult: float = 0.5
@export var quiet_footstep_db: float = -24.0  ## dB cut to footstep volume at FULL crouch — ~1/16 amplitude, genuinely sneaky (lerped by crouch_t)
@export var ceiling_clearance: float = 0.05
