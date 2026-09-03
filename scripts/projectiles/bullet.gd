class_name Bullet
extends Projectile

## The standard projectile: a small round that punches a bullet-hole decal and
## sprays blood on Characters / dust on everything else. The abstract [Projectile]
## base owns movement, damage and impact orchestration; this concrete variant just
## fills in the two per-variant hooks — the impact decal and the impact particles.
## Used by Projectile.tscn (pistol/shotgun/SMG/sniper) and sphere_projectile.tscn (spray paint);
## rock_projectile.gd is the other variant.

const BLOOD = preload("uid://c7v6vgs74fhn4")
const DUST = preload("uid://um6f8g8g6l7v")

## Backoff used to place the decal when the impact raycast finds no surface.
const DECAL_FALLBACK_BACKOFF: float = 0.05

## ⭐⭐A fired ROUND MUST NEVER TUMBLE — the structural guarantee behind the de-spin in Projectile's pierce.
##
## The visual and the collider are wildly mismatched: Projectile.tscn's MeshInstance3D scales a radius-0.2
## SphereMesh by 6 on Z and offsets it +0.326, making a 2.4 m x 4 mm emissive needle spanning local z
## [-0.874, +1.526] — around a SphereShape3D collider of radius 0.05. That is a 30:1 lever. A round that
## stops with any residual spin sweeps its tip through a ~3 m disc, which reads to the player as a tracer
## ORBITING whatever it stopped next to (it is what "the bullet is rotating around my corpse" was).
##
## Locking is behaviourally FREE: the only orientation a round ever receives is the one-shot look_at in
## Projectile._ready(), which aims the needle along travel. There is no _physics_process, no
## _integrate_forces and no custom_integrator anywhere in the Projectile hierarchy, so nothing re-orients a
## round in flight and nothing depends on it spinning. Set AFTER super() so look_at has already aimed it.
##
## Deliberately NOT on the base Projectile: RockProjectile is a lobbed rock and SHOULD tumble.
func _ready() -> void:
	super()
	lock_rotation = true

func particles(_body, _last_velocity) -> void:
	var is_character: bool = _body is Character
	var _particles = BLOOD.instantiate() if is_character else DUST.instantiate()
	# empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
	if _particles == null:
		return
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
	# empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
	if decal == null:
		return
	get_tree().root.add_child(decal)
	decal.size = DECAL_SIZE
	decal.cull_mask = DECAL_CULL_MASK

	if result:
		decal.global_position = result.position + result.normal * GameSettings.effects.decal_normal_offset
		_orient_decal_to_normal(decal, result.normal)
	else:
		decal.global_position = global_position - dir * DECAL_FALLBACK_BACKOFF
