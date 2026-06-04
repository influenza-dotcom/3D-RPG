class_name GunFX

## Stateless gunfire visual effects lifted off the Attack coordinator — the throwaway tracer, hit
## spark, and (spray-paint) muzzle flash, each spawned under an explicit `parent` so they outlive the
## firing Weapon's churn (attack.gd parents them to the tree root) and aimed by explicit args rather
## than reading any state. The bullet material + explosion-area scene live here with the spawners that
## use them. The coordinator decides WHEN to spawn (a hit, a tracer-flagged weapon, a spray shot) and
## passes the camera in for the distance-scaled tracer thickness.

## Tracer: a brief stretched mesh from the muzzle to the shot's point, wearing the bullet material.
## Only for weapons with has_tracer; freed after TRACER_LIFETIME.
const TRACER_MATERIAL = preload("res://resources/materials/bulletmat.tres")
const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")
const TRACER_THICKNESS: float = 0.03
const TRACER_LIFETIME: float = 0.1
## Distance (m) from the camera at which a tracer is drawn at TRACER_THICKNESS; farther tracers scale
## proportionally THICKER so a distant (e.g. enemy) tracer stays visible instead of a sub-pixel sliver.
const TRACER_REFERENCE_DIST: float = 4.0
## The muzzle flash sits right at the camera, so its world-space size must be tiny (the spark
## radius used for impacts out in the world reads as screen-filling up close).
const MUZZLE_FLASH_RADIUS: float = 0.06
const HIT_SPARK_BACKOFF: float = 0.4
const HIT_SPARK_SPEED_TO_SCALE: float = 32.0

## Spawn a brief tracer: a thin box stretched from `from` (muzzle) to `to` (the shot point), wearing
## the bullet material, freed after TRACER_LIFETIME. Built like the laser beam (manual basis so it
## stays thin + aligned to the shot), parented to `parent` (the tree root) so it outlives the Weapon's
## churn. `cam` is the active camera (may be null) — its distance only scales the visible thickness.
static func spawn_tracer(parent: Node, from: Vector3, to: Vector3, cam: Camera3D) -> void:
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	var tracer := MeshInstance3D.new()
	var box := BoxMesh.new()
	# Scale thickness with how far the tracer is from the camera so a distant (e.g. enemy-fired) tracer
	# stays about as visible as a close one instead of shrinking to a sub-pixel sliver.
	var view_dist: float = cam.global_position.distance_to((from + to) * 0.5) if cam else TRACER_REFERENCE_DIST
	var thick := TRACER_THICKNESS * maxf(1.0, view_dist / TRACER_REFERENCE_DIST)
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
	parent.get_tree().create_timer(TRACER_LIFETIME).timeout.connect(tracer.queue_free)

## Spawn the bullet-impact spark at `pos`, backed off slightly along the hit direction so it sits proud
## of the surface. A non-damaging explosion area that scales in with the impact speed.
static func spawn_hit_spark(parent: Node, pos: Vector3, dir: Vector3) -> void:
	var explosion = EXPLOSION_AREA.instantiate()
	explosion.max_explosion_force = 0.0
	explosion.explosion_radius = GameSettings.effects.explosion_spark_radius
	explosion.speed_to_scale = HIT_SPARK_SPEED_TO_SCALE
	explosion.deals_damage = false
	parent.add_child(explosion)
	explosion.position = pos - dir.normalized() * HIT_SPARK_BACKOFF

## Coloured muzzle flash for the spray can — reuses the bullet-hit spark, tinted to match the paint
## (like the splat) and popped at full size instantly (no grow-in) at the tiny near-camera radius.
static func spawn_muzzle_flash(parent: Node, pos: Vector3, color: Color) -> void:
	var flash := EXPLOSION_AREA.instantiate()
	flash.max_explosion_force = 0.0
	flash.deals_damage = false
	flash.explosion_radius = MUZZLE_FLASH_RADIUS
	flash.speed_to_scale = 0.0  # pop at full size instantly like a real muzzle flash, no grow-in
	flash.tint_color = color
	parent.add_child(flash)
	flash.position = pos
