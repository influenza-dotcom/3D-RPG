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

func _ready() -> void:
	_standing_head_y = head.position.y
	var capsule := collision_shape.shape as CapsuleShape3D
	_standing_capsule_height = capsule.height
	_standing_capsule_y = collision_shape.position.y
	_crouched_capsule_height = _standing_capsule_height * GameTuning.CROUCH_HEIGHT_RATIO
	var height_delta := _standing_capsule_height - _crouched_capsule_height
	_crouched_capsule_y = _standing_capsule_y - height_delta / 2.0
	_crouched_head_y = _standing_head_y - height_delta

func _physics_process(delta: float) -> void:
	var wants := Input.is_action_pressed("Crouch")
	var target_t := 1.0 if wants or not has_room_to_stand() else 0.0
	crouch_t = move_toward(crouch_t, target_t, GameTuning.CROUCH_LERP_SPEED * delta)
	_apply(crouch_t)

func _apply(t: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = lerpf(_standing_capsule_height, _crouched_capsule_height, t)
	collision_shape.position.y = lerpf(_standing_capsule_y, _crouched_capsule_y, t)
	head.position.y = lerpf(_standing_head_y, _crouched_head_y, t)

func has_room_to_stand() -> bool:
	if crouch_t <= 0.0:
		return true
	var space := get_world_3d().direct_space_state
	var origin := player.global_position
	var clearance := _standing_capsule_height / 2.0 + GameTuning.CROUCH_CEILING_CLEARANCE
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.UP * clearance)
	query.exclude = [player]
	return space.intersect_ray(query).is_empty()
