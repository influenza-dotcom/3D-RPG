class_name CameraEffects
extends Node3D

const BOB_HORIZONTAL_RATIO: float = 0.5
const BOB_MIN_SPEED: float = 0.1
const TILT_AMOUNT_X: float = 0.1

@export var camera: Camera3D
@export var player: Character

var base_amt: float
var bob_amount: float = GameTuning.CAMERA_BOB_AMOUNT
var base_fov: float = GameTuning.CAMERA_DEFAULT_FOV

var _time: float = 0.0
var _origin: Vector3
var _bob_offset: Vector3
var _impact_offset: Vector3
var _target_fov: float

func _ready() -> void:
	base_amt = bob_amount
	_origin = position
	base_fov = camera.fov
	_target_fov = base_fov

func _process(delta: float) -> void:
	_impact_offset = _impact_offset.lerp(Vector3.ZERO, delta * GameTuning.CAMERA_RECOVERY_SPEED)
	camera.position = _origin + _bob_offset + _impact_offset

	var vertical_norm := clampf(-player.velocity.y / GameTuning.PLAYER_LAND_IMPACT_DIVISOR, 0.0, 1.0)
	var rising_norm := clampf(player.velocity.y / GameTuning.PLAYER_LAND_IMPACT_DIVISOR, 0.0, 1.0)
	var fall_fov := vertical_norm * GameTuning.CAMERA_FALL_FOV_MULT
	var rise_fov := rising_norm * GameTuning.CAMERA_RISE_FOV_MULT

	var move_fov := 0.0
	if player.input_dir.y < 0:
		move_fov = -player.input_dir.y * GameTuning.CAMERA_FORWARD_FOV_MULT

	_target_fov = base_fov + fall_fov - rise_fov + move_fov
	camera.fov = lerpf(camera.fov, _target_fov, delta * GameTuning.CAMERA_FOV_LERP_SPEED)
	camera.rotation.z = lerpf(camera.rotation.z, -player.input_dir.x * TILT_AMOUNT_X, delta * GameTuning.CAMERA_TILT_SPEED)


func bob(velocity: Vector3) -> void:
	var max_speed := GameTuning.PLAYER_MAX_SPEED
	bob_amount = base_amt * (player.target_speed / max_speed)
	var speed := Vector2(velocity.x, velocity.z).length() * (player.target_speed / max_speed)
	if speed < BOB_MIN_SPEED:
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, get_process_delta_time() * GameTuning.CAMERA_RECOVERY_SPEED)
		return
	_time += get_process_delta_time() * GameTuning.CAMERA_BOB_SPEED
	_bob_offset.y = sin(_time) * bob_amount * speed
	_bob_offset.x = cos(_time * BOB_HORIZONTAL_RATIO) * bob_amount * speed * BOB_HORIZONTAL_RATIO

func land(intensity: float = 1.0) -> void:
	_impact_offset.y -= GameTuning.CAMERA_LAND_IMPACT * intensity
