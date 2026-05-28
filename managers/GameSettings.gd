extends Node

# GameSettings — central registry for tunable gameplay resources.
#
# Phase 1: declares the property slots only. Phase 2 will create the actual
# .tres files in res://resources/tuning/ and wire the preloads below.
#
# OLD CONSTANT -> NEW PROPERTY (mappings for the Phase 3 refactor):
#
#   PlayerMovementSettings:
#     PLAYER_MAX_SPEED              -> player_movement.max_speed
#     PLAYER_JUMP_VELOCITY          -> player_movement.jump_velocity
#     COYOTE_TIME                   -> player_movement.coyote_time
#     JUMP_BUFFER_TIME              -> player_movement.jump_buffer_time
#     PLAYER_MOVE_SMOOTHING_RATIO   -> player_movement.smoothing
#     PLAYER_LAND_IMPACT_DIVISOR    -> player_movement.landing_impact_divisor
#     PLAYER_BACKWARD_SPEED_MULT    -> player_movement.backward_mult
#     PLAYER_STRAFE_SPEED_MULT      -> player_movement.strafe_mult
#     PLAYER_FOOTSTEP_BASE_INTERVAL -> player_movement.footstep_interval
#
#   PlayerCrouchSettings:
#     CROUCH_HEIGHT_RATIO           -> player_crouch.height_ratio
#     CROUCH_SPEED_MULT             -> player_crouch.speed_mult
#     CROUCH_LERP_SPEED             -> player_crouch.lerp_speed
#     CROUCH_CEILING_CLEARANCE      -> player_crouch.ceiling_clearance
#     CROUCH_FOOTSTEP_QUIET_DB      -> player_crouch.quiet_footstep_db
#
#   BunnyhopSettings:
#     BHOP_BOOST_PER_HOP            -> bunnyhop.boost
#     BHOP_MAX_SPEED                -> bunnyhop.max_speed
#     BHOP_LAND_WINDOW              -> bunnyhop.land_window
#     BHOP_INPUT_WINDOW             -> bunnyhop.input_window
#     SENS_REDUCTION_THRESHOLD      -> bunnyhop.sens_reduction_threshold
#     SENS_MIN_MULTIPLIER           -> bunnyhop.sens_min_multiplier
#
#   CameraSettings:
#     CAMERA_DEFAULT_FOV            -> camera.default_fov
#     CAMERA_SCOPED_FOV             -> camera.scoped_fov
#     CAMERA_BOB_AMOUNT             -> camera.bob_amount
#     CAMERA_TILT_AMOUNT            -> camera.tilt_amount
#     CAMERA_LAND_IMPACT            -> camera.land_impact
#     CAMERA_RECOVERY_SPEED         -> camera.recovery_speed
#     CAMERA_SCOPE_ZOOM_SPEED       -> camera.scope_zoom_speed
#     CAMERA_PITCH_LIMIT_DEG        -> camera.pitch_max_deg
#     CAMERA_PITCH_LIMIT_HOLDING_DEG-> camera.pitch_max_holding_deg
#     CAMERA_PITCH_SOFT_RAMP_DEG    -> camera.pitch_soft_ramp_deg
#     MOUSE_SENSITIVITY             -> camera.mouse_sensitivity
#
#   ScreenShakeSettings:  (note: explosion-shake values folded in)
#     SCREEN_SHAKE_DECAY            -> screen_shake.decay_rate
#     SCREEN_SHAKE_AMOUNT_MULT      -> screen_shake.intensity_multiplier
#     DEATH_SHAKE_RANGE             -> screen_shake.death_shake_range
#     DEATH_SHAKE_AMOUNT            -> screen_shake.death_shake_amount
#     EXPLOSION_MAX_TRAUMA          -> screen_shake.explosion_max_trauma
#
#   WeaponGeneralSettings:
#     SWAP_TIME                     -> weapon_general.swap_time
#     MUZZLE_FLASH_DURATION         -> weapon_general.muzzle_flash_duration
#     SCOPE_SPREAD_DIVISOR          -> weapon_general.scope_spread_divisor
#     BULLET_TIME_SCALE             -> weapon_general.bullet_time_scale
#     BULLET_TIME_DURATION          -> weapon_general.bullet_time_duration
#     BULLET_TIME_LERP_SPEED        -> weapon_general.bullet_time_lerp_speed
#     SCOPE_SPEED_MULT              -> weapon_general.scope_speed_mult
#
#   EffectsSettings:
#     DECAL_FADE_RATE/_MIN_ALPHA    -> effects.decal_fade_rate / decal_fade_min_alpha
#     DECAL_NORMAL_OFFSET           -> effects.decal_normal_offset
#     DUST_*                        -> effects.dust_*
#     BLOOD_SPLATTER_*              -> effects.blood_splatter_*
#     EXPLOSION_SPARK_RADIUS        -> effects.spark_radius
#     EXPLOSION_FLASH_*             -> effects.flash_*
#
#   AudioSettings:
#     PLAYER_FOOTSTEP_*             -> audio.footstep_*
#     LAND_SFX_*                    -> audio.land_sfx_*
#     FALLING_AIR_*                 -> audio.falling_air_*
#     BULLET_WHIZ_*                 -> audio.bullet_whiz_*
#     MUZZLE_WHIZ_*                 -> audio.muzzle_whiz_*
#
#   PhysicsDamageSettings:
#     EXPLOSION_DAMAGE              -> physics_damage.explosion_damage
#     EXPLOSION_FLASH_ENERGY_PER_RADIUS -> physics_damage.explosion_flash_energy
#     BLAST_GRACE_TIMER / DECAY_RATE / MIN_MAGNITUDE -> physics_damage.blast_*
#     INTERACTABLE_*                -> physics_damage.interactable_*
#     PICKUP_*                      -> physics_damage.pickup_*
#     BULLET_INTERACTABLE_KNOCKBACK -> physics_damage.bullet_interactable_knockback

# Runtime-mutable global flag (not in a resource because tests toggle it).
var allow_timescale_changes: bool = true

# Resources are preload()-ed at script load time so that they're available
# as soon as the autoload class is loaded — BEFORE any scene's @implicit_new
# field initializers run. Loading these in _ready would be too late: scripts
# like player.gd evaluate `var x = GameSettings.foo.bar` during construction.
var player_movement: PlayerMovementSettings = preload("res://resources/tuning/PlayerMovementSettings.tres")
var player_crouch: PlayerCrouchSettings = preload("res://resources/tuning/PlayerCrouchSettings.tres")
var bunnyhop: BunnyhopSettings = preload("res://resources/tuning/BunnyhopSettings.tres")
var camera: CameraSettings = preload("res://resources/tuning/CameraSettings.tres")
var screen_shake: ScreenShakeSettings = preload("res://resources/tuning/ScreenShakeSettings.tres")
var weapon_general: WeaponGeneralSettings = preload("res://resources/tuning/WeaponGeneralSettings.tres")
var effects: EffectsSettings = preload("res://resources/tuning/EffectsSettings.tres")
var audio: AudioSettings = preload("res://resources/tuning/AudioSettings.tres")
var physics_damage: PhysicsDamageSettings = preload("res://resources/tuning/PhysicsDamageSettings.tres")
