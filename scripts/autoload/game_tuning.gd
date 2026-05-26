extends Node

var allow_timescale_changes: bool = true

const PLAYER_MAX_SPEED: float = 5.0
const PLAYER_JUMP_VELOCITY: float = 4.5
const COYOTE_TIME: float = 0.12
const JUMP_BUFFER_TIME: float = 0.15
const PLAYER_MOVE_SMOOTHING_RATIO: float = 0.135
const PLAYER_AIR_SMOOTHING_DIVISOR: float = 10.0
const PLAYER_BACKWARD_SPEED_MULT: float = 0.6
const PLAYER_STRAFE_SPEED_MULT: float = 0.8
const PLAYER_FOOTSTEP_BASE_INTERVAL: float = 0.4
const PLAYER_FOOTSTEP_MIN_HORIZONTAL_SPEED: float = 0.5
const PLAYER_LAND_IMPACT_DIVISOR: float = 20.0
const SMOOTHING_REFERENCE_FPS: float = 60.0

const CROUCH_HEIGHT_RATIO: float = 0.6
const CROUCH_LERP_SPEED: float = 14.0
const CROUCH_SPEED_MULT: float = 0.5
const CROUCH_FOOTSTEP_QUIET_DB: float = -12.0
const CROUCH_CEILING_CLEARANCE: float = 0.05

const MOUSE_SENSITIVITY: float = 0.002
const CAMERA_PITCH_LIMIT_DEG: float = 89.0
const CAMERA_DEFAULT_FOV: float = 75.0
const CAMERA_SCOPED_FOV: float = 40.0
const CAMERA_SCOPE_ZOOM_SPEED: float = 8.0
const CAMERA_BOB_SPEED: float = 8.0
const CAMERA_BOB_AMOUNT: float = 0.05
const CAMERA_LAND_IMPACT: float = 0.1
const CAMERA_RECOVERY_SPEED: float = 10.0
const CAMERA_FALL_FOV_MULT: float = 60.0
const CAMERA_RISE_FOV_MULT: float = 40.0
const CAMERA_FORWARD_FOV_MULT: float = 15.0
const CAMERA_TILT_AMOUNT: float = 0.1
const CAMERA_TILT_SPEED: float = 3.0
const CAMERA_FOV_LERP_SPEED: float = 5.0

const SCREEN_SHAKE_DECAY: float = 5.0
const SCREEN_SHAKE_AMOUNT_MULT: float = 0.1
const DEATH_SHAKE_RANGE: float = 8.0
const DEATH_SHAKE_AMOUNT: float = 1.6

const SCOPE_SPREAD_DIVISOR: float = 3.0
const SCOPE_SPEED_MULT: float = 0.4
const SWAP_TIME: float = 0.4
const MUZZLE_FLASH_DURATION: float = 0.1

const BULLET_TIME_SCALE: float = 0.4
const BULLET_TIME_LERP_SPEED: float = 12.0
const BULLET_TIME_DURATION: float = 1.0

const DECAL_FADE_RATE: float = 0.9
const DECAL_FADE_MIN_ALPHA: float = 0.01
const DECAL_NORMAL_OFFSET: float = 0.02
const DECAL_PROBE_DISTANCE: float = 0.5

const EXPLOSION_DAMAGE: int = 1
const EXPLOSION_LIGHT_GROW_SPEED: float = 8.0
const EXPLOSION_FLASH_SPEED: float = 20.0
const EXPLOSION_SPARK_RADIUS: float = 0.3

const BLAST_GRACE_TIMER: float = 0.2
const BLAST_DECAY_RATE: float = 0.05
const BLAST_MIN_MAGNITUDE: float = 0.1

const ENEMY_GROUND_FRICTION: float = 8.0
const ENEMY_AIR_FRICTION: float = 1.0
const ENEMY_FRICTION_MIN_SPEED: float = 0.01

const BHOP_BOOST_PER_HOP: float = 1.2
const BHOP_MAX_SPEED: float = 12.0
const BHOP_LAND_WINDOW: float = 0.18
const BHOP_INPUT_WINDOW: float = 0.15
const SENS_REDUCTION_THRESHOLD: float = 6.5
const SENS_MIN_MULTIPLIER: float = 0.5

const DUST_JUMP_INTENSITY: float = 0.7
const DUST_LAND_BASE_INTENSITY: float = 0.15
const DUST_LAND_IMPACT_BONUS: float = 0.85
const DUST_LAND_MIN_IMPACT_TO_SPAWN: float = 0.08
const DUST_GROUND_PROBE_DISTANCE: float = 3.0
const DUST_GROUND_OFFSET: float = 0.05
const DUST_AMOUNT_RATIO_MIN: float = 0.1

const LAND_SFX_MIN_IMPACT_TO_PLAY: float = 0.08
const LAND_SFX_VOLUME_DB_REDUCTION: float = 18.0
const LAND_SFX_PITCH_SPREAD: float = 0.25

const FALLING_AIR_MIN_FALL_SPEED: float = 4.0
const FALLING_AIR_MAX_FALL_SPEED: float = 18.0
const FALLING_AIR_MIN_DB: float = -40.0
const FALLING_AIR_MAX_DB: float = -6.0
const FALLING_AIR_FADE_RATE: float = 8.0
const FALLING_AIR_AUDIBLE_T: float = 0.01

const BULLET_WHIZ_MAX_DISTANCE: float = 6.0
const BULLET_WHIZ_VOLUME_DB: float = -2.0

const MUZZLE_WHIZ_PITCH_MIN: float = 0.85
const MUZZLE_WHIZ_PITCH_MAX: float = 1.2

const BLOOD_SPLATTER_RANGE: float = 3.5
const BLOOD_SPLATTER_FADE_TIME: float = 1.5
const BLOOD_SPLATTER_MIN_BLOBS: float = 3.0
const BLOOD_SPLATTER_MAX_BLOBS: float = 8.0
const BLOOD_SPLATTER_MIN_SCALE: float = 0.6
const BLOOD_SPLATTER_MAX_SCALE: float = 1.8
const BLOOD_SPLATTER_BASE_SIZE: float = 60.0
const BLOOD_SPLATTER_TINT_R: float = 0.6
const BLOOD_SPLATTER_TINT_G: float = 0.04
const BLOOD_SPLATTER_TINT_B: float = 0.02
