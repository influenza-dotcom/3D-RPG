class_name Explosion
extends Area3D
@onready var omni_light_3d: OmniLight3D = $OmniLight3D

@export var mesh_instance: ExplosionMesh
@export var collision_shape: CollisionShape3D
@export var screen_shake_collision_shape: CollisionShape3D
@export var timer: Timer

@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0

@export var speed_to_scale: float = 0.0

@export var allowed_shake_screen: bool = false

func _ready() -> void:
	mesh_instance.mesh = mesh_instance.mesh.duplicate()
	collision_shape.shape = collision_shape.shape.duplicate()
	(mesh_instance.mesh as SphereMesh).radius = explosion_radius
	(mesh_instance.mesh as SphereMesh).height = explosion_radius * 2.0
	(collision_shape.shape as SphereShape3D).radius = explosion_radius
	if screen_shake_collision_shape:
		screen_shake_collision_shape.shape = screen_shake_collision_shape.shape.duplicate()
		(screen_shake_collision_shape.shape as SphereShape3D).radius = explosion_radius
	mesh_instance.speed_to_scale = speed_to_scale

func _on_body_entered(body: Node3D) -> void:
	if not (body is Character):
		return
	var distance_to_blast := body.global_position.distance_to(global_position)
	if distance_to_blast > explosion_radius:
		return

	var force_multiplier := 1.0 - (distance_to_blast / explosion_radius)
	var applied_force := max_explosion_force * force_multiplier
	var push_direction := global_position.direction_to(body.global_position).normalized()

	if body.has_method("take_damage"):
		body.take_damage(GameTuning.EXPLOSION_DAMAGE)
	omni_light_3d.omni_range = explosion_radius*1.5
	body.explosion_velocity += push_direction * applied_force

func _on_timer_timeout() -> void:
	queue_free()
