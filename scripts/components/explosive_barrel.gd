@tool
class_name ExplosiveBarrel
extends CanDestroy

## A destructible that DETONATES when destroyed (SE-1): shoot it — or catch it in another blast — and it spawns
## a damaging explosion at its spot. CHAINING is free: the blast's Area3D calls take_damage on every overlapping
## body, so a nearby ExplosiveBarrel is destroyed and detonates IN TURN (a frame later via the Area3D's deferred
## body_entered — never a synchronous recursion; CanDestroy's _destroyed latch stops a re-trigger). The player who
## shot the first barrel is credited through the chain (the instigator rides the blast). Tune the blast per barrel;
## the flash/SFX come from the shared explosion_area scene + CanDestroy's destroy_effect / destroy_sound.

const EXPLOSION_AREA := preload("uid://co1ehjy0gbhu3")  # explosion_area.tscn (the shared blast)

@export_group("Blast")
## Peak radial push at ground zero, falling to 0 at blast_radius (also drives the blast's reach/feel).
@export var blast_force: float = 20.0
## Blast radius in metres — sizes the explosion + the push/damage falloff.
@export var blast_radius: float = 4.0
## Bias the push toward straight UP (0 = outward shove, 1 = pure vertical pop).
@export_range(0.0, 1.0) var blast_upward_bias: float = 0.1

var _last_attacker: Node = null  ## who last shot us — forwarded as the blast instigator so a player barrel-kill credits them

## Remember who dealt the hit (for blast attribution), then run CanDestroy's normal damage / destroy.
func take_damage(amount: float, was_crit: bool = false, attacker: Node = null, hit_pos: Vector3 = Vector3.INF) -> void:
	if attacker != null:
		_last_attacker = attacker
	super.take_damage(amount, was_crit, attacker, hit_pos)

## Detonate BEFORE freeing: spawn the blast at our spot, then fall through to CanDestroy's destroy FX + free. The
## _destroyed guard (the same latch CanDestroy uses) keeps a second _destroy from detonating twice.
func _destroy() -> void:
	if _destroyed:
		return
	_detonate()
	super._destroy()

## Spawn the damaging explosion at our position and return it (null off-tree / if the blast scene is momentarily
## unavailable mid-reimport). blast_* size the blast; the last attacker rides as the instigator for kill credit.
func _detonate() -> Explosion:
	if not is_inside_tree():
		return null
	var scene: PackedScene = EXPLOSION_AREA if (EXPLOSION_AREA != null and EXPLOSION_AREA.can_instantiate()) \
		else ResourceLoader.load("res://scenes/effects/explosion_area.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		return null
	var explosion := scene.instantiate() as Explosion
	if explosion == null:
		return null
	explosion.max_explosion_force = blast_force
	explosion.explosion_radius = blast_radius
	explosion.upward_bias = blast_upward_bias
	explosion.instigator = _last_attacker
	get_tree().root.add_child(explosion)
	explosion.global_position = global_position
	return explosion
