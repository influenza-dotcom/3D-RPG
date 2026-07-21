extends Area3D

## The wide screen-shake trigger around an Explosion (a larger, separate radius than
## the damaging blast collider). Only the Player triggers it, and only when the owning
## Explosion opts in via allowed_shake_screen. Shake scales down with distance.

## This area's CollisionShape3D (a SphereShape3D) — its radius IS the shake falloff distance: shake is full
## at the centre and fades to zero at the sphere's edge. Resize the sphere to widen/narrow the shake zone.
@export var collision_shape_3d: CollisionShape3D
## The owning Explosion this shake belongs to — read for its `allowed_shake_screen` flag; if that's off, this
## blast never shakes the camera. Point it at the sibling Explosion.
@export var explosion_area: Explosion

func _on_body_entered(body: Node3D) -> void:
	# A bare-instanced ScreenShakeArea may have neither @export wired — bail before
	# dereferencing either so an unwired drop-in never null-derefs when the Player overlaps.
	if explosion_area == null or collision_shape_3d == null:
		return
	if collision_shape_3d.shape is not SphereShape3D:
		return
	if body is Player and explosion_area.allowed_shake_screen:
		var distance_to_blast := body.global_position.distance_to(global_position)
		var radius := (collision_shape_3d.shape as SphereShape3D).radius
		var shake_amount := shake_multiplier_for(distance_to_blast, radius) * GameSettings.screen_shake.explosion_shake_mult

		var screen_shake = body.screen_shake
		if screen_shake:
			screen_shake.shake_explosion(shake_amount)


## Distance falloff for the shake, as a PURE function so the smoke tests can pin it off-tree (no Player +
## explosion scene boot): full strength (1.0) at the blast centre, fading linearly to 0.0 at `radius` (the shake
## sphere's edge), clamped outside [0, radius]. A non-positive radius yields 0.0 — no shake, no divide-by-zero.
static func shake_multiplier_for(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	return clampf(1.0 - (distance / radius), 0.0, 1.0)
