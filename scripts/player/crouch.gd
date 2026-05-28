class_name Crouch
extends Node3D

@export var player: CharacterBody3D
@export var head: Node3D
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
	var wants := Input.is_action_pressed("Crouch") and not has_box_overhead()
	var target_t := 1.0 if wants or not has_room_to_stand() else 0.0
	crouch_t = move_toward(crouch_t, target_t, GameSettings.player_crouch.lerp_speed * delta)
	_apply(crouch_t)

func _apply(t: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = lerpf(_standing_capsule_height, _crouched_capsule_height, t)
	collision_shape.position.y = lerpf(_standing_capsule_y, _crouched_capsule_y, t)
	head.position.y = lerpf(_standing_head_y, _crouched_head_y, t)

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
	# Block crouching if an Interactable is resting on / just above the player's
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
		if r["collider"] is Interactable:
			return true
	return false
