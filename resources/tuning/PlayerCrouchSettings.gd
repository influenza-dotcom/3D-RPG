class_name PlayerCrouchSettings
extends Resource

## Tuning for Crouch: collision/camera height ratio when crouched, crouch-walk speed
## penalty, lerp rate in/out, ceiling clearance for the stand-up check, and the quieter
## footstep volume while crouched.

@export var height_ratio: float = 0.6
@export var lerp_speed: float = 14.0
@export var speed_mult: float = 0.5
@export var quiet_footstep_db: float = -12.0
@export var ceiling_clearance: float = 0.05
