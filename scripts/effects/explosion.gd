extends Node3D

const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")

@export var projectile: Projectile
@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0
@export var sfx: AudioStreamPlayer3D

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
