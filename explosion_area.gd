class_name Explosion
extends Area3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var timer: Timer = $Timer

@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0

var explosion_dmg : int = 1

func _ready() -> void:
	(mesh_instance.mesh as SphereMesh).radius = explosion_radius
	(mesh_instance.mesh as SphereMesh).height = explosion_radius * 2.0
	(collision_shape.shape as SphereShape3D).radius = explosion_radius

func _on_body_entered(body: Node3D) -> void:
	if body is Character:
		var distance_to_blast = body.global_position.distance_to(global_position)
		
		if distance_to_blast > explosion_radius:
			return
		
		var force_multiplier = 1.0 - (distance_to_blast / explosion_radius)
		
		var applied_force = max_explosion_force * force_multiplier
		
		var push_direction = global_position.direction_to(body.global_position).normalized()
		
		if body.has_method("take_damage"):
			body.take_damage(explosion_dmg)
		
		body.explosion_velocity += push_direction.normalized() * applied_force
	else:
		return


func _on_timer_timeout() -> void:
	queue_free()
