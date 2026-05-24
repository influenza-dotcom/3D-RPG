extends Character

const MAX_SPEED = 5.0
const SPEED_LERPF_RATIO = .135

var current_speed: float = 0.0

const JUMP_VELOCITY = 4.5

@onready var jump_sfx: AudioStreamPlayer3D = $JumpSFX
@onready var land_sfx: AudioStreamPlayer3D = $LandSFX

@onready var walking_sfx: AudioStreamPlayer3D = $WalkingSFX
@export var footstep_interval: float = 0.4
var _footstep_timer: float = 0.0

@onready var camera_effects: CameraEffects = $Head/Camera3D/CameraEffects

var _was_on_floor: bool = false
var input_dir : Vector2 = Vector2.ZERO

var target_speed = MAX_SPEED

func _physics_process(delta: float) -> void:
	gravity(delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		jump_sfx.play()

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	target_speed = MAX_SPEED
	if input_dir.y > 0:  # moving backward
		target_speed = MAX_SPEED * 0.6
	elif abs(input_dir.x) > 0 and input_dir.y == 0:  # moving sideways only
		target_speed = MAX_SPEED * 0.8
	
	var t_ground = 1.0 - pow(1.0 - SPEED_LERPF_RATIO, delta * 60.0)
	var t_air = 1.0 - pow(1.0 - SPEED_LERPF_RATIO / 10.0, delta * 60.0)
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
	
	var pre_landing_velocity = velocity.y
	
	apply_velocity()
	
	if is_on_floor() and !_was_on_floor:
		var impact = clamp(-pre_landing_velocity / 20.0, 0.0, 1.0)
		camera_effects.land(impact)
		land_sfx.play()
	
	_was_on_floor = is_on_floor()
	
	_footstep_timer -= delta
	
	footstep_interval = .4 * (MAX_SPEED/target_speed)
	
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5 and _footstep_timer <= 0.0:
		walking_sfx.play()
		_footstep_timer = footstep_interval
	
	

func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_y(_amt.y)
