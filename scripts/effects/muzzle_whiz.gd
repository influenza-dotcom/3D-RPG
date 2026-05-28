extends AudioStreamPlayer3D

## Positional "bullet whiz/crack" played at the muzzle on each shot, connected to
## Attack.flash_muzzle. Prefers the equipped weapon's whiz_sound (else the
## scene-assigned stream), randomly pitched so repeated shots don't sound identical.

# Set by Player._enter_tree so we can read the equipped weapon's whiz_sound.
@export var inventory: Inventory

func _on_flash_muzzle() -> void:
	# Use the equipped weapon's custom whiz if it has one; otherwise fall back
	# to the stream assigned on this node in the scene.
	if inventory and inventory.equipped_weapon and inventory.equipped_weapon.whiz_sound:
		stream = inventory.equipped_weapon.whiz_sound
	pitch_scale = randf_range(GameSettings.audio.muzzle_whiz_pitch_min, GameSettings.audio.muzzle_whiz_pitch_max)
	play()
