extends GPUParticles3D

## Muzzle spark burst, connected to Attack.flash_muzzle. Gated by the same
## WeaponData.has_muzzle_flash toggle as the flash mesh — by design sparks and the
## muzzle flash are coupled (a weapon has both or neither). restart() re-fires the
## one-shot emitter from frame zero on each shot.

# Set by Player._enter_tree so sparks honor the equipped weapon's flash toggle.
@export var inventory: Inventory

func _on_attack_flash_muzzle() -> void:
	if inventory and inventory.equipped_weapon and not inventory.equipped_weapon.has_muzzle_flash:
		return
	restart()
