extends Node3D

const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")

@export var projectile: Projectile
@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0
@export var sfx: AudioStreamPlayer3D
@export var speed_to_scale: float 

func _on_rock_projectile_queued_for_deletion(_last_pos: Vector3) -> void:
	var explosion = EXPLOSION_AREA.instantiate()
	explosion.max_explosion_force = max_explosion_force
	explosion.explosion_radius = explosion_radius
	get_tree().root.add_child(explosion)

	sfx.reparent(get_tree().root)
	sfx.position = _last_pos
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

	explosion.position = _last_pos


func _on_projectile_queued_for_deletion(_last_pos: Vector3) -> void:
	var explosion = EXPLOSION_AREA.instantiate()
	explosion.max_explosion_force = 0
	explosion.explosion_radius = .3
	explosion.speed_to_scale = speed_to_scale
	get_tree().root.add_child(explosion)

	explosion.position = _pos

var _pos: Vector3 = Vector3.ZERO

func _on_projectile_return_contact_point(_point: Vector3) -> void:
	_pos = _point
