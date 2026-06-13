class_name PlayerMovementSettings
extends Resource

## Core ground/air locomotion tuning consumed by player.gd and the jump-forgiveness nodes: speeds +
## directional multipliers, jump velocity, coyote/jump-buffer windows, accel/air smoothing, footstep
## cadence, and the landing-impact divisor that scales camera dip / FOV / land SFX.

@export_group("Speed")
## Base ground run speed (m/s) — the speed forward movement tops out at (bhop boosts stack above it).
@export var max_speed: float = 5.0
## Speed multiplier when moving BACKWARD (0.6 = 60% of run speed) — keeps backpedalling slower than advancing.
@export var backward_mult: float = 0.6
## Speed multiplier when STRAFING sideways (0.8 = 80% of run speed).
@export var strafe_mult: float = 0.8

@export_group("Jump")
## Upward launch velocity (m/s) on a jump — higher = a taller jump.
@export var jump_velocity: float = 4.5
## Grace window (s) after walking off a ledge during which you can still jump — forgiveness for late presses. 0 = must jump while grounded.
@export var coyote_time: float = 0.12
## Window (s) before landing in which a jump press is remembered and fires the instant you touch down. 0 = no buffering.
@export var jump_buffer_time: float = 0.15

@export_group("Acceleration")
## Ground move smoothing — the fraction the velocity closes toward target per reference frame. Higher = snappier starts/stops; lower = more glide.
@export var smoothing: float = 0.135
## Divisor that WEAKENS smoothing in the air (air accel = ground smoothing / this) so air control is floatier. Bigger = less air control.
@export var air_smoothing_divisor: float = 10.0
## FPS the smoothing values are tuned for; movement is rescaled to this so accel feels identical at any framerate. Don't change unless retuning all smoothing.
@export var smoothing_reference_fps: float = 60.0

@export_group("Footsteps")
## Seconds between footstep sounds at full run speed — the step cadence (faster movement shortens it). Smaller = quicker footfalls.
@export var footstep_base_interval: float = 0.4
## Horizontal speed (m/s) below which footsteps stop playing — the standing-still cutoff.
@export var footstep_min_horizontal_speed: float = 0.5

@export_group("Landing")
## Divisor turning landing fall-speed into a 0..1 impact strength (speed / this, clamped) that scales camera dip, FOV kick and land SFX. Bigger = only very fast falls read as a hard landing.
@export var landing_impact_divisor: float = 20.0
