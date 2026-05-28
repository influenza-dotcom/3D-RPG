class_name PickupRay
extends RayCast3D

## Physics-object pickup / carry / throw. A RayCast3D from the camera detects the
## aimed Interactable; "PickUp" (hold) grabs it, release drops or throws it (longer
## hold = throw impulse, tap = gentle drop). While held the body is frozen kinematic
## with gravity off and chased toward hold_anchor each frame via collision-aware
## motion. Several robustness fixes are documented at their call sites: a grab "grace"
## ease-in (anti-clip on pickup), stack-wake (stops a stack floating when you pull a
## box out), safe-motion casting (no clipping through walls), character shoving while
## carrying, and a deferred slide-off so a dropped crate can't trap the player.

const PICKUP_GRACE_TIME: float = 0.25
const PICKUP_GRACE_STEP_RATIO: float = 0.25
const STACK_WAKE_RADIUS: float = 1.0
const STACK_WAKE_TIME: float = 0.6
const STACK_WAKE_NUDGE: float = 0.05

@export var player: CharacterBody3D
@export var hold_anchor: Marker3D

var held_object: Interactable = null
var _prior_gravity_scale: float = 1.0
var _prior_collision_layer: int = 1
var _prior_freeze: bool = false
var _prior_freeze_mode: RigidBody3D.FreezeMode = RigidBody3D.FREEZE_MODE_STATIC
var _release_timer_started_us: int = -1
var _last_targeted: Interactable = null
var _pickup_grace_remaining: float = 0.0
var _stack_wake_remaining: float = 0.0
var _stack_wake_origin: Vector3 = Vector3.ZERO

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
			var impulse: float = GameSettings.physics_damage.pickup_throw_impulse if held_for_s >= GameSettings.physics_damage.pickup_e_hold_threshold else GameSettings.physics_damage.pickup_drop_impulse
			_release(impulse)
		_release_timer_started_us = -1

## Per-frame carry update: refresh the highlight, run the pending stack-wake, then —
## if holding — chase hold_anchor with a clamped, collision-safe step and shove any
## characters in the path. Drops the object if it strays past the max hold distance
## (e.g. yanked through a wall).
func _physics_process(delta: float) -> void:
	_update_target_outline()
	if _stack_wake_remaining > 0.0:
		_stack_wake_remaining = maxf(0.0, _stack_wake_remaining - delta)
		_wake_nearby_bodies(_stack_wake_origin)
	if not held_object:
		return
	if not is_instance_valid(held_object):
		held_object = null
		return
	var to_anchor := hold_anchor.global_position - held_object.global_position
	if to_anchor.length() > GameSettings.physics_damage.pickup_max_hold_distance:
		_release(GameSettings.physics_damage.pickup_drop_impulse)
		return
	held_object.linear_velocity = Vector3.ZERO
	held_object.angular_velocity = Vector3.ZERO
	var follow_t := 1.0 - exp(-GameSettings.physics_damage.pickup_hold_follow_rate * delta)
	var step := to_anchor * follow_t
	var max_step := GameSettings.physics_damage.pickup_max_step_per_frame
	if _pickup_grace_remaining > 0.0:
		_pickup_grace_remaining = maxf(0.0, _pickup_grace_remaining - delta)
		var grace_t := 1.0 - (_pickup_grace_remaining / PICKUP_GRACE_TIME)
		max_step *= lerpf(PICKUP_GRACE_STEP_RATIO, 1.0, grace_t)
	step = step.limit_length(max_step)
	if step.length() < 0.0001:
		return
	var safe_step := _safe_motion(held_object, step)
	held_object.global_position += safe_step
	_push_characters_in_path(held_object, safe_step, delta)

func _push_characters_in_path(held: Interactable, motion: Vector3, delta: float) -> void:
	if not held.collision_shape or not held.collision_shape.shape:
		return
	if motion.length() < 0.0001 or delta <= 0.0:
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = held.collision_shape.shape
	query.transform = held.collision_shape.global_transform
	query.collision_mask = 2
	var exclude: Array[RID] = [held.get_rid()]
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude
	var overlaps := space_state.intersect_shape(query, 8)
	var motion_velocity := motion / delta
	for o in overlaps:
		var collider = o["collider"]
		if collider is Character:
			var c := collider as Character
			c.explosion_velocity += motion_velocity * GameSettings.physics_damage.pickup_ram_knockback_scale

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

