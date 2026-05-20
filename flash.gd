extends Node3D

@export var mesh: MeshInstance3D

func _on_enemy_damaged(_current_hp: float, _max_hp: float) -> void:
	flash()

func flash():
	var mat = mesh.get_active_material(0)
	if not mat:
		return
	mat.albedo_color = Color.RED
	await get_tree().create_timer(0.1).timeout
	mat.albedo_color = Color.WHITE
