class_name SwapWeapons
extends Node3D

signal equip_this(_weapon: WeaponData)

const ROCK_WEAPON = preload("uid://bu7caixpr0wo")
const PISTOL = preload("uid://1hb6seg5fr6s")
const SHOTGUN = preload("uid://cg011ft8wdtgl")
const SMG = preload("uid://gd1r78rei6wv")
const MELEE = preload("uid://ddqnc1majlp2r")

var weapon_slots: Array[WeaponData] = [PISTOL, ROCK_WEAPON, SHOTGUN, SMG, MELEE]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Weapon Slot 1"):
		equip_this.emit(weapon_slots[0])
	if event.is_action_pressed("Weapon Slot 2"):
		equip_this.emit(weapon_slots[1])
	if event.is_action_pressed("Weapon Slot 3"):
		equip_this.emit(weapon_slots[2])
	if event.is_action_pressed("Weapon Slot 4"):
		equip_this.emit(weapon_slots[3])
	if event.is_action_pressed("Weapon Slot 5"):
		equip_this.emit(weapon_slots[4])
