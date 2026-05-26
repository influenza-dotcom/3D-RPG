class_name SwapWeapons
extends Node3D

signal equip_this(_weapon: WeaponData)

const ROCK_WEAPON = preload("uid://bu7caixpr0wo")
const PISTOL = preload("uid://1hb6seg5fr6s")
const SHOTGUN = preload("uid://cg011ft8wdtgl")

var weapon_slots: Array[WeaponData] = [PISTOL, ROCK_WEAPON, SHOTGUN]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Weapon Slot 1"):
		equip_this.emit(weapon_slots[0])
	if event.is_action_pressed("Weapon Slot 2"):
		equip_this.emit(weapon_slots[1])
	if event.is_action_pressed("Weapon Slot 3"):
		equip_this.emit(weapon_slots[2])
