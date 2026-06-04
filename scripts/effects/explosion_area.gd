class_name Explosion
extends Area3D

## One-shot radial blast. On _ready it sizes its flash mesh, push collider, screen-
## shake collider, and light from explosion_radius; on body entry it applies a
## distance-falloff push (+ optional damage); a timer self-frees it.
##
## DUAL MODE via collision_shape: present = a real explosion (physics push collider,
## full-size mesh/light). Absent = a light-only visual (e.g. a bullet hit spark) —
## the mesh/light shrink and no push collider is built. `deals_damage` gates damage.

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

## Recolour the flash + light to this (alpha > 0 = active). Used by the paint splat to match paint.
@export var tint_color: Color = Color(0, 0, 0, 0)

## Who caused this blast (the projectile's shooter), set by explosion.gd when spawned. ONLY a player
## instigator flashes the player's hitmarker — an NPC's rocket splashing another NPC must not ping it.
## Null = unknown (e.g. a cosmetic spark) and is treated as not-the-player.
var instigator: Node = null

func _ready() -> void:
	mesh_instance.mesh = mesh_instance.mesh.duplicate()
	if collision_shape:
		collision_shape.shape = collision_shape.shape.duplicate()
	else:
		pass
	if !collision_shape:
		(mesh_instance.mesh as SphereMesh).radius = explosion_radius / 4
		(mesh_instance.mesh as SphereMesh).height = explosion_radius /2
	else:
		(mesh_instance.mesh as SphereMesh).radius = explosion_radius
		(mesh_instance.mesh as SphereMesh).height = explosion_radius * 2.0
	if collision_shape:
		(collision_shape.shape as SphereShape3D).radius = explosion_radius
	else:
		pass
	if screen_shake_collision_shape:
		screen_shake_collision_shape.shape = screen_shake_collision_shape.shape.duplicate()
		var shake_radius := maxf(explosion_radius * 2.0, GameSettings.screen_shake.explosion_min_shake_radius)
		(screen_shake_collision_shape.shape as SphereShape3D).radius = shake_radius
	mesh_instance.speed_to_scale = speed_to_scale
	if omni_light_3d:
		var flash_radius := maxf(explosion_radius * 1.0, 0)
		if !collision_shape:
			flash_radius = maxf(explosion_radius / 2, 0)
		omni_light_3d.omni_range = flash_radius
		omni_light_3d.light_energy = flash_radius * GameSettings.effects.explosion_flash_energy_per_radius
	if tint_color.a > 0.0:
		if mesh_instance:
			mesh_instance.tint(tint_color)
		if omni_light_3d:
			omni_light_3d.light_color = tint_color
	_limit_monitoring_window()

## An explosion is instantaneous: it only needs to detect the bodies it overlaps for a frame
## or two (to damage / push / shake), NOT for its whole 0.2s visual lifetime. If the Area3D
## keeps monitoring that whole time, every gore drop / gib / body that spawns or drifts inside
## churns enter+exit events — and when those bodies (or this area) free mid-overlap, Jolt spams
## "_flush_events: ref_count <= 0" and the frame hitches hard on every kill. So: detect, then
## stop monitoring. The mesh + light still fade out on the Timer.
func _limit_monitoring_window() -> void:
	var visual_only := not deals_damage and max_explosion_force <= 0.0
	if not visual_only:
		# Let body_entered fire for everything we already overlap, then stop.
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	monitoring = false
	var shake := get_node_or_null("ScreenShakeArea")
	if shake is Area3D:
		(shake as Area3D).monitoring = false

## Push (and optionally damage) each body entering the blast. Force falls off
## linearly to zero at explosion_radius. Characters/enemies receive a DECAYING blast
## impulse (explosion_velocity, see Character); loose rigid bodies get a real impulse.
func _on_body_entered(body: Node3D) -> void:
	# Area is a sphere, but clamp to the exact radius so edge cases just outside the
	# intended range receive no force.
	var distance_to_blast := body.global_position.distance_to(global_position)
	if distance_to_blast > explosion_radius:
		return

	var force_multiplier := 1.0 - (distance_to_blast / explosion_radius)
	var applied_force := max_explosion_force * force_multiplier
	var push_direction := global_position.direction_to(body.global_position).normalized()

	if deals_damage and body.has_method("take_damage"):
		body.take_damage(GameSettings.physics_damage.explosion_damage)
		# Flash the player's hitmarker when our blast connects — enemy splash OR self-damage.
		# But ONLY when the PLAYER instigated this blast (see the gate below) — enemies have rockets now.
		if body is Character:
			# Directional damage arc toward the blast — self-damage (player in their own
			# explosion) shows it; enemies no-op.
			(body as Character).indicate_damage_from(global_position)
			# Hitmarker is PLAYER feedback for a hit the player dealt — flash it only when the player
			# instigated THIS blast (an NPC's rocket splashing another NPC must not ping it).
			if is_instance_valid(instigator) and instigator.is_in_group(&"Player") and instigator.has_method(&"on_dealt_hit"):
				instigator.on_dealt_hit()

	# Player (a Character but NOT an NPC): blast push with optional upward bias.
	if body is Character and body is not NPC:
		var biased_dir := push_direction.lerp(Vector3.UP, upward_bias).normalized()
		body.explosion_velocity += biased_dir * applied_force
	# Enemies get DOUBLE force so they juggle/fly dramatically — the gore payoff.
	elif body is NPC:
		var biased_dir := push_direction.lerp(Vector3.UP, upward_bias).normalized()
		body.explosion_velocity += biased_dir * applied_force * 2
	elif body is RigidBody3D:
		var rb := body as RigidBody3D
		if rb.freeze:
			return
		rb.apply_impulse(push_direction * applied_force, Vector3.ZERO)

func _on_timer_timeout() -> void:
	queue_free()
