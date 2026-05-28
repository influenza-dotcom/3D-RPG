class_name BulletTime
extends Node3D

enum State { READY, ACTIVE, EXHAUSTED }

@export var character: CharacterBody3D
@export var scope_in: ScopeIn
@export var attack: Attack

const TIME_SCALE_RELEASE_EPSILON: float = 0.01

var _state: State = State.READY
var _is_scoped: bool = false
# True only if scope was entered while the character was airborne. Prevents
# bullet time from activating when the player gets launched into the air while
# already scoped (e.g. self-knockback from a rocket while ADS'd on the ground).
var _scope_entered_in_air: bool = false
var _last_us: int = 0
var _active_started_us: int = 0
var _managing_time_scale: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()
	if scope_in:
		scope_in.scoped_in.connect(_on_scoped_in)
	if attack:
		attack.flash_muzzle.connect(_on_fired)

func _on_scoped_in(_tf: bool) -> void:
	_is_scoped = _tf
	if not _tf:
		# Un-scope clears the flag so a subsequent re-scope can re-arm it.
		_scope_entered_in_air = false
	elif character and not character.is_on_floor():
		_scope_entered_in_air = true

func _on_fired() -> void:
	if _state == State.ACTIVE:
		_state = State.EXHAUSTED

func is_active() -> bool:
	return _state == State.ACTIVE

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1_000_000.0
	_last_us = now

	var on_floor: bool = true
	if character:
		on_floor = character.is_on_floor()
	if on_floor:
		# Touching ground resets the arming flag so the next airborne
		# scope-in can re-activate bullet time.
		_scope_entered_in_air = false
	var in_air_scoped: bool = _is_scoped and not on_floor and _scope_entered_in_air

	match _state:
		State.READY:
			if in_air_scoped:
				_state = State.ACTIVE
				_active_started_us = now
		State.ACTIVE:
			var elapsed := (now - _active_started_us) / 1_000_000.0
			if elapsed >= GameSettings.weapon_general.bullet_time_duration:
				_state = State.EXHAUSTED
			elif not in_air_scoped:
				_state = State.READY
		State.EXHAUSTED:
			if not in_air_scoped:
				_state = State.READY

	if not GameSettings.allow_timescale_changes:
		return

	var t := 1.0 - exp(-GameSettings.weapon_general.bullet_time_lerp_speed * dt)
	if _state == State.ACTIVE:
		_managing_time_scale = true
		Engine.time_scale = lerpf(Engine.time_scale, GameSettings.weapon_general.bullet_time_scale, t)
	elif _managing_time_scale:
		Engine.time_scale = lerpf(Engine.time_scale, 1.0, t)
		if absf(Engine.time_scale - 1.0) < TIME_SCALE_RELEASE_EPSILON:
			Engine.time_scale = 1.0
			_managing_time_scale = false
