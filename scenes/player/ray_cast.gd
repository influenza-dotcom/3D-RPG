class_name PickupRay
extends RayCast3D

@export var player: CharacterBody3D
@export var hold_anchor: Marker3D

var held_object: Interactable = null
var _prior_gravity_scale: float = 1.0
var _prior_collision_layer: int = 1
var _prior_freeze: bool = false
var _prior_freeze_mode: int = RigidBody3D.FREEZE_MODE_STATIC
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

func _physics_process(delta: float) -> void:
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
	held_object.linear_velocity = Vector3.ZERO
	held_object.angular_velocity = Vector3.ZERO
	var follow_t := 1.0 - exp(-GameTuning.PICKUP_HOLD_FOLLOW_RATE * delta)
	var step := to_anchor * follow_t
	step = step.limit_length(GameTuning.PICKUP_MAX_STEP_PER_FRAME)
	if step.length() < 0.0001:
		return
	var safe_step := _safe_motion(held_object, step)
	held_object.global_position += safe_step

func _safe_motion(body: Interactable, motion: Vector3) -> Vector3:
	if not body.collision_shape or not body.collision_shape.shape:
		return motion
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body.collision_shape.shape
	query.transform = body.collision_shape.global_transform
	query.motion = motion
	query.collision_mask = body.collision_mask
	var exclude: Array[RID] = [body.get_rid()]
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude
	var result := space_state.cast_motion(query)
	if result.is_empty():
		return motion
	return motion * result[0]

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
	_prior_freeze = held_object.freeze
	_prior_freeze_mode = held_object.freeze_mode
	held_object.collision_layer = GameTuning.PICKUP_HELD_COLLISION_LAYER
	held_object.gravity_scale = 0.0
	held_object.linear_velocity = Vector3.ZERO
	held_object.angular_velocity = Vector3.ZERO
	held_object.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	held_object.freeze = true
	if player:
		player.add_collision_exception_with(held_object)
	held_object.on_picked_up(self)

func _release(impulse: float) -> void:
	if not is_instance_valid(held_object):
		held_object = null
		return
	var dropped := held_object
	held_object = null
	dropped.freeze = _prior_freeze
	dropped.freeze_mode = _prior_freeze_mode
	dropped.collision_layer = _prior_collision_layer
	dropped.gravity_scale = _prior_gravity_scale
	var forward := -global_basis.z.normalized()
	var lateral := global_basis.x.normalized() * GameTuning.PICKUP_DROP_LATERAL_NUDGE
	dropped.linear_velocity = forward * impulse + lateral
	dropped.on_dropped()
	if player:
		var t := get_tree().create_timer(GameTuning.PICKUP_DROP_EXCEPTION_DELAY, true, true, true)
		t.timeout.connect(_restore_player_collision.bind(dropped))

func _restore_player_collision(dropped: Node) -> void:
	if not is_instance_valid(player) or not is_instance_valid(dropped):
		return
	if dropped is RigidBody3D and dropped is Node3D and player is Node3D:
		var rb := dropped as RigidBody3D
		var dropped_pos: Vector3 = (dropped as Node3D).global_position
		var player_pos: Vector3 = (player as Node3D).global_position
		var to_rb := dropped_pos - player_pos
		var horizontal: float = Vector2(to_rb.x, to_rb.z).length()
		if horizontal < GameTuning.PICKUP_SAFE_HORIZONTAL_DISTANCE:
			var slide_dir := Vector3(to_rb.x, 0.0, to_rb.z)
			if slide_dir.length_squared() < 0.01:
				slide_dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			slide_dir = slide_dir.normalized()
			rb.linear_velocity += slide_dir * GameTuning.PICKUP_SLIDE_OFF_IMPULSE
			var t := get_tree().create_timer(GameTuning.PICKUP_SAFE_RECHECK_DELAY, true, true, true)
			t.timeout.connect(_restore_player_collision.bind(dropped))
			return
	player.remove_collision_exception_with(dropped)
