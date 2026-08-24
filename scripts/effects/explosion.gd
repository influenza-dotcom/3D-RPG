extends Node3D

## Bridge from a projectile's death to a spawned Explosion. Lives on the projectile-
## owning scene and listens to a projectile's `queued_for_deletion(last_pos)` signal,
## spawning an Explosion at the impact point. Two flavors:
##   • rock projectile   -> a real damaging blast (full force + radius) + impact SFX.
##   • generic projectile -> a force-less visual spark only (spark radius, no push).
##
## The blast scene is resolved through the shared Explosion.instantiate_recovering() source (the reimport-recovery
## idiom lives there once), so this bridge holds no preload of its own.

## Peak radial push impulse handed to the spawned blast on a rock/rocket impact, falling off to 0 at explosion_radius. 0 = no shove.
@export var max_explosion_force: float = 20.0
## Blast reach in metres for the rock/rocket impact: sizes the spawned explosion's mesh/light/collider and the push falloff distance.
@export var explosion_radius: float = 4.0
## Blast DAMAGE for the rock/rocket impact, forwarded onto the spawned Explosion. -1 = the global
## GameSettings.physics_damage.explosion_damage fallback; ProjectileSpawner sets this from WeaponData.explosion_damage (M9).
@export var explosion_damage: float = -1.0
## How much the blast push tilts upward: 0 = pure outward shove, 1 = straight up — raise it to lob/juggle bodies instead of just shoving.
@export_range(0.0, 1.0) var upward_bias: float = 0.0
## The one-shot impact sound for a rock/rocket hit; reparented to the scene root on detonation so it finishes playing after this node frees.
@export var sfx: AudioStreamPlayer3D
## Grow-in speed of the spawned blast mesh: 0 = pop at full size instantly, >0 = bloom outward from zero (higher = faster bloom).
@export var speed_to_scale: float

## `_deals_damage` MUST be passed explicitly by every caller. Explosion.deals_damage defaults to TRUE on the
## script (explosion_area.gd), and explosion_area.tscn does not override it — so a blast this bridge spawns
## without setting it damages whatever it overlaps. That default is right for the rocket and wrong for the
## bullet spark, which is documented as purely cosmetic; leaving it unset made every ordinary bullet impact
## spawn a damaging Area3D. Mirrors gun_fx.gd:61/74/85 and paint_projectile.gd:92, which all set it by hand.
func _spawn_at(_last_pos: Vector3, _force: float, _radius: float, _damage: float = -1.0, _deals_damage: bool = true) -> void:
	# Resolve the blast through the shared reimport-recovery source: the cached fast load, falling back to a fresh
	# cache-bypassing read if the scene baked empty mid-reimport. null ONLY if genuinely unavailable — warn + skip
	# rather than crash. The property sets below are all valid on the typed Explosion it returns.
	var explosion := Explosion.instantiate_recovering()
	if explosion == null:
		push_warning("explosion: explosion_area.tscn unavailable — skipping blast")
		return
	explosion.max_explosion_force = _force
	explosion.explosion_radius = _radius
	explosion.explosion_damage = _damage  # M9: -1 -> the blast uses the global fallback; a rocket forwards its WeaponData value
	explosion.deals_damage = _deals_damage  # never left to the script default — see _spawn_at's doc comment
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
	_spawn_at(_last_pos, max_explosion_force, explosion_radius, explosion_damage, true)  # M9: carry the weapon's blast damage; a rocket's blast DOES damage

	# A drop-in Explosion bridge without `sfx` wired must still spawn its blast and not
	# crash on impact — the impact SFX is optional.
	if sfx != null:
		sfx.reparent(get_tree().root)
		sfx.position = _last_pos
		AudioManager.play_varied(sfx)
		sfx.finished.connect(sfx.queue_free)

## Ordinary bullet impact: force 0 + spark radius — a purely cosmetic hit flash, no
## knockback or damage from the blast itself.
##
## deals_damage=false is what MAKES that true. The round has already dealt its damage in
## Projectile._on_body_entered; a damaging spark on top of it charged every bullet in the game an extra
## splash hit (GameSettings.physics_damage.explosion_damage) against anything within explosion_spark_radius.
## It also flips Explosion's `visual_only` gate on, so the spark stops holding a monitoring Area3D live for
## two physics frames per shot.
func _on_projectile_queued_for_deletion(_last_pos: Vector3) -> void:
	_spawn_at(_last_pos, 0.0, GameSettings.effects.explosion_spark_radius, -1.0, false)
