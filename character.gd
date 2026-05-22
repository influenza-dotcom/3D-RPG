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
	move_and_slide()


var explosion_velocity: Vector3

func apply_blast():
	velocity += explosion_velocity
	explosion_velocity = explosion_velocity.lerp(Vector3.ZERO, .9)

func _physics_process(delta: float) -> void:
	gravity(delta)
	apply_blast()
	apply_velocity()
	
	
