class_name BulletTime
extends Node

@export var character: CharacterBody3D
@export var scope_in: ScopeIn

var _is_scoped: bool = false
var _last_us: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()
	if scope_in:
		scope_in.scoped_in.connect(_on_scoped_in)

func _on_scoped_in(_tf: bool) -> void:
	_is_scoped = _tf

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1_000_000.0
	_last_us = now

	var should_slow := _is_scoped and not character.is_on_floor()
	var target := GameTuning.BULLET_TIME_SCALE if should_slow else 1.0
	var t := 1.0 - exp(-GameTuning.BULLET_TIME_LERP_SPEED * dt)
	Engine.time_scale = lerpf(Engine.time_scale, target, t)
