class_name PickupRay
extends RayCast3D

@export var player: CharacterBody3D
@export var hold_anchor: Marker3D

var held_object: Interactable = null
var _prior_gravity_scale: float = 1.0
var _prior_collision_layer: int = 1
var _release_timer_started_us: int = -1
var _last_targeted: Interactable = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("PickUp"):
		if held_object:
			_release_timer_started_us = Time.get_ticks_usec()
		elif is_colliding():
			var target := get_collider() as Interactable
			if target:
				_pick_up(target)
	elif event.is_action_released("PickUp"):
		if held_object and _release_timer_started_us > 0:
			var held_for_s := (Time.get_ticks_usec() - _release_timer_started_us) / 1_000_000.0
			var impulse: float = GameTuning.PICKUP_THROW_IMPULSE if held_for_s >= GameTuning.PICKUP_E_HOLD_THRESHOLD else GameTuning.PICKUP_DROP_IMPULSE
			_release(impulse)
		_release_timer_started_us = -1

func _physics_process(_delta: float) -> void:
	_update_target_outline()
	if not held_object:
		return
	if not is_instance_valid(held_object):
		held_object = null
		return
	var to_anchor := hold_anchor.global_position - held_object.global_position
	if to_anchor.length() > GameTuning.PICKUP_MAX_HOLD_DISTANCE:
		_release(GameTuning.PICKUP_DROP_IMPULSE)
		return
	var clamped := to_anchor.limit_length(GameTuning.PICKUP_HOLD_MAX_DISPLACEMENT)
	var spring_force := clamped * GameTuning.PICKUP_HOLD_STIFFNESS
	var damp_force := -held_object.linear_velocity * GameTuning.PICKUP_HOLD_DAMPING
	held_object.apply_central_force(spring_force + damp_force)
	held_object.angular_velocity *= GameTuning.PICKUP_HOLD_ANGULAR_DAMPING

func _update_target_outline() -> void:
	var current: Interactable = null
	if not held_object and is_colliding():
		current = get_collider() as Interactable
	if current == _last_targeted:
		return
	if _last_targeted and is_instance_valid(_last_targeted):
		_last_targeted.set_outline_visible(false)
	if current:
		current.set_outline_visible(true)
	_last_targeted = current

func _pick_up(target: Interactable) -> void:
	held_object = target
	_prior_gravity_scale = held_object.gravity_scale
	_prior_collision_layer = held_object.collision_layer
	held_object.collision_layer = GameTuning.PICKUP_HELD_COLLISION_LAYER
	held_object.gravity_scale = 0.0
	if player:
		player.add_collision_exception_with(held_object)
	held_object.on_picked_up(self)

func _release(impulse: float) -> void:
	if not is_instance_valid(held_object):
		held_object = null
		return
	var dropped := held_object
	held_object = null
	dropped.collision_layer = _prior_collision_layer
	dropped.gravity_scale = _prior_gravity_scale
	if player:
		player.remove_collision_exception_with(dropped)
	var forward := -global_basis.z.normalized()
	dropped.linear_velocity += forward * impulse
	dropped.on_dropped()
