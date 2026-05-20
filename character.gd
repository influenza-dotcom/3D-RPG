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
