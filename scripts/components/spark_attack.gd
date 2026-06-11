class_name SparkAttack
extends GPUParticles3D

## Muzzle spark burst, fired from Attack.flash_muzzle. Gated by the same WeaponData.has_muzzle_flash
## toggle as the flash mesh — by design sparks and the muzzle flash are coupled (a weapon has both or
## neither). restart() re-fires the one-shot emitter from frame zero on each shot.
##
## DROP-IN: instance scenes/effects/spark_attack.tscn under any muzzle and connect Attack.flash_muzzle
## to _on_attack_flash_muzzle. Give it the wielder's weapon source for the per-weapon gate — EITHER the
## `inventory` (the player's gun rig sets it in GunMesh.setup) OR the firing `attack` (the NPC's
## in-hand gun sets it in _build_muzzle_fx). With neither set it just always sparks.

@export var inventory: Inventory
var attack: Attack = null

func _on_attack_flash_muzzle() -> void:
	var wd: WeaponData = null
	if inventory != null:
		wd = inventory.equipped_weapon
	elif attack != null:
		wd = attack.current_weapon
	if wd != null and not wd.has_muzzle_flash:
		return
	restart()
