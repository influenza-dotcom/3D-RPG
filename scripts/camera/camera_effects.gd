class_name CameraEffects
extends Camera3D

const BOB_HORIZONTAL_RATIO: float = 0.5
const BOB_MIN_SPEED: float = 0.1

@export var player: Character

var base_amt: float
var bob_amount: float = GameSettings.camera.bob_amount
var base_fov: float = GameSettings.camera.default_fov

var _time: float = 0.0
var _origin: Vector3
var _bob_offset: Vector3
var _impact_offset: Vector3
var _target_fov: float

func _ready() -> void:
	base_amt = bob_amount
	_origin = position
	base_fov = fov
	_target_fov = base_fov

func _process(delta: float) -> void:
	var recovery_t := 1.0 - exp(-GameSettings.camera.recovery_speed * delta)
	_impact_offset = _impact_offset.lerp(Vector3.ZERO, recovery_t)
	position = _origin + _bob_offset + _impact_offset

	var vertical_norm := clampf(-player.velocity.y / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)
	var rising_norm := clampf(player.velocity.y / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)
	var fall_fov := vertical_norm * GameSettings.camera.fall_fov_mult
	var rise_fov := rising_norm * GameSettings.camera.rise_fov_mult

	var move_fov := 0.0
	if player.input_dir.y < 0:
		move_fov = -player.input_dir.y * GameSettings.camera.forward_fov_mult

	_target_fov = base_fov + fall_fov - rise_fov + move_fov

	var fov_t := 1.0 - exp(-GameSettings.camera.fov_lerp_speed * delta)
	var tilt_t := 1.0 - exp(-GameSettings.camera.tilt_speed * delta)
	fov = lerpf(fov, _target_fov, fov_t)
	rotation.z = lerpf(rotation.z, -player.input_dir.x * GameSettings.camera.tilt_amount, tilt_t)


func bob(velocity: Vector3) -> void:
	var max_speed := GameSettings.player_movement.max_speed
	var speed_factor: float = player.current_speed / max_speed
	bob_amount = base_amt * speed_factor
	var speed = Vector2(velocity.x, velocity.z).length() * speed_factor
	if speed < BOB_MIN_SPEED:
		var dt := get_process_delta_time()
		var t := 1.0 - exp(-GameSettings.camera.recovery_speed * dt)
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, t)
		return
	_time += get_process_delta_time() * GameSettings.camera.bob_speed
	_bob_offset.y = sin(_time) * bob_amount * speed
	_bob_offset.x = cos(_time * BOB_HORIZONTAL_RATIO) * bob_amount * speed * BOB_HORIZONTAL_RATIO

func land(intensity: float = 1.0) -> void:
	_impact_offset.y -= GameSettings.camera.land_impact * intensity
