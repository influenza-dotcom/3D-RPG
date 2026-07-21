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
## Speed multiplier for the default walk tier when Run is not held. Noise scales with ground speed, so walking is
## automatically quieter than running. Lower = slower + quieter; 1.0 = off.
@export var walk_speed_mult: float = 0.7

@export_group("Jump")
## Upward launch velocity (m/s) on a jump — higher = a taller jump.
@export var jump_velocity: float = 4.5
## Gravity multiplier applied only once the player is descending. 1.0 = symmetric jump arc; >1 makes falls snap down faster.
@export var fall_gravity_mult: float = 1.75
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
## dB cut applied to footstep loudness at the SLOW end (a creep near footstep_min_horizontal_speed), eased to 0
## (full authored loudness) at max_speed — so a sprint is loud and a slow sneak is quiet. Stacks on top of the
## crouch cut (PlayerCrouchSettings.quiet_footstep_db). Negative = quieter when moving slowly; 0 disables the effect.
@export var footstep_slow_volume_db: float = -8.0

@export_group("Landing")
## Divisor turning landing fall-speed into a 0..1 impact strength (speed / this, clamped) that scales camera dip, FOV kick and land SFX. Bigger = only very fast falls read as a hard landing.
@export var landing_impact_divisor: float = 20.0
## Seconds of continuous DESCENDING airtime before the player dies. 0 disables the environmental long-fall kill.
@export var max_continuous_fall_time: float = 4.0

@export_group("Stairs")
## Maximum vertical ledge height (m) the player can auto-step up while grounded. This lets brush stairs / curbs act like walkable terrain without turning every staircase into a ramp collider. 0 disables step assist.
@export var step_up_height: float = 0.6
## Extra downward snap distance (m) after a successful step-up, and the CharacterBody floor snap length while walking. Keep this at least as high as step_up_height so descending stairs stay grounded.
@export var step_down_snap: float = 0.65
## Minimum horizontal speed (m/s) before step assist runs. Prevents idle wall contacts / tiny collision recovery from lifting the player.
@export var step_min_horizontal_speed: float = 0.2

@export_group("Stamina")
## Maximum stamina points available for special movement abilities.
@export var max_stamina: float = 100.0
## Stamina restored per second while standing still on the ground.
@export var stamina_regen_idle: float = 24.0
## Stamina restored per second while moving on the ground.
@export var stamina_regen_moving: float = 12.0
## Stamina restored per second while airborne.
@export var stamina_regen_airborne: float = 8.0
## Stamina restored per second while in a special movement state that is not actively draining.
@export var stamina_regen_active: float = 4.0
## Seconds after spending stamina before natural recovery resumes.
@export var stamina_regen_delay_after_spend: float = 0.35
## Stamina drained per second while moving at the full run tier.
@export var stamina_sprint_drain: float = 18.0
## Seconds sprint stays unavailable after running drains stamina to empty.
@export var stamina_sprint_lockout: float = 3.0
## One-time stamina cost when a buffered/coyote jump actually launches.
@export var stamina_jump_cost: float = 10.0
## One-time stamina cost to fire the grappling hook, including a miss.
@export var stamina_grapple_fire_cost: float = 18.0
## Stamina drained per second while the grappling hook is attached.
@export var stamina_grapple_attached_drain: float = 10.0
## Stamina drained per second while actively wall-climbing.
@export var stamina_wall_climb_drain: float = 16.0
## One-time stamina cost for the scoped-attack air dash.
@export var stamina_air_dash_cost: float = 25.0
## One-time stamina cost when a fast crouched landing starts a slide.
@export var stamina_slide_start_cost: float = 12.0
## One-time stamina cost when a melee weapon swing actually starts.
@export var stamina_melee_attack_cost: float = 14.0
