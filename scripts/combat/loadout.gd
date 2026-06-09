class_name Loadout
extends Resource

## A player STARTING LOADOUT as data: the weapons the backpack is seeded with, the spare clips per caliber,
## and the starting zorkmids. Assign one to the SwapWeapons `loadout` slot to override the hardcoded
## defaults — a difficulty / scenario kit authored as a single .tres, no code edits — or leave it null to
## keep the authored weapon_slots + the player's default clips/money. Mirrors WeaponData / NpcData.
##
## (Author the .tres in the editor: a typed Array[WeaponData] serialises reliably when the editor writes it.)

## The starting weapons (seeded into the backpack; index 0 = "Weapon Slot 1", etc.). Empty -> fall back to
## the SwapWeapons.weapon_slots defaults.
@export var weapons: Array[WeaponData] = []
## Spare clips the player starts with PER DISTINCT caliber (pistol + SMG share 9mm -> one batch).
@export var starting_clips_per_caliber: int = 4
## Starting zorkmids (currency for trading at merchants).
@export var money: int = 100
