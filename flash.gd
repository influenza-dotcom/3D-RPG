extends Node3D

@export var mesh: MeshInstance3D

func _on_enemy_damaged(_current_hp: float, _max_hp: float) -> void:
	flash()

func flash():
	pass
