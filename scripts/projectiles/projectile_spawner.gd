class_name ProjectileSpawner
extends Node3D

const PITCH_AXIS_MIN_LENGTH_SQ: float = 0.0001

## The Inventory this watches for weapon swaps — its weapon_changed/equipped_weapon decide which weapon's
## projectile scene + stats get spawned. Wired by WeaponSystem.setup.
@export var inventory: Inventory
## Marker3D at the gun's barrel tip — the spawn origin reference for fired projectiles. Wired by
## WeaponSystem.setup, and re-pointed to the actual gun muzzle when an NPC equips a weapon.
@export var muzzle: Marker3D
## The Character that fired (the wielder) — stamped onto each bullet as its `shooter` and added as a
## collision exception so shots can't hit the firer. Wired by WeaponSystem.setup.
@export var player: Character

var current_weapon: WeaponData

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon

func _on_weapon_changed(_weapon: WeaponData) -> void:
	current_weapon = _weapon

func spawn_projectile(_from: Vector3, _direction: Vector3, _visual_only: bool, _apply_status: bool = false) -> void:
	if not current_weapon or not current_weapon.projectile_scene:
		return

	var _bullet := current_weapon.projectile_scene.instantiate()
	if _bullet == null:
		return  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
	_bullet.gravity_scale = current_weapon.bullet_gravity_scale

	var pitch_axis := _direction.cross(Vector3.UP)
	if pitch_axis.length_squared() > PITCH_AXIS_MIN_LENGTH_SQ:
		_direction = _direction.rotated(pitch_axis.normalized(), deg_to_rad(current_weapon.launch_angle))

	_bullet.direction = _direction
	_bullet.damage = current_weapon.damage
	_bullet.life_time = current_weapon.projectile_life_time
	_bullet.speed = current_weapon.projectile_speed
	_bullet.visual_only = _visual_only
	_bullet.shooter = player
	_bullet.headshot_multiplier = current_weapon.headshot_multiplier
	_bullet.sneak_attack_multiplier = current_weapon.sneak_attack_multiplier
	_bullet.backstab_multiplier = current_weapon.backstab_multiplier
	_bullet.backstab_arc_degrees = current_weapon.backstab_arc_degrees
	_bullet.overkill_penetration = current_weapon.overkill_penetration
	# Forward the ragdoll knockback/lift as the PER-PELLET share (mirrors damage_trace dividing by pellet_count),
	# so a multi-pellet projectile gun's TOTAL push matches a hitscan one and a 1-pellet gun gets the full value.
	# Without this the authored enemy_knockback/enemy_lift were silently dead for every projectile-weapon hit.
	var _pellets := maxf(float(current_weapon.pellet_count), 1.0)
	_bullet.enemy_knockback = current_weapon.enemy_knockback / _pellets
	_bullet.enemy_lift = current_weapon.enemy_lift / _pellets
	_bullet.on_hit_effect = current_weapon.on_hit_effect  # CT-3: forward the effect (the projectile carries no WeaponData)
	_bullet.apply_status = _apply_status                   # CT-3: the shot-level roll, decided once in Attack

	if _bullet.has_method("add_collision_exception_with"):
		_bullet.add_collision_exception_with(player)

	if _bullet.has_node("Explosion"):
		_bullet.get_node("Explosion").max_explosion_force = current_weapon.max_explosion_force
		_bullet.get_node("Explosion").explosion_radius = current_weapon.explosion_radius
		_bullet.get_node("Explosion").explosion_damage = current_weapon.explosion_damage  # M9: -1 forwards the global fallback

	get_tree().root.add_child(_bullet)
	_bullet.global_position = _from

	# Projectiles play their own impact SFX (the scene's AudioStreamPlayer3Ds).
	# Override them with the weapon's per-weapon sounds so projectile weapons
	# match hitscan weapons. Done after add_child so the @export node refs have
	# resolved.
	var enemy_sfx := _bullet.get("impact_enemy_hit") as AudioStreamPlayer3D
	if enemy_sfx and current_weapon.impact_enemy_sound:
		enemy_sfx.stream = current_weapon.impact_enemy_sound
	var generic_sfx := _bullet.get("impact_generic") as AudioStreamPlayer3D
	if generic_sfx and current_weapon.impact_sound:
		generic_sfx.stream = current_weapon.impact_sound
