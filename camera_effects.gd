class_name CameraEffects
extends Node3D

@export var camera: Camera3D
@export var bob_speed: float = 8.0
@export var bob_amount: float = 0.05
@export var land_impact: float = 0.1
@export var recovery_speed: float = 10.0

@export var player: Character

var base_amt: float

var _time: float = 0.0
var _origin: Vector3
var _bob_offset: Vector3
var _impact_offset: Vector3

var _target_fov: float

@export var base_fov: float = 75.0

func _ready() -> void:
	base_amt = bob_amount
	_origin = position
	base_fov = camera.fov
	_target_fov = base_fov

func _process(delta: float) -> void:
	_impact_offset = _impact_offset.lerp(Vector3.ZERO, delta * recovery_speed)
	camera.position = _origin + _bob_offset + _impact_offset
	
	var fall_speed = clamp(-player.velocity.y / 20.0, 0.0, 1.0) * 60
	var rise_speed = clamp(player.velocity.y / 20.0, 0.0, 1.0) * 40
	
	var move_fov = 0.0
	if player.input_dir.y < 0:
		move_fov = -player.input_dir.y * 15.0
	
	_target_fov = base_fov + fall_speed - rise_speed + move_fov
	
	camera.fov = lerpf(camera.fov, _target_fov, delta * 5.0)
	
	camera.rotation.z = lerpf(camera.rotation.z, -player.input_dir.x * 0.1, delta * 3.0)
	

func bob(velocity: Vector3) -> void:
	bob_amount = base_amt * (player.target_speed/player.MAX_SPEED)
	var speed = Vector2(velocity.x, velocity.z).length() * (player.target_speed/player.MAX_SPEED)
	if speed < 0.1:
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, get_process_delta_time() * recovery_speed)
		return
	_time += get_process_delta_time() * bob_speed
	_bob_offset.y = sin(_time) * bob_amount * speed
	_bob_offset.x = cos(_time * 0.5) * bob_amount * speed * 0.5

func land(intensity: float = 1.0) -> void:
	_impact_offset.y -= land_impact * intensity
