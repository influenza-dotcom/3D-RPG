class_name Inventory
extends Node

## Single source of truth for the equipped weapon. Holds the WeaponData resource
## and broadcasts changes; owns no ammo/visual state itself.

## Emitted whenever the equipped weapon changes. Wide fan-out — Ammo (clip swap),
## Attack (current_weapon + spread), ProjectileSpawner, GunMesh (hand mesh), and
## FlashLight (laser/range) all derive their state from this. Carries the new weapon.
signal weapon_changed(_weapon: WeaponData)

@export var equipped_weapon: WeaponData

func equip(_weapon: WeaponData):
	# Ignore re-equipping the same weapon so listeners don't re-run swap logic
	# (which would reset ammo/anim) on a no-op selection.
	if _weapon == equipped_weapon:
		return
	equipped_weapon = _weapon
	weapon_changed.emit(_weapon)
