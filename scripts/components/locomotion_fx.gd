class_name LocomotionFx
extends Node

## Drop-in MOVEMENT FEEDBACK for any CharacterBody3D (an NPC, or anything that moves): footstep SFX every stride
## while walking on the ground, plus a louder LAND thud + a ground-dust puff on touchdown -- so an NPC reads like
## the player when it moves. Reuses the host's spawn_dust() (Character's DustSpawner) for the puff. Drop it under
## the actor; an NPC auto-builds one if you DON'T (npc.gd _build_components), so every NPC gets it out of the box.
## All host reads are duck-typed (is_on_floor / velocity / spawn_dust), so it never hard-depends on a type.
##
## Polled in _physics_process (after the host's move_and_slide, so is_on_floor / velocity are this frame's truth).

## Footstep sounds, picked at random per step (silent if empty). Default = the shipped Footstep set.
@export var footstep_sounds: Array[AudioStream] = [
	preload("res://assets/audio/sfx/Footstep1.mp3"),
	preload("res://assets/audio/sfx/Footstep2.mp3"),
	preload("res://assets/audio/sfx/Footstep3.mp3"),
]
## Touchdown sound after a real fall (louder + lower the harder the impact). Null -> reuse the first footstep.
@export var land_sound: AudioStream = preload("res://assets/audio/sfx/Footstep1.mp3")
## Metres travelled per footstep -- time between steps = stride / speed, so faster = quicker steps. Larger = fewer.
@export var stride_length: float = 1.7
## Planar speed (m/s) above which footsteps play at all.
@export var move_threshold: float = 0.4
## Footstep loudness (dB), and the land loudness at a hard impact.
@export var footstep_volume_db: float = -8.0
@export var land_volume_db: float = -1.0
## Descent speed (m/s) at touchdown BELOW which a landing is ignored (a stair step / tiny hop, not a fall); AT/above
## hard_land_speed it's a full-strength landing (loudest + biggest dust). Between, it scales.
@export var min_land_speed: float = 2.0
@export var hard_land_speed: float = 9.0

var _step_t: float = 0.0
var _was_on_floor: bool = true
var _fall_vy: float = 0.0  ## last airborne frame's vertical velocity -> the descent speed used for the landing impact
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func _physics_process(delta: float) -> void:
	var host := get_parent()
	if host == null or not host.has_method(&"is_on_floor"):
		return
	var grounded: bool = bool(host.call(&"is_on_floor"))
	var v: Variant = host.get(&"velocity")
	var vel: Vector3 = v if v is Vector3 else Vector3.ZERO
	if grounded and not _was_on_floor:
		_land(maxf(0.0, -_fall_vy))  # downward speed at touchdown
	_was_on_floor = grounded
	if not grounded:
		_fall_vy = vel.y
		return
	# Footsteps: a step every `stride_length` metres travelled on the ground (quicker the faster you move).
	var speed := Vector2(vel.x, vel.z).length()
	if speed <= move_threshold:
		_step_t = 0.0  # reset so the first step after stopping plays promptly
		return
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = clampf(stride_length / speed, 0.18, 1.2)
		_footstep()

func _footstep() -> void:
	if footstep_sounds.is_empty():
		return
	_play(footstep_sounds[_rng.randi_range(0, footstep_sounds.size() - 1)], footstep_volume_db, _rng.randf_range(0.92, 1.08))

## Touchdown: ignore a trivial step-down; otherwise a louder, lower thud + a dust puff, all scaling with the impact.
func _land(impact: float) -> void:
	if impact < min_land_speed:
		return  # a stair step / tiny hop, not a fall -> no thud
	var t := clampf((impact - min_land_speed) / maxf(hard_land_speed - min_land_speed, 0.01), 0.0, 1.0)
	var s: AudioStream = land_sound if land_sound != null else (footstep_sounds[0] if not footstep_sounds.is_empty() else null)
	_play(s, lerpf(footstep_volume_db, land_volume_db, t), lerpf(1.0, 0.82, t))  # harder = louder + lower
	var host := get_parent()
	if host != null and host.has_method(&"spawn_dust"):
		host.call(&"spawn_dust", lerpf(0.5, 1.4, t))  # bigger puff on a harder landing

func _play(stream: AudioStream, volume_db: float, pitch: float) -> void:
	var host := get_parent()
	if stream == null or not (host is Node3D):
		return
	AudioManager.play_sfx((host as Node3D).global_position, stream, volume_db, pitch)