## Grab: stash the body's prior physics state (so _release can restore it), then make
## it a weightless kinematic frozen body on the pickup collision layer, wake its
## neighbors/stack, and exclude it from player collision. on_picked_up notifies it.
func _pick_up(target: Interactable) -> void:
	held_object = target
	_pickup_grace_remaining = PICKUP_GRACE_TIME
	_stack_wake_origin = target.global_position
	_stack_wake_remaining = STACK_WAKE_TIME
	_wake_neighbors(target)
	_wake_nearby_bodies(_stack_wake_origin)
	_prior_gravity_scale = held_object.gravity_scale
	_prior_collision_layer = held_object.collision_layer
	_prior_freeze = held_object.freeze
	_prior_freeze_mode = held_object.freeze_mode
	held_object.collision_layer = GameSettings.physics_damage.pickup_held_collision_layer
	held_object.gravity_scale = 0.0
	held_object.linear_velocity = Vector3.ZERO
	held_object.angular_velocity = Vector3.ZERO
	held_object.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	held_object.freeze = true
	if player:
		player.add_collision_exception_with(held_object)
	held_object.on_picked_up(self)

func _wake_neighbors(target: Interactable) -> void:
	var contacts := target.get_colliding_bodies()
	for c in contacts:
		if c is RigidBody3D:
			(c as RigidBody3D).sleeping = false

func _wake_nearby_bodies(origin: Vector3) -> void:
	# Sphere-cast around the pickup origin and wake every RigidBody3D found,
	# applying a tiny downward nudge so they have non-zero velocity and don't
	# immediately re-sleep before gravity has a chance to take over.
	# This fixes the "stack floats" issue when grabbing a box from a stack.
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = STACK_WAKE_RADIUS
	var t := Transform3D.IDENTITY
	t.origin = origin
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = t
	query.collision_mask = 1
	var exclude: Array[RID] = []
	if held_object:
		exclude.append(held_object.get_rid())
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude
	for r in space.intersect_shape(query, 16):
		var c = r["collider"]
		if c is RigidBody3D and not (c as RigidBody3D).freeze:
			var rb := c as RigidBody3D
			rb.sleeping = false
			rb.apply_central_impulse(Vector3(0, -STACK_WAKE_NUDGE, 0))

## Drop/throw: restore the saved physics state, then launch along the look direction
## at `impulse`, inheriting the player's velocity (so throwing while running carries).
## The player-collision exception is removed on a delay (and re-checked) so the crate
## can't instantly re-collide with / trap the player on release.
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
	var lateral := global_basis.x.normalized() * GameSettings.physics_damage.pickup_drop_lateral_nudge
	var inherited := player.velocity if player else Vector3.ZERO
	dropped.linear_velocity = forward * impulse + lateral + inherited
	dropped.on_dropped()
	if player:
		var t := get_tree().create_timer(GameSettings.physics_damage.pickup_drop_exception_delay, true, true, true)
		t.timeout.connect(_restore_player_collision.bind(dropped))

## Deferred re-enable of player↔crate collision after a drop. If the crate still
## overlaps the player, nudge it away and re-check later instead — prevents the player
## getting stuck inside a crate dropped on their own head.
func _restore_player_collision(dropped: Node) -> void:
	if not is_instance_valid(player) or not is_instance_valid(dropped):
		return
	if dropped is Interactable and _crate_overlaps_player(dropped as Interactable):
		var rb := dropped as RigidBody3D
		var away := rb.global_position - player.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		away = away.normalized()
		rb.linear_velocity += away * GameSettings.physics_damage.pickup_slide_off_impulse
		var t := get_tree().create_timer(GameSettings.physics_damage.pickup_safe_recheck_delay, true, true, true)
		t.timeout.connect(_restore_player_collision.bind(dropped))
		return
	player.remove_collision_exception_with(dropped)

func _crate_overlaps_player(crate: Interactable) -> bool:
	if not crate.collision_shape or not crate.collision_shape.shape:
		return false
	if not player:
		return false
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = crate.collision_shape.shape
	query.transform = crate.collision_shape.global_transform
	query.collision_mask = player.collision_layer
	var results := space_state.intersect_shape(query, 8)
	for r in results:
		if r["collider"] == player:
			return true
	return false
