extends Node3D

const PITCH_AXIS_MIN_LENGTH_SQ: float = 0.0001

@export var inventory: Inventory
@export var muzzle: Marker3D
@export var player: Character

var current_weapon: WeaponData

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon

func _on_weapon_changed(_weapon: WeaponData) -> void:
	current_weapon = _weapon

func spawn_projectile(_from: Vector3, _direction: Vector3, _visual_only: bool) -> void:
	if not current_weapon or not current_weapon.projectile_scene:
		return

	var _bullet := current_weapon.projectile_scene.instantiate()
	_bullet.gravity_scale = current_weapon.bullet_gravity_scale

	var pitch_axis := _direction.cross(Vector3.UP)
	if pitch_axis.length_squared() > PITCH_AXIS_MIN_LENGTH_SQ:
		_direction = _direction.rotated(pitch_axis.normalized(), deg_to_rad(current_weapon.launch_angle))

	_bullet.direction = _direction
	_bullet.damage = current_weapon.damage
	_bullet.life_time = current_weapon.projectile_life_time
	_bullet.speed = current_weapon.projectile_speed
	_bullet.visual_only = _visual_only
	_bullet.knockback = current_weapon.enemy_knockback

	if _bullet.has_method("add_collision_exception_with"):
		_bullet.add_collision_exception_with(player)

	if _bullet.has_node("Explosion"):
		_bullet.get_node("Explosion").max_explosion_force = current_weapon.max_explosion_force
		_bullet.get_node("Explosion").explosion_radius = current_weapon.explosion_radius

	get_tree().root.add_child(_bullet)
	_bullet.global_position = _from
