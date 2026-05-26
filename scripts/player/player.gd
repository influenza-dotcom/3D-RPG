class_name Player
extends Character

var current_speed: float = 0.0

@export var jump_sfx: AudioStreamPlayer3D
@export var land_sfx: AudioStreamPlayer3D
@export var walking_sfx: AudioStreamPlayer3D
@export var falling_air_sfx: AudioStreamPlayer
@export var camera_effects: CameraEffects
@export var crouch: Crouch
@export var head: Node3D
@export var player_collision_shape: CollisionShape3D
@export var weapon_system: WeaponSystem
@export var screen_shake: ScreenShake
@export var muzzle: Marker3D
@export var ui: UI
@export var coyote_time: CoyoteTime
@export var jump_buffer: JumpBuffer
@export var gun_mesh: GunMesh
@export var bullet_time: BulletTime
@export var bunnyhop: Bunnyhop
@export var mouse_input: MouseInput

var footstep_interval: float = GameTuning.PLAYER_FOOTSTEP_BASE_INTERVAL
var _footstep_timer: float = 0.0

var _was_on_floor: bool = false
var input_dir: Vector2 = Vector2.ZERO

var target_speed: float = GameTuning.PLAYER_MAX_SPEED

var _walking_sfx_base_db: float
var _land_sfx_base_db: float
var _land_sfx_base_pitch: float
var _is_scoped: bool = false

func _enter_tree() -> void:
	crouch.player = self
	crouch.head = head
	crouch.collision_shape = player_collision_shape
	camera_effects.player = self
	weapon_system.character = self
	weapon_system.camera = camera_effects
	weapon_system.screen_shake = screen_shake
	weapon_system.muzzle = muzzle
	ui.player = self
	ui.ammo_count = weapon_system.ammo
	coyote_time.character = self
	gun_mesh.inventory = weapon_system.inventory
	gun_mesh.player = self
	bullet_time.character = self
	bullet_time.scope_in = weapon_system.scope_in
	bullet_time.attack = weapon_system.attack
	bunnyhop.character = self
	mouse_input.player = self

func _ready() -> void:
	super._ready()
	_walking_sfx_base_db = walking_sfx.volume_db
	_land_sfx_base_db = land_sfx.volume_db
	_land_sfx_base_pitch = land_sfx.pitch_scale
	weapon_system.scope_in.scoped_in.connect(_on_scoped_in)

func _on_scoped_in(_tf: bool) -> void:
	_is_scoped = _tf

