class_name Interactable
extends RigidBody3D

func on_picked_up():
	if self is RigidBody3D:
		pass#freeze = true

func on_dropped():
	if self is RigidBody3D:
		pass#freeze = false
