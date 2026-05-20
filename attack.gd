extends Node3D

signal spawn_projectile(_from, _direction, _visual_only: bool)

@export var muzzle: Node3D

var current_weapon: Weapon

var inventory: Node3D

func get_inventory():
	inventory = get_parent().get_node("Inventory")
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon
	

func _ready() -> void:
	get_inventory()
	print("current weapon: ", current_weapon)

func _on_weapon_changed(_weapon: Weapon):
	current_weapon = _weapon

func _on_mouse_input_attack(_camera: Camera3D) -> void:
	if not current_weapon:
		return
	
	var _space_state = get_world_3d().direct_space_state
	var _center = get_viewport().get_visible_rect().size / 2.0
	var _from = _camera.project_ray_origin(_center)
	var _direction = -_camera.global_transform.basis.z
	var _to = _from + _direction * current_weapon.effective_range
	
	var _query = PhysicsRayQueryParameters3D.create(_from, _to)
	_query.exclude = [get_parent()]
	var _result = _space_state.intersect_ray(_query)
	
	var _spawn_point = muzzle.global_position if muzzle else _from
	
	if _result: 
		print("Hit: ", _result.collider.name)
		if _result.collider.has_method("take_damage"):
			_result.collider.take_damage(current_weapon.damage)
			spawn_projectile.emit(_spawn_point, _direction, true)
	else:
		spawn_projectile.emit(_spawn_point, _direction, false)
