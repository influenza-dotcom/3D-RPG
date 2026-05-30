class_name Bullet
extends Projectile

## The standard projectile: a small round that punches a bullet-hole decal and
## sprays blood on Characters / dust on everything else. The abstract [Projectile]
## base owns movement, damage and impact orchestration; this concrete variant just
## fills in the two per-variant hooks — the impact decal and the impact particles.
## Used by Projectile.tscn (pistol/shotgun) and sphere_projectile.tscn (smg);
## rock_projectile.gd is the other variant.

const BLOOD = preload("uid://c7v6vgs74fhn4")
const DUST = preload("uid://um6f8g8g6l7v")

## Backoff used to place the decal when the impact raycast finds no surface.
const DECAL_FALLBACK_BACKOFF: float = 0.05

func particles(_body, _last_velocity) -> void:
	var is_character: bool = _body is Character
	var _particles = BLOOD.instantiate() if is_character else DUST.instantiate()
	get_tree().root.add_child(_particles)
	var backoff := IMPACT_BACKOFF if is_character else PARTICLE_BACKOFF
	_particles.global_position = global_position - _last_velocity.normalized() * backoff
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)
	if is_character and _body.get("bloody_mess"):
		_body.bloody_mess.splatter_at(global_position, _last_velocity)

func _spawn_decal(last_velocity: Vector3) -> void:
	if last_velocity.is_zero_approx():
		return
	var dir := last_velocity.normalized()
	var space_state := get_world_3d().direct_space_state
	var probe_dist := GameSettings.effects.decal_probe_distance
	var query := PhysicsRayQueryParameters3D.create(
		global_position - dir * probe_dist,
		global_position + dir * probe_dist
	)
	var result := space_state.intersect_ray(query)

	var decal = BULLET_HOLE_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.size = DECAL_SIZE
	decal.cull_mask = DECAL_CULL_MASK

	if result:
		decal.global_position = result.position + result.normal * GameSettings.effects.decal_normal_offset
		_orient_decal_to_normal(decal, result.normal)
	else:
		decal.global_position = global_position - dir * DECAL_FALLBACK_BACKOFF