func _physics_process(delta: float) -> void:
	coyote_time.tick(delta)
	gravity(delta)

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var bhop_engaged: bool = false
	if coyote_time.can_jump() and jump_buffer.wants_jump():
		velocity.y = GameTuning.PLAYER_JUMP_VELOCITY
		jump_sfx.play()
		spawn_dust(GameTuning.DUST_JUMP_INTENSITY)
		coyote_time.consume()
		jump_buffer.consume()
		bhop_engaged = bunnyhop.try_engage(input_dir.y < 0)

	target_speed = GameTuning.PLAYER_MAX_SPEED
	if input_dir.y > 0:
		target_speed = GameTuning.PLAYER_MAX_SPEED * GameTuning.PLAYER_BACKWARD_SPEED_MULT
	elif abs(input_dir.x) > 0 and input_dir.y == 0:
		target_speed = GameTuning.PLAYER_MAX_SPEED * GameTuning.PLAYER_STRAFE_SPEED_MULT
	target_speed = lerpf(target_speed, target_speed * GameTuning.CROUCH_SPEED_MULT, crouch.crouch_t)
	if _is_scoped:
		target_speed *= GameTuning.SCOPE_SPEED_MULT

	var ground_ratio := GameTuning.PLAYER_MOVE_SMOOTHING_RATIO
	var air_ratio := GameTuning.PLAYER_MOVE_SMOOTHING_RATIO / GameTuning.PLAYER_AIR_SMOOTHING_DIVISOR
	var fps_factor := delta * GameTuning.SMOOTHING_REFERENCE_FPS
	var t_ground := 1.0 - pow(1.0 - ground_ratio, fps_factor)
	var t_air := 1.0 - pow(1.0 - air_ratio, fps_factor)
	if is_on_floor():
		if direction:
			current_speed = lerpf(current_speed, target_speed, t_ground)
		else:
			current_speed = lerpf(current_speed, 0.0, t_ground)
		velocity.x = lerpf(velocity.x, direction.x * current_speed, t_ground)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, t_ground)
		camera_effects.bob(velocity)
	else:
		velocity.x = lerpf(velocity.x, direction.x * current_speed, t_air)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, t_air)

	if bhop_engaged:
		var bhop_speed := bunnyhop.get_target_speed()
		velocity.x = direction.x * bhop_speed
		velocity.z = direction.z * bhop_speed
		current_speed = bhop_speed

	apply_blast()

	var pre_landing_velocity := velocity.y

	apply_velocity()

	if is_on_floor() and !_was_on_floor:
		var impact := clampf(-pre_landing_velocity / GameTuning.PLAYER_LAND_IMPACT_DIVISOR, 0.0, 1.0)
		camera_effects.land(impact * (1.0 - crouch.crouch_t))
		if impact >= GameTuning.LAND_SFX_MIN_IMPACT_TO_PLAY:
			land_sfx.volume_db = _land_sfx_base_db - (1.0 - impact) * GameTuning.LAND_SFX_VOLUME_DB_REDUCTION
			land_sfx.pitch_scale = lerpf(
				_land_sfx_base_pitch + GameTuning.LAND_SFX_PITCH_SPREAD,
				_land_sfx_base_pitch - GameTuning.LAND_SFX_PITCH_SPREAD,
				impact
			)
			land_sfx.play()
		if impact >= GameTuning.DUST_LAND_MIN_IMPACT_TO_SPAWN:
			spawn_dust(GameTuning.DUST_LAND_BASE_INTENSITY + impact * GameTuning.DUST_LAND_IMPACT_BONUS)

	_was_on_floor = is_on_floor()

	_footstep_timer -= delta

	footstep_interval = GameTuning.PLAYER_FOOTSTEP_BASE_INTERVAL * (GameTuning.PLAYER_MAX_SPEED / max(target_speed, 0.01))

	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > GameTuning.PLAYER_FOOTSTEP_MIN_HORIZONTAL_SPEED and _footstep_timer <= 0.0:
		walking_sfx.volume_db = lerpf(_walking_sfx_base_db, _walking_sfx_base_db + GameTuning.CROUCH_FOOTSTEP_QUIET_DB, crouch.crouch_t)
		walking_sfx.play()
		_footstep_timer = footstep_interval

	_update_falling_air(delta)


func _update_falling_air(delta: float) -> void:
	if not falling_air_sfx:
		return
	var fall_speed: float = -velocity.y if velocity.y < 0.0 else 0.0
	var span := GameTuning.FALLING_AIR_MAX_FALL_SPEED - GameTuning.FALLING_AIR_MIN_FALL_SPEED
	var t := 0.0
	if span > 0.0:
		t = clampf((fall_speed - GameTuning.FALLING_AIR_MIN_FALL_SPEED) / span, 0.0, 1.0)
	var target_db := lerpf(GameTuning.FALLING_AIR_MIN_DB, GameTuning.FALLING_AIR_MAX_DB, t)
	if t > GameTuning.FALLING_AIR_AUDIBLE_T:
		if not falling_air_sfx.playing and falling_air_sfx.stream:
			falling_air_sfx.play()
	elif falling_air_sfx.playing and is_on_floor():
		falling_air_sfx.stop()
	var smooth := 1.0 - exp(-GameTuning.FALLING_AIR_FADE_RATE * delta)
	falling_air_sfx.volume_db = lerpf(falling_air_sfx.volume_db, target_db, smooth)


func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_y(_amt.y)

func on_nearby_death(distance: float) -> void:
	FreezeFrame.freeze(0.01, 0.1, 0.02)
	if distance <= GameTuning.BLOOD_SPLATTER_RANGE and ui and ui.blood_splatter:
		var splat_t := 1.0 - clampf(distance / GameTuning.BLOOD_SPLATTER_RANGE, 0.0, 1.0)
		ui.blood_splatter.splash(splat_t)
	if distance <= GameTuning.DEATH_SHAKE_RANGE and screen_shake:
		var shake_t := 1.0 - clampf(distance / GameTuning.DEATH_SHAKE_RANGE, 0.0, 1.0)
		screen_shake.shake(shake_t * GameTuning.DEATH_SHAKE_AMOUNT)
