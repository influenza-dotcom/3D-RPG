@tool
class_name CanDestroy
extends StaticBody3D

## Drop-in DESTRUCTIBLE component: a body that breaks apart when shot. Use it as the root of (or attach it
## to) any object you want to shoot to pieces — give it a CollisionShape3D + a MeshInstance3D child.
##
## BOTH the hitscan path (attack.gd) and the projectile path (projectile.gd) call take_damage() on
## whatever body they hit, so this works for EVERY weapon with no changes to either. At 0 HP it spawns an
## optional effect + sound and frees itself (and everything under it). Lives on the default StaticBody3D
## collision layer (1 = world), so shots land on it just like a wall — set the layer in the scene if needed.

const WorldSaveId = preload("res://scripts/world/world_save_id.gd")  # stable per-object save key (GameState.world_objects)

@export var max_hp: int = 1                ## how many shots to destroy it (1 = one-shot)
@export var destroy_effect: PackedScene    ## optional VFX spawned at our position on destruction (one-shot)
@export var destroy_sound: AudioStream     ## optional 3D one-shot played on destruction
## OPTIONAL stable id so this prop stays destroyed across a save/load (and node moves). Blank = level+path+position
## fallback (fine for a hand-placed prop that never moves — see WorldSaveId). Only destroyed props are stored.
@export var save_id: StringName = &""

signal destroyed

var hp: int
var _destroyed := false

func _ready() -> void:
	hp = max_hp
	# Stay destroyed across a reload: if this prop was already broken this run, don't respawn it. Runtime-only
	# (@tool _ready also runs in-editor — never touch GameState there). The "gone" bit is coerced through
	# GameState.as_bool (persisted-Variant safety, mirrors Door): a hand-edited / legacy gamestate.cfg could hold a
	# String under the key, and bare truthiness on a non-empty String reads true — as_bool degrades junk to the default.
	if not Engine.is_editor_hint() and GameState.as_bool(GameState.object_state(GameState.current_level_path, _save_key()).get("gone", false)):
		queue_free()

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
			# empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
			if fx == null:
				return
			get_tree().root.add_child(fx)
			if fx is Node3D:
				(fx as Node3D).global_position = global_position
			if fx is GPUParticles3D:
				(fx as GPUParticles3D).emitting = true
				(fx as GPUParticles3D).finished.connect(fx.queue_free)
		if destroy_sound != null:
			AudioManager.play_sfx(global_position, destroy_sound, 0.0, 1.0)
		# Persist "gone" so a reloaded level doesn't respawn this prop (keyed by level + save_id/fallback).
		if not Engine.is_editor_hint():
			GameState.record_object_state(GameState.current_level_path, _save_key(), {"gone": true})
	queue_free()

func _save_key() -> String:
	return WorldSaveId.key_for(self, save_id)

## Editor warning: a destructible with no collider can never be shot -- it's silently indestructible. The
## collider must be a direct child of this StaticBody3D (a mesh may live elsewhere, so we don't warn on that).
## Re-evaluated by the editor when children change.
func _get_configuration_warnings() -> PackedStringArray:
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			return PackedStringArray()
	return PackedStringArray([
		"No CollisionShape3D (with a shape) child — shots can't hit this StaticBody3D, so it can never be destroyed. Add one sized to the object.",
	])
