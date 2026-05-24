extends Node3D

@onready var mesh_instance_3d: ExplosionMesh = $"../MeshInstance3D"
@onready var light_flash: OmniLight3D = $"../LightFlash"

func _do_muzzle_flash() -> void:
	mesh_instance_3d.visible = true
	light_flash.visible = true
	await get_tree().create_timer(0.1).timeout
	mesh_instance_3d.visible = false
	light_flash.visible = false
