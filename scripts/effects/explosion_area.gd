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
@export var deals_damage: bool = true

# Bias the radial push toward straight UP for characters — 0 = no change,
# 1 = pure vertical pop. Gives the "juggle" feel without flinging horizontally.
@export_range(0.0, 1.0) var upward_bias: float = 0.0

func _ready() -> void:
	mesh_instance.mesh = mesh_instance.mesh.duplicate()
	collision_shape.shape = collision_shape.shape.duplicate()
	(mesh_instance.mesh as SphereMesh).radius = explosion_radius
	(mesh_instance.mesh as SphereMesh).height = explosion_radius * 2.0
	(collision_shape.shape as SphereShape3D).radius = explosion_radius
	if screen_shake_collision_shape:
		screen_shake_collision_shape.shape = screen_shake_collision_shape.shape.duplicate()
		var shake_radius := maxf(explosion_radius * 2.0, GameSettings.screen_shake.explosion_min_shake_radius)
		(screen_shake_collision_shape.shape as SphereShape3D).radius = shake_radius
	mesh_instance.speed_to_scale = speed_to_scale
	if omni_light_3d:
		var flash_radius := maxf(explosion_radius * 1.0, 0)
		omni_light_3d.omni_range = flash_radius
		omni_light_3d.light_energy = flash_radius * GameSettings.effects.explosion_flash_energy_per_radius

func _on_body_entered(body: Node3D) -> void:
	var distance_to_blast := body.global_position.distance_to(global_position)
	if distance_to_blast > explosion_radius:
		return

	var force_multiplier := 1.0 - (distance_to_blast / explosion_radius)
	var applied_force := max_explosion_force * force_multiplier
	var push_direction := global_position.direction_to(body.global_position).normalized()

	if deals_damage and body.has_method("take_damage"):
		body.take_damage(GameSettings.physics_damage.explosion_damage)

	if body is Character and body is not Enemy:
		var biased_dir := push_direction.lerp(Vector3.UP, upward_bias).normalized()
		body.explosion_velocity += biased_dir * applied_force
	elif body is Enemy:
		var biased_dir := push_direction.lerp(Vector3.UP, upward_bias).normalized()
		body.explosion_velocity += biased_dir * applied_force * 2
	elif body is RigidBody3D:
		var rb := body as RigidBody3D
		if rb.freeze:
			return
		rb.apply_impulse(push_direction * applied_force, Vector3.ZERO)

func _on_timer_timeout() -> void:
	queue_free()
