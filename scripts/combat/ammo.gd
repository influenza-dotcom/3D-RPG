class_name Ammo
extends Node3D

## Per-weapon ammo clip. Tracks the equipped weapon's current rounds and, on a
## weapon swap, stashes/restores each weapon's count so switching guns does NOT
## refill them. attack.gd calls consume_ammo() per shot (gating fire on its bool
## return); the Reload Timer / reload() refill to max.

## Emitted when a reload completes (clip back to max). gun_mesh.gd listens to raise
## the gun back up after the reload dip; UI refreshes the count.
signal finished_reloading

@export var inventory: Inventory

var current_weapon: WeaponData
var current_ammo: int = 0
## Rounds consumed per shot. >1 would burn multiple rounds per trigger pull.
var ammo_cost: int = 1

## Remembers each weapon's leftover ammo across swaps (WeaponData -> int), keyed by
## the WeaponData resource instance.
var _ammo_per_weapon: Dictionary = {}

## A backgrounded (swapped-away mid-reload) reload runs this much slower than a normal one.
const BG_RELOAD_SLOWDOWN: float = 1.5
## Weapons reloading in the BACKGROUND after you swapped away mid-reload (WeaponData -> normal-speed
## seconds of reload still left). Advanced slowly in _process; on completion the weapon's banked clip
## refills, so switching back later finds it loaded.
var _bg_reloads: Dictionary = {}

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon
	set_to_max_ammo()
	set_process(false)  # only runs while a background reload is in flight (see start_background_reload)

## On swap: bank the outgoing weapon's remaining ammo, then restore the incoming
## weapon's saved count — or fill to max the first time that weapon is seen.
func _on_weapon_changed(_weapon: WeaponData):
	if current_weapon:
		_ammo_per_weapon[current_weapon] = current_ammo
	current_weapon = _weapon
	if _ammo_per_weapon.has(_weapon):
		current_ammo = _ammo_per_weapon[_weapon]
	else:
		set_to_max_ammo()

func set_to_max_ammo():
	# Startup race: an enemy add_child's its Weapon (firing Ammo._ready) a beat BEFORE it equips a
	# WeaponData, so current_weapon can still be null here. Skip — the equip fires weapon_changed a
	# moment later, which refills correctly.
	if not current_weapon:
		return
	# NOTE: melee.tres sets max_ammo to INT_MIN as an "effectively infinite" sentinel.
	# Together with consume_ammo's signed wraparound below, the melee clip never
	# empties. TODO: fragile — relies on 64-bit two's-complement overflow; a dedicated
	# is_infinite flag on WeaponData would be safer. Left as-is (no behavior change).
	current_ammo = current_weapon.max_ammo

## Returns false (and changes nothing) when the clip can't cover one shot — attack.gd
## treats false as "empty" and plays the dry-fire click instead of firing.
func consume_ammo() -> bool:
	if current_ammo - ammo_cost >= 0:
		current_ammo -= ammo_cost
		return true
	return false

func reload():
	set_to_max_ammo()
	finished_reloading.emit()

func _on_reload_timeout() -> void:
	reload()

## Begin (or replace) a BACKGROUND reload for `weapon` with `normal_seconds` of reload work left at
## normal speed. Called by Attack when you swap away mid-reload, so the outgoing gun keeps topping up
## (slower) while you fight with another.
func start_background_reload(weapon: WeaponData, normal_seconds: float) -> void:
	if weapon == null or normal_seconds <= 0.0:
		return
	_bg_reloads[weapon] = normal_seconds
	set_process(true)

func is_background_reloading(weapon: WeaponData) -> bool:
	return _bg_reloads.has(weapon)

## Drop a weapon's background reload (e.g. the player chose to foreground-reload it instead).
func cancel_background_reload(weapon: WeaponData) -> void:
	_bg_reloads.erase(weapon)

func _process(delta: float) -> void:
	if _bg_reloads.is_empty():
		set_process(false)
		return
	# Advance every backgrounded reload slowly; a finished one refills that weapon's banked clip (and
	# the live clip + UI if it happens to be the gun in hand right now).
	for weapon in _bg_reloads.keys():
		_bg_reloads[weapon] -= delta / BG_RELOAD_SLOWDOWN
		if _bg_reloads[weapon] <= 0.0:
			_bg_reloads.erase(weapon)
			_ammo_per_weapon[weapon] = weapon.max_ammo
			if weapon == current_weapon:
				current_ammo = weapon.max_ammo
				finished_reloading.emit()
