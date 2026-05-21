extends Node3D

@export var projectile: Projectile
const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")


func _on_rock_projectile_queued_for_deletion(_last_pos: Vector3) -> void:
	var explosion = EXPLOSION_AREA.instantiate()
	explosion.position = _last_pos
	get_tree().root.add_child(explosion)
