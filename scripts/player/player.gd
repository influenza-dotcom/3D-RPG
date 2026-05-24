extends Character

var current_speed: float = 0.0

@export var jump_sfx: AudioStreamPlayer3D
@export var land_sfx: AudioStreamPlayer3D
@export var walking_sfx: AudioStreamPlayer3D
@export var camera_effects: CameraEffects
@export var crouch: Crouch

var footstep_interval: float = GameTuning.PLAYER_FOOTSTEP_BASE_INTERVAL
var _footstep_timer: float = 0.0

var _was_on_floor: bool = false
var input_dir: Vector2 = Vector2.ZERO

var target_speed: float = GameTuning.PLAYER_MAX_SPEED

var _walking_sfx_base_db: float

func _ready() -> void:
	super._ready()
	_walking_sfx_base_db = walking_sfx.volume_db

func _physics_process(delta: float) -> void:
	gravity(delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = GameTuning.PLAYER_JUMP_VELOCITY
		jump_sfx.play()

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	target_speed = GameTuning.PLAYER_MAX_SPEED
	if input_dir.y > 0:
		target_speed = GameTuning.PLAYER_MAX_SPEED * GameTuning.PLAYER_BACKWARD_SPEED_MULT
	elif abs(input_dir.x) > 0 and input_dir.y == 0:
		target_speed = GameTuning.PLAYER_MAX_SPEED * GameTuning.PLAYER_STRAFE_SPEED_MULT
	target_speed = lerpf(target_speed, target_speed * GameTuning.CROUCH_SPEED_MULT, crouch.crouch_t)

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

	apply_blast()

	var pre_landing_velocity := velocity.y

	apply_velocity()

	if is_on_floor() and !_was_on_floor:
		var impact := clampf(-pre_landing_velocity / GameTuning.PLAYER_LAND_IMPACT_DIVISOR, 0.0, 1.0)
		camera_effects.land(impact * (1.0 - crouch.crouch_t))
		land_sfx.play()

	_was_on_floor = is_on_floor()

	_footstep_timer -= delta

	footstep_interval = GameTuning.PLAYER_FOOTSTEP_BASE_INTERVAL * (GameTuning.PLAYER_MAX_SPEED / target_speed)

	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > GameTuning.PLAYER_FOOTSTEP_MIN_HORIZONTAL_SPEED and _footstep_timer <= 0.0:
		walking_sfx.volume_db = lerpf(_walking_sfx_base_db, _walking_sfx_base_db + GameTuning.CROUCH_FOOTSTEP_QUIET_DB, crouch.crouch_t)
		walking_sfx.play()
		_footstep_timer = footstep_interval


func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_y(_amt.y)
