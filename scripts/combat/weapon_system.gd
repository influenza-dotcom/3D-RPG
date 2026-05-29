class_name Weapon
extends Node3D
## Self-contained weapon component. The scene (weapon.tscn) wires its own internal
## parts (inventory, ammo, attack, scope-in, projectile spawner); the outside world
## only ever talks to THIS root: call setup() once to inject the cross-actor refs,
## then read the public properties / call the public methods below.
##
## Internal child refs are resolved from the scene's exported NodePaths at
## instantiation. Cross-actor refs (the wielder, its camera, muzzle and screen
## shake) live outside the component, so a host injects them via setup().

# --- Internal parts (wired by the scene) ---
@export var inventory: Inventory
@export var ammo: Ammo
@export var attack: Attack
@export var scope_in: ScopeIn
@export var projectile_spawner: ProjectileSpawner

# --- Cross-actor refs (injected by the host via setup()) ---
var character: Character
var camera: Camera3D
var screen_shake: ScreenShake
var muzzle: Marker3D

## Hand the component its wielder and that wielder's camera / muzzle / screen shake,
## then fan those refs out to the internal parts that need them. Call once, after
## the component has entered the tree (e.g. from the host's _enter_tree).
func setup(p_character: Character, p_camera: Camera3D, p_muzzle: Marker3D, p_screen_shake: ScreenShake) -> void:
	character = p_character
	camera = p_camera
	muzzle = p_muzzle
	screen_shake = p_screen_shake

	ammo.inventory = inventory
	attack.character = character
	attack.inventory = inventory
	attack.clip = ammo
	attack.muzzle = muzzle
	attack.screen_shake = screen_shake
	attack.scope_in = scope_in
	scope_in.camera = camera
	scope_in.attack = attack
	projectile_spawner.inventory = inventory
	projectile_spawner.muzzle = muzzle
	projectile_spawner.player = character

# --- Public API (read state / query the weapon without reaching into children) ---

## The currently equipped weapon's data, or null if there's no inventory yet.
var equipped_weapon: WeaponData:
	get:
		return inventory.equipped_weapon if inventory else null

## Rounds left in the current clip (0 if the component isn't wired yet).
var current_ammo: int:
	get:
		return ammo.current_ammo if ammo else 0

## Whether the weapon is currently scoped in.
var is_scoped: bool:
	get:
		return scope_in.is_scoped if scope_in else false

## True when the weapon is free to fire (off cooldown, has ammo, etc.).
func can_fire() -> bool:
	return attack.can_fire() if attack else false

## True while a reload or weapon swap is in progress.
func is_busy() -> bool:
	return attack.is_reload_or_swap_active() if attack else false
