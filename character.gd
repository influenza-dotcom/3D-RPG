class_name Character
extends CharacterBody3D

signal damaged(current_hp: float, max_hp: float)
signal died()

@export var max_hp: int = 10
var hp: int

func _ready():
	hp = max_hp

func take_damage(_amount: int):
	hp -= _amount
	damaged.emit(hp, max_hp)
	if hp <= 0.0:
		die()

func die():
	died.emit()
	queue_free()

func heal(_amount: int):
	hp = min(hp + _amount, max_hp)
	damaged.emit(hp, max_hp)

func gravity(delta: float):
	if !is_on_floor():
		velocity += get_gravity() * delta

func apply_velocity():
	velocity += explosion_velocity
	move_and_slide()
	velocity.y -= explosion_velocity.y/1.12
	velocity.x -= explosion_velocity.x
	velocity.z -= explosion_velocity.z


var explosion_velocity: Vector3

var _blast_timer: float = 0.0

func apply_blast():
	if explosion_velocity.length() > 0.1:
		_blast_timer = 0.2  # grace period
	
	if is_on_floor() and _blast_timer <= 0.0:
		explosion_velocity = Vector3.ZERO
		return
	
	_blast_timer -= get_physics_process_delta_time()
	explosion_velocity = explosion_velocity.lerp(Vector3.ZERO, 0.05)
	if explosion_velocity.length() < 0.1:
		explosion_velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	gravity(delta)
	apply_blast()
	apply_velocity()
	
	
