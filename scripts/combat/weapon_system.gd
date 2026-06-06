class_name Weapon
extends Node3D
## Self-contained weapon component. The scene (weapon.tscn) wires its own internal
## parts (inventory, ammo, attack, scope-in, projectile spawner); the outside world
## only ever talks to THIS root: call setup() once to inject the cross-actor refs,
## then read the public properties / call the public methods below.
##
## Internal child refs are resolved from the scene's exported NodePaths at
## instantiation. Cross-actor refs (the wielder, its ADS camera and muzzle) live
## outside the component, so a host injects them via setup(). Fire feedback (shake,
## flash, FOV punch) lives on the wielder via its Character host hooks, not here.

# --- Internal parts (wired by the scene) ---
@export var inventory: Inventory
@export var ammo: Ammo
@export var attack: Attack
@export var scope_in: ScopeIn
@export var projectile_spawner: ProjectileSpawner

# --- Cross-actor refs (injected by the host via setup()) ---
var character: Character
var camera: Camera3D
var muzzle: Marker3D

## Hand the component its wielder and that wielder's ADS camera + muzzle, then fan
## those refs out to the internal parts that need them. Call once, after the component
## has entered the tree (e.g. from the host's _enter_tree).
func setup(p_character: Character, p_camera: Camera3D, p_muzzle: Marker3D) -> void:
	character = p_character
	camera = p_camera
	muzzle = p_muzzle

	ammo.inventory = inventory
	ammo.character = character  # so reloads can draw from (and gate on) the wielder's reserve backpack
	attack.character = character
	attack.inventory = inventory
	attack.clip = ammo
	attack.muzzle = muzzle
	attack.scope_in = scope_in
	scope_in.camera = camera
	scope_in.attack = attack
	projectile_spawner.inventory = inventory
	projectile_spawner.muzzle = muzzle
	projectile_spawner.player = character

	# Wire the hold-R holster toggle (from the Reload input adapter) into Attack. Harmless for an
	# AI wielder, whose Reload is process-disabled below and never emits it.
	var reload_node := get_node_or_null("Reload") as Reload
	if reload_node and attack:
		reload_node.holster_toggle.connect(attack.toggle_holster)

	# An AI wielder passes no camera. The weapon's input-driven parts (weapon swap,
	# reload, ADS) poll the GLOBAL keyboard, so without this an enemy would swap or
	# reload whenever the PLAYER presses those keys. Silence them for a camera-less
	# wielder; the enemy reloads via reload() and never swaps or scopes.
	if camera == null:
		for part in [scope_in, get_node_or_null("SwapWeapons"), get_node_or_null("Reload")]:
			if part:
				part.process_mode = Node.PROCESS_MODE_DISABLED

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

## Trigger a reload — for an AI wielder that has no reload input. No-op if the clip is
## already full or a reload/swap is mid-flight.
func reload() -> void:
	if attack:
		attack._on_reload_reload()

## Equip `weapon` through the swap path (the down/up animation + hub update) — the public entry the
## inventory equip bridge uses now that the number keys are gone. Routes through SwapWeapons so the swap
## animation plays; falls back to a direct hub equip if there's no SwapWeapons child.
func equip_weapon(weapon: WeaponData) -> void:
	if weapon == null:
		return
	var sw := get_node_or_null("SwapWeapons") as SwapWeapons
	if sw != null:
		sw.request_equip(weapon)
	elif inventory != null:
		inventory.equip(weapon)

## The wielder's authored weapon loadout (the SwapWeapons slots), or [] if there's no swap node. The
## player seeds its starting backpack from this so the inventory lists the weapons it owns.
func weapon_loadout() -> Array:
	var sw := get_node_or_null("SwapWeapons") as SwapWeapons
	return sw.weapon_slots if sw != null else []
