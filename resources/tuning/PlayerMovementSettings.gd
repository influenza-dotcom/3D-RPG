class_name PlayerMovementSettings
extends Resource

## Core ground/air locomotion tuning consumed by player.gd and the jump-forgiveness
## nodes: speeds + directional multipliers, jump velocity, coyote/jump-buffer windows,
## accel/air smoothing, footstep cadence, and the landing-impact divisor that scales
## camera dip / FOV / land SFX.

@export var max_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.15
@export var smoothing: float = 0.135
@export var air_smoothing_divisor: float = 10.0
@export var backward_mult: float = 0.6
@export var strafe_mult: float = 0.8
@export var footstep_base_interval: float = 0.4
@export var footstep_min_horizontal_speed: float = 0.5
@export var landing_impact_divisor: float = 20.0
@export var smoothing_reference_fps: float = 60.0
