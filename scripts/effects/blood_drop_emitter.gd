class_name BloodDropEmitter
extends Node

## Spawns death-gore blood drops spread across several physics frames instead of all
## at once. A single kill rains DROP_COUNT (~100) RigidBody3D drops; registering that
## many physics bodies with the physics server in ONE frame is what hitched the game
## on death. This emitter batches them (`_per_frame` each physics frame) so the cost
## is amortized while keeping the full drop count.
##
## It lives under the scene root, independent of the dying Character (which
## queue_free()s itself the same frame its gore fires, taking its BloodyMess child
## with it), and self-frees once every drop has spawned. The per-drop spawn
## parameters (scatter + speed range) live in GameSettings.effects (blood_drop_*),
## so the death rain and the per-gib burst spawn identical drops.

const BLOOD_DROP := preload("res://scenes/effects/blood_drop.tscn")

var _origin: Vector3
var _remaining: int = 0
var _per_frame: int = 1

## Begin raining `count` drops centred on `origin`, at most `per_frame` per physics
## frame. Call right after add_child()ing the emitter to the scene root.
func start(origin: Vector3, count: int, per_frame: int) -> void:
	_origin = origin
	_remaining = maxi(0, count)
	_per_frame = maxi(1, per_frame)

func _physics_process(_delta: float) -> void:
	var batch := mini(_per_frame, _remaining)
	for i in batch:
		_spawn_one()
	_remaining -= batch
	if _remaining <= 0:
		queue_free()

func _spawn_one() -> void:
	var drop := BLOOD_DROP.instantiate()
	get_tree().root.add_child(drop)
	var scatter: float = GameSettings.effects.blood_drop_scatter
	drop.global_position = _origin + Vector3(
		randf_range(-scatter, scatter),
		randf_range(0.0, scatter),
		randf_range(-scatter, scatter)
	)
	var dir := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(0.6, 1.5),
		randf_range(-1.0, 1.0)
	).normalized()
	var vel_min: float = GameSettings.effects.blood_drop_vel_min
	var vel_max: float = GameSettings.effects.blood_drop_vel_max
	drop.linear_velocity = dir * randf_range(vel_min, vel_max)
