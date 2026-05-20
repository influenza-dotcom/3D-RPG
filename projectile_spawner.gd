extends Node3D

@export var muzzle: Marker3D
@export var player: Character

var current_weapon: Weapon

func _ready():
	var inventory = get_parent().get_node("Inventory")
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon

func _on_weapon_changed(_weapon: Weapon):
	current_weapon = _weapon

func spawn_projectile(_from: Vector3, _direction: Vector3, _visual_only: bool):
	if not current_weapon or not current_weapon.projectile_scene:
		return
	
	
	var _bullet = current_weapon.projectile_scene.instantiate()
	
	_bullet.gravity_scale = current_weapon.bullet_gravity_scale
	_direction = _direction.rotated(_direction.cross(Vector3.UP).normalized(), deg_to_rad(current_weapon.launch_angle))
	_bullet.direction = _direction
	_bullet.damage = current_weapon.damage
	_bullet.life_time = current_weapon.projectile_life_time
	_bullet.speed = current_weapon.projectile_speed
	_bullet.visual_only = _visual_only
	get_tree().root.add_child(_bullet)
	_bullet.global_position = _from
	
