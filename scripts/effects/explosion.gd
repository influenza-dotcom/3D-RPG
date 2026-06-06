extends Node3D

## Bridge from a projectile's death to a spawned Explosion. Lives on the projectile-
## owning scene and listens to a projectile's `queued_for_deletion(last_pos)` signal,
## spawning an Explosion at the impact point. Two flavors:
##   • rock projectile   -> a real damaging blast (full force + radius) + impact SFX.
##   • generic projectile -> a force-less visual spark only (spark radius, no push).

const EXPLOSION_AREA = preload("uid://co1ehjy0gbhu3")

@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0
@export_range(0.0, 1.0) var upward_bias: float = 0.0
@export var sfx: AudioStreamPlayer3D
@export var speed_to_scale: float

func _spawn_at(_last_pos: Vector3, _force: float, _radius: float) -> void:
	if EXPLOSION_AREA == null:
		return
	var explosion = EXPLOSION_AREA.instantiate()
	# Defensive: the PackedScene can momentarily come back EMPTY (instantiate -> null) while the open
	# editor is reimporting the project — its resource cache is briefly invalid. The scene itself is
	# valid (verified headless: 7 nodes), so skip this one blast rather than hard-crash on a null deref;
	# it works again once the import settles. Never happens in an exported build (baked, stable cache).
	if explosion == null:
		push_warning("explosion: EXPLOSION_AREA instantiated to null (editor reimport churn) — skipping blast")
		return
	explosion.max_explosion_force = _force
	explosion.explosion_radius = _radius
	explosion.upward_bias = upward_bias
	explosion.speed_to_scale = speed_to_scale
	# Carry who fired the projectile (the parent's `shooter`) into the blast so its hitmarker ping
	# only fires for a PLAYER-instigated explosion, not an NPC's rocket. null if there's no shooter.
	var p := get_parent()
	explosion.instigator = p.get(&"shooter") if p else null
	get_tree().root.add_child(explosion)
	explosion.position = _last_pos

## Rocket/rock impact: full-force damaging explosion + a reparented one-shot SFX.
## The SFX is reparented to the scene root so it outlives this node / the projectile
## and isn't cut off when they free.
func _on_rock_projectile_queued_for_deletion(_last_pos: Vector3) -> void:
	_spawn_at(_last_pos, max_explosion_force, explosion_radius)

	sfx.reparent(get_tree().root)
	sfx.position = _last_pos
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

## Ordinary bullet impact: force 0 + spark radius — a purely cosmetic hit flash, no
## knockback or damage from the blast itself.
func _on_projectile_queued_for_deletion(_last_pos: Vector3) -> void:
	_spawn_at(_last_pos, 0.0, GameSettings.effects.explosion_spark_radius)
