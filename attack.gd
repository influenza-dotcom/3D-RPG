extends Node3D

signal spawn_projectile(_from, _direction, _visual_only: bool)
signal play_animation

signal flash_muzzle

@export var muzzle: Node3D
@export var clip: Node3D

@onready var attack_audio: AudioStreamPlayer3D = $"Attack Audio"
@onready var attack: Timer = $Attack
@onready var reload: Timer = $Reload
@onready var reload_sfx: AudioStreamPlayer3D = $ReloadSFX

@onready var impact: AudioStreamPlayer3D = $Impact
@onready var impact_enemy_hit: AudioStreamPlayer3D = $ImpactEnemyHit

var current_weapon: Weapon

var inventory: Node3D

func get_inventory():
	inventory = get_parent().get_node("Inventory")
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon

func _ready() -> void:
	get_inventory()
	print("current weapon: ", current_weapon)
	await get_tree().process_frame
	base_spread = current_weapon.pellet_spread

var base_spread: float

func _on_weapon_changed(_weapon: Weapon):
	
	current_weapon = _weapon
	base_spread = _weapon.pellet_spread

func _on_mouse_input_attack(_camera: Camera3D) -> void:
	if not current_weapon:
		return
	if !attack.is_stopped() or !reload.is_stopped():
		return
	if !clip.consume_ammo():
		return
	attack.wait_time = current_weapon.attack_speed
	attack.start()
	flash_muzzle.emit()
	get_viewport().get_camera_3d().screen_shake.shake(current_weapon.pellet_count * 0.667)
	
	attack_audio.stream = current_weapon.audio
	attack_audio.play()
	
	var _space_state = get_world_3d().direct_space_state
	var _center = get_viewport().get_visible_rect().size / 2.0
	var _from = _camera.project_ray_origin(_center)
	var spawn_point = muzzle.global_position if muzzle else _from
	_from = spawn_point
	var _direction = _camera.project_ray_normal(_center)
	
		
	for i in range(current_weapon.pellet_count):
		var pellet_direction = _direction
		var spread = current_weapon.pellet_spread
		pellet_direction = pellet_direction.rotated(
			Vector3.RIGHT,
			randf_range(-spread,spread)
		)
		pellet_direction = pellet_direction.rotated(
			Vector3.UP,
			randf_range(-spread, spread)
		)
		var _to = _from + pellet_direction * current_weapon.effective_range
		var _far_point = _from + pellet_direction * 10.0
		
		var _query = PhysicsRayQueryParameters3D.create(_from, _to)
		_query.exclude = [get_parent()]
		var _result = _space_state.intersect_ray(_query)
		
		var _spawn_point = muzzle.global_position if muzzle else _from
		
		if _result: 
			print("Hit: ", _result.collider.name)
			if _result.collider.has_method("take_damage"):
				_result.collider.take_damage(current_weapon.damage)
				var _visual_direction = (_far_point - _spawn_point).normalized()
				if _result.collider is Character:
					_result.collider.explosion_velocity += pellet_direction.normalized() * current_weapon.enemy_knockback/current_weapon.pellet_count
				spawn_projectile.emit(_spawn_point, _visual_direction, true)
				impact_enemy_hit.play()
			else:
				var _visual_direction = (_far_point - _spawn_point).normalized()
				spawn_projectile.emit(_spawn_point, _visual_direction, true)
				impact.play()
			
		else:
			var _visual_direction = (_far_point - _spawn_point).normalized()
			spawn_projectile.emit(_spawn_point, _visual_direction, false)
		play_animation.emit()
		
	var knockback_dir = -_direction
	get_parent().explosion_velocity += knockback_dir * current_weapon.self_knockback
		


func _on_reload_reload() -> void:
	reload_sfx.play()
	reload.start()


func _on_scope_in_scoped_in(_tf: bool) -> void:
	print(_tf)
	print(current_weapon.pellet_spread)
	print(base_spread)
	print(base_spread / 3.0)
	
	
	current_weapon.pellet_spread = base_spread / 3.0 if _tf else base_spread
