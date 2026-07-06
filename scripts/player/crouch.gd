class_name Crouch
extends Node3D

## The player CharacterBody3D this crouch drives — its transform, collision_mask and RID feed the stand-up / overhead-box clearance probes. Wire to the player root.
@export var player: CharacterBody3D
## The camera/head node lowered while crouched (its local Y lerps from standing to crouched height). Wire to the player's head pivot.
@export var head: Node3D
## The player's capsule CollisionShape3D, shrunk while crouched (its height + Y lerp down). Wire to the player's body collider; its shape is duplicated so other instances aren't affected.
@export var collision_shape: CollisionShape3D

var crouch_t: float = 0.0

var _standing_head_y: float
var _standing_capsule_height: float
var _standing_capsule_y: float
var _crouched_head_y: float
var _crouched_capsule_height: float
var _crouched_capsule_y: float
var _stand_probe_shape: CapsuleShape3D
var _overhead_probe_shape: SphereShape3D

func _ready() -> void:
	_standing_head_y = head.position.y
	collision_shape.shape = collision_shape.shape.duplicate()
	var capsule := collision_shape.shape as CapsuleShape3D
	_standing_capsule_height = capsule.height
	_standing_capsule_y = collision_shape.position.y
	_crouched_capsule_height = _standing_capsule_height * GameSettings.player_crouch.height_ratio
	var height_delta := _standing_capsule_height - _crouched_capsule_height
	_crouched_capsule_y = _standing_capsule_y - height_delta / 2.0
	_crouched_head_y = _standing_head_y - height_delta

	_stand_probe_shape = CapsuleShape3D.new()
	_stand_probe_shape.radius = capsule.radius
	_stand_probe_shape.height = _standing_capsule_height

	_overhead_probe_shape = SphereShape3D.new()
	_overhead_probe_shape.radius = capsule.radius * 0.9

func _physics_process(delta: float) -> void:
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return  # frozen during a conversation or while a modal UI is open — can't crouch or uncrouch
	var wants := Input.is_action_pressed("Crouch") and not has_box_overhead()
	var target_t := 1.0 if wants or not has_room_to_stand() else 0.0
	crouch_t = move_toward(crouch_t, target_t, GameSettings.player_crouch.lerp_speed * delta)
	_apply(crouch_t)

func _apply(t: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = lerpf(_standing_capsule_height, _crouched_capsule_height, t)
	collision_shape.position.y = lerpf(_standing_capsule_y, _crouched_capsule_y, t)
	head.position.y = lerpf(_standing_head_y, _crouched_head_y, t)

## Snap fully upright THIS FRAME (crouch_t -> 0 + restore the standing capsule height/Y and head Y). The
## player's in-place revive (Player._respawn_at_checkpoint) calls this after freezing crouch on death, so a
## death taken while crouched doesn't respawn you with a shrunk hitbox / lowered camera. Mirrors the
## WallClimb.reset() / Slide.end() latch-clearing the revive already does; _physics_process resumes from a
## clean standing pose. Uses the cached _standing_* from _ready (the revive doesn't rebuild this node).
func reset() -> void:
	crouch_t = 0.0
	_apply(0.0)

func has_room_to_stand() -> bool:
	if crouch_t <= 0.0:
		return true
	var space := player.get_world_3d().direct_space_state
	var probe_transform := player.global_transform
	probe_transform.origin.y += _standing_capsule_y + GameSettings.player_crouch.ceiling_clearance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_probe_shape
	query.transform = probe_transform
	query.exclude = [player.get_rid()]
	query.collision_mask = player.collision_mask
	return space.intersect_shape(query, 1).is_empty()

func has_box_overhead() -> bool:
	# Block crouching if an Throwable is resting on / just above the player's
	# head. Prevents the camera-clipping issue when the player crouches under a
	# crate that's sitting on top of them.
	if not player:
		return false
	var space := player.get_world_3d().direct_space_state
	var probe_transform := player.global_transform
	probe_transform.origin.y += _standing_head_y + 0.15
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _overhead_probe_shape
	query.transform = probe_transform
	query.exclude = [player.get_rid()]
	query.collision_mask = player.collision_mask
	for r in space.intersect_shape(query, 4):
		if r["collider"] is Throwable:
			return true
	return false
