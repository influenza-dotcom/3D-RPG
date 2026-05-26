class_name Attack
extends Node3D

signal spawn_projectile(_from, _direction, _visual_only: bool)
signal play_animation
signal reload_started
signal swap_started
signal swap_finished
signal flash_muzzle
signal shell_particle
const VISUAL_TRACER_FALLBACK_DISTANCE: float = 100.0
const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")
const HIT_SPARK_BACKOFF: float = 0.4
const HIT_SPARK_SPEED_TO_SCALE: float = 32.0

@export var character: Character
@export var inventory: Inventory
@export var muzzle: Node3D
@export var clip: Ammo
@export var screen_shake: ScreenShake

@export var attack_audio: AudioStreamPlayer3D
@export var attack: Timer
@export var reload: Timer
@export var swap: Timer
@export var reload_sfx: AudioStreamPlayer3D
@onready var shell_impact: AudioStreamPlayer3D = $ShellImpact

@export var impact: AudioStreamPlayer3D
@export var impact_enemy_hit: AudioStreamPlayer3D

@export var empty_clip: AudioStreamPlayer3D


var current_weapon: WeaponData
var base_spread: float
var current_spread: float

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon
	base_spread = current_weapon.pellet_spread
	current_spread = base_spread

func _on_weapon_changed(_weapon: WeaponData):
	current_weapon = _weapon
	base_spread = _weapon.pellet_spread
	current_spread = base_spread

func _on_mouse_input_attack(_camera: Camera3D) -> void:
	if not current_weapon:
		return
	if !attack.is_stopped() or !reload.is_stopped() or !swap.is_stopped():
		return
	if !clip.consume_ammo():
		if Input.is_action_just_pressed("Attack"):
			empty_clip.play()
		return
	attack.wait_time = current_weapon.attack_speed
	attack.start()
	flash_muzzle.emit()
	if screen_shake:
		screen_shake.shake(current_weapon.screen_shake_amount)

	attack_audio.stream = current_weapon.audio
	attack_audio.play()
	shell_impact.play()
	shell_particle.emit()
	var _space_state := get_world_3d().direct_space_state
	var _center := get_viewport().get_visible_rect().size / 2.0
	var _ray_origin := _camera.project_ray_origin(_center)
	var _spawn_point := muzzle.global_position if muzzle else _ray_origin
	var _direction := _camera.project_ray_normal(_center)
	var _cam_basis := _camera.global_transform.basis

	for i in range(current_weapon.pellet_count):
		var pellet_direction := _direction
		var spread := current_spread
		pellet_direction = pellet_direction.rotated(
			_cam_basis.x,
			randf_range(-spread, spread)
		)
		pellet_direction = pellet_direction.rotated(
			_cam_basis.y,
			randf_range(-spread, spread)
		)
		var _to := _ray_origin + pellet_direction * current_weapon.effective_range

		var _query := PhysicsRayQueryParameters3D.create(_ray_origin, _to)
		_query.exclude = [character]
		var _result := _space_state.intersect_ray(_query)

		var _visual_target: Vector3
		if _result:
			_visual_target = _result.position
			_spawn_hit_spark(_result.position, pellet_direction)
			var collider: Object = _result.collider
			if collider.has_method("take_damage"):
				collider.take_damage(current_weapon.damage)
				if collider is Character:
					collider.explosion_velocity += pellet_direction.normalized() * current_weapon.enemy_knockback / current_weapon.pellet_count
					impact_enemy_hit.play()
				else:
					impact.play()
			else:
				impact.play()
			if collider is RigidBody3D and not (collider is Character):
				var rb := collider as RigidBody3D
				var impulse := pellet_direction.normalized() * GameTuning.BULLET_INTERACTABLE_KNOCKBACK
				rb.apply_impulse(impulse, _result.position - rb.global_position)
				if rb is Interactable:
					(rb as Interactable).on_impact(GameTuning.INTERACTABLE_IMPACT_MAX_VELOCITY)
		else:
			_visual_target = _ray_origin + pellet_direction * VISUAL_TRACER_FALLBACK_DISTANCE

		var _visual_direction := (_visual_target - _spawn_point).normalized()
		var _hit_anything: bool = _result and not _result.is_empty()
		spawn_projectile.emit(_spawn_point, _visual_direction, _hit_anything)

	play_animation.emit()

	var knockback_dir := -_direction
	character.explosion_velocity += knockback_dir * current_weapon.self_knockback


func _on_reload_reload() -> void:
	if not current_weapon:
		return
	if !reload.is_stopped() or !swap.is_stopped():
		return
	if clip.current_ammo >= current_weapon.max_ammo:
		return
	reload.wait_time = current_weapon.reload_time
	reload_sfx.play()
	reload.start()
	reload_started.emit()


func _on_swap_weapons_equip_this(_weapon: WeaponData) -> void:
	if _weapon == current_weapon:
		return
	if !swap.is_stopped() or !reload.is_stopped():
		return
	swap.wait_time = GameTuning.SWAP_TIME
	swap.start()
	swap_started.emit()
	inventory.equip(_weapon)


func _on_swap_timeout() -> void:
	swap_finished.emit()


func _on_scope_in_scoped_in(_tf: bool) -> void:
	current_spread = base_spread / GameTuning.SCOPE_SPREAD_DIVISOR if _tf else base_spread


func _spawn_hit_spark(hit_pos: Vector3, hit_dir: Vector3) -> void:
	var explosion = EXPLOSION_AREA.instantiate()
	explosion.max_explosion_force = 0.0
	explosion.explosion_radius = GameTuning.EXPLOSION_SPARK_RADIUS
	explosion.speed_to_scale = HIT_SPARK_SPEED_TO_SCALE
	explosion.deals_damage = false
	get_tree().root.add_child(explosion)
	explosion.position = hit_pos - hit_dir.normalized() * HIT_SPARK_BACKOFF
