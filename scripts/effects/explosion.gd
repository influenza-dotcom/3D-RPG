extends Node3D

const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")

@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0
@export var sfx: AudioStreamPlayer3D
@export var speed_to_scale: float

func _spawn_at(_last_pos: Vector3, _force: float, _radius: float) -> void:
	var explosion = EXPLOSION_AREA.instantiate()
	explosion.max_explosion_force = _force
	explosion.explosion_radius = _radius
	explosion.speed_to_scale = speed_to_scale
	get_tree().root.add_child(explosion)
	explosion.position = _last_pos

func _on_rock_projectile_queued_for_deletion(_last_pos: Vector3) -> void:
	_spawn_at(_last_pos, max_explosion_force, explosion_radius)

	sfx.reparent(get_tree().root)
	sfx.position = _last_pos
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


func _on_projectile_queued_for_deletion(_last_pos: Vector3) -> void:
	_spawn_at(_last_pos, 0.0, 0.3)
