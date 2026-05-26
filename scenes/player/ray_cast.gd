extends RayCast3D

@export var player: CharacterBody3D
@export var joint: Generic6DOFJoint3D
@export var hold_distance: float = 1.0
var held_object: Interactable = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("PickUp"):
		if is_colliding() and not held_object:
			var interactable := get_collider() as Interactable
			if interactable:
				pick_up(interactable)
		elif held_object:
			drop()

func pick_up(interactable: Interactable) -> void:
	held_object = interactable
	held_object.global_position += Vector3(0,0.20,0) 
	held_object.on_picked_up()

	held_object.sleeping = false
	held_object.freeze = false
	player.add_collision_exception_with(held_object)

	joint.node_a = player.get_path()
	joint.node_b = held_object.get_path()

	joint.global_position = global_position - global_basis.z * hold_distance
	joint.global_basis = global_basis

func drop() -> void:
	if not is_instance_valid(held_object):
		held_object = null
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		return

	if player and held_object:
		player.remove_collision_exception_with(held_object)

	joint.node_a = NodePath()
	joint.node_b = NodePath()

	held_object.on_dropped()
	held_object = null
