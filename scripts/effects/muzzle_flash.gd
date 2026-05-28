class_name MuzzleFlash
extends Node3D

@export var mesh_instance_3d: ExplosionMesh
@export var light_flash: OmniLight3D

func _do_muzzle_flash() -> void:
	mesh_instance_3d.visible = true
	light_flash.visible = true
	await get_tree().create_timer(GameSettings.weapon_general.muzzle_flash_duration).timeout
	mesh_instance_3d.visible = false
	light_flash.visible = false
