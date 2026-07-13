class_name GunFX

## Stateless gunfire visual effects lifted off the Attack coordinator — the throwaway tracer, hit
## spark, and (spray-paint) muzzle flash, each spawned under an explicit `parent` so they outlive the
## firing Weapon's churn (attack.gd parents them to the tree root) and aimed by explicit args rather
## than reading any state. The bullet material lives here; the explosion-area blast scene is resolved through the
## shared Explosion.instantiate_recovering() source. The coordinator decides WHEN to spawn (a hit, a tracer-flagged
## weapon, a spray shot) and passes the camera in for the distance-scaled tracer thickness.

## Tracer: a brief stretched mesh from the muzzle to the shot's point, wearing the bullet material.
## Only for weapons with has_tracer; thickness / lifetime / distance-compensation are designer knobs
## on GameSettings.weapon_general (tracer_thickness / tracer_lifetime / tracer_reference_dist).
const TRACER_MATERIAL = preload("res://resources/materials/bulletmat.tres")
# The blast scene for the hit spark / overkill burst / muzzle flash is resolved through the shared
# Explosion.instantiate_recovering() source (reimport-recovery lives there once), not a preload here.
# Muzzle-flash / hit-spark / overkill-burst sizing + placement are designer knobs on GameSettings.effects
# (muzzle_flash_radius / hit_spark_backoff / hit_spark_speed_to_scale / overkill_burst_radius). The muzzle
# flash sits right at the camera so its world radius is tiny; the overkill burst is bigger than the ordinary
# spark so a shot punching THROUGH one enemy into the next reads clearly.

## Spawn a brief tracer: a thin box stretched from `from` (muzzle) to `to` (the shot point), wearing
## the bullet material, freed after the tunable tracer_lifetime. Built like the laser beam (manual
## basis so it stays thin + aligned to the shot), parented to `parent` (the tree root) so it outlives
## the Weapon's churn. `cam` is the active camera (may be null) — its distance only scales the visible
## thickness.
static func spawn_tracer(parent: Node, from: Vector3, to: Vector3, cam: Camera3D) -> void:
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	var tracer := MeshInstance3D.new()
	var box := BoxMesh.new()
	# Scale thickness with how far the tracer is from the camera so a distant (e.g. enemy-fired) tracer
	# stays about as visible as a close one instead of shrinking to a sub-pixel sliver.
	var view_dist: float = cam.global_position.distance_to((from + to) * 0.5) if cam \
			else GameSettings.weapon_general.tracer_reference_dist
	var thick: float = GameSettings.weapon_general.tracer_thickness \
			* maxf(1.0, view_dist / GameSettings.weapon_general.tracer_reference_dist)
	box.size = Vector3(thick, thick, 1.0)
	tracer.mesh = box
	tracer.material_override = TRACER_MATERIAL
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(tracer)
	var bdir := (to - from) / dist
	var x := bdir.cross(Vector3.UP)
	if x.length_squared() < 0.000001:
		x = bdir.cross(Vector3.FORWARD)
	x = x.normalized()
	var y := x.cross(bdir).normalized()
	tracer.global_transform = Transform3D(Basis(x, y, bdir * dist), (from + to) * 0.5)
	parent.get_tree().create_timer(GameSettings.weapon_general.tracer_lifetime).timeout.connect(tracer.queue_free)

## Spawn the bullet-impact spark at `pos`, backed off slightly along the hit direction so it sits proud
## of the surface. A non-damaging explosion area that scales in with the impact speed.
static func spawn_hit_spark(parent: Node, pos: Vector3, dir: Vector3) -> void:
	var explosion := Explosion.instantiate_recovering()
	if explosion == null:
		return
	explosion.max_explosion_force = 0.0
	explosion.explosion_radius = GameSettings.effects.explosion_spark_radius
	explosion.speed_to_scale = GameSettings.effects.hit_spark_speed_to_scale
	explosion.deals_damage = false
	parent.add_child(explosion)
	explosion.position = pos - dir.normalized() * GameSettings.effects.hit_spark_backoff

## A prominent NON-damaging burst where an overkill-penetrating shot lands on a pierced target — the
## visible "it punched through" feedback (paired with a tracer down the pierce segment in attack.gd).
static func spawn_overkill_burst(parent: Node, pos: Vector3, dir: Vector3) -> void:
	var burst := Explosion.instantiate_recovering()
	if burst == null:
		return  # empty FX scene (reimport hiccup) — skip the cosmetic burst rather than crash
	burst.max_explosion_force = 0.0
	burst.explosion_radius = GameSettings.effects.overkill_burst_radius
	burst.speed_to_scale = 0.0  # pop at full size instantly so it's unmissable
	burst.deals_damage = false
	parent.add_child(burst)
	burst.position = pos - dir.normalized() * GameSettings.effects.hit_spark_backoff

## Coloured muzzle flash for the spray can — reuses the bullet-hit spark, tinted to match the paint
## (like the splat) and popped at full size instantly (no grow-in) at the tiny near-camera radius.
static func spawn_muzzle_flash(parent: Node, pos: Vector3, color: Color) -> void:
	var flash := Explosion.instantiate_recovering()
	if flash == null:
		return  # empty FX scene (reimport hiccup) — skip the cosmetic muzzle flash rather than crash
	flash.max_explosion_force = 0.0
	flash.deals_damage = false
	flash.explosion_radius = GameSettings.effects.muzzle_flash_radius
	flash.speed_to_scale = 0.0  # pop at full size instantly like a real muzzle flash, no grow-in
	flash.tint_color = color
	parent.add_child(flash)
	flash.position = pos
