class_name CanDestroy
extends StaticBody3D

## Drop-in DESTRUCTIBLE component: a body that breaks apart when shot. Use it as the root of (or attach it
## to) any object you want to shoot to pieces — give it a CollisionShape3D + a MeshInstance3D child.
##
## BOTH the hitscan path (attack.gd) and the projectile path (projectile.gd) call take_damage() on
## whatever body they hit, so this works for EVERY weapon with no changes to either. At 0 HP it spawns an
## optional effect + sound and frees itself (and everything under it). Lives on the default StaticBody3D
## collision layer (1 = world), so shots land on it just like a wall — set the layer in the scene if needed.

@export var max_hp: int = 1                ## how many shots to destroy it (1 = one-shot)
@export var destroy_effect: PackedScene    ## optional VFX spawned at our position on destruction (one-shot)
@export var destroy_sound: AudioStream     ## optional 3D one-shot played on destruction

signal destroyed

var hp: int
var _destroyed := false

func _ready() -> void:
	hp = max_hp

## A shot (or any damage source) landed on us. Signature mirrors Character / Throwable.take_damage so the
## same projectile/hitscan call works unchanged. Any positive hit removes at least 1 HP; at 0 we break.
func take_damage(amount: float, _was_crit: bool = false, _attacker: Node = null, _hit_pos: Vector3 = Vector3.INF) -> void:
	if _destroyed or amount <= 0.0:
		return
	hp -= maxi(1, int(ceil(amount)))
	if hp <= 0:
		_destroy()

func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit()
	# Side effects need a live tree; an off-tree instance (a unit test) just emits + frees.
	if is_inside_tree():
		if destroy_effect != null:
			var fx := destroy_effect.instantiate()
			get_tree().root.add_child(fx)
			if fx is Node3D:
				(fx as Node3D).global_position = global_position
			if fx is GPUParticles3D:
				(fx as GPUParticles3D).emitting = true
				(fx as GPUParticles3D).finished.connect(fx.queue_free)
		if destroy_sound != null:
			AudioManager.play_sfx(global_position, destroy_sound, 0.0, 1.0)
	queue_free()
