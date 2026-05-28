class_name MuzzleFlash
extends Node3D

## Blinks the muzzle-flash mesh + point light for a fixed duration on each shot.
## Connected to Attack.flash_muzzle (emitted alongside the gunshot). Per-weapon
## opt-out via WeaponData.has_muzzle_flash (e.g. melee has none). The mesh is an
## ExplosionMesh (pulsing glow); light_flash briefly lights the surroundings.

@export var mesh_instance_3d: ExplosionMesh
@export var light_flash: OmniLight3D
# Set by Player._enter_tree so we can honor the equipped weapon's flash toggle.
@export var inventory: Inventory

func _do_muzzle_flash() -> void:
	if inventory and inventory.equipped_weapon and not inventory.equipped_weapon.has_muzzle_flash:
		return
	mesh_instance_3d.visible = true
	light_flash.visible = true
	await get_tree().create_timer(GameSettings.weapon_general.muzzle_flash_duration).timeout
	mesh_instance_3d.visible = false
	light_flash.visible = false
