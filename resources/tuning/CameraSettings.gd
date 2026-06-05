class_name CameraSettings
extends Resource

## Tuning for the first-person camera (CameraEffects), look/pitch (Head), and ADS
## zoom (ScopeIn): look limits + sensitivity, FOV (default/scoped plus the dynamic
## fall/rise/forward kicks), head-bob, landing-dip recovery, and strafe tilt.

@export var mouse_sensitivity: float = 0.002
@export var pitch_max_deg: float = 89.0
@export var pitch_max_holding_deg: float = 30.0
@export var pitch_soft_ramp_deg: float = 25.0
## Pitch limit while wall-climbing — wider than normal so the view can crane up and over the top of the
## wall, simulating walking onto a different plane. Past 90° the look tips backward over the lip.
@export var pitch_max_climbing_deg: float = 150.0

@export var default_fov: float = 75.0
@export var scoped_fov: float = 40.0
@export var scope_zoom_speed: float = 8.0

@export var bob_speed: float = 8.0
@export var bob_amount: float = 0.015

@export var land_impact: float = 1.0
@export var recovery_speed: float = 10.0

@export var fall_fov_mult: float = 60.0
@export var rise_fov_mult: float = 40.0
@export var forward_fov_mult: float = 5.0

# Air-dash FOV punch: an instant outward spike on a scoped-attack launch / air
# dash, eased back to the default FOV by fov_punch_decay (higher = snappier).
@export var dash_fov_punch: float = 40.0
@export var fov_punch_decay: float = 7.0

@export var tilt_amount: float = 0.1
@export var tilt_speed: float = 3.0
@export var fov_lerp_speed: float = 5.0
