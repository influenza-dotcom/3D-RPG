extends Node

# InputManager — wraps Input action lookups so action-name strings live in one
# place. Designers can rebind actions in project.godot and only the vars here
# need to be updated (or, in future, the InputMap UI directly).
#
# Action names mirror the current InputMap in project.godot. If you change an
# action name, change it here AND in project.godot.

var action_forward: StringName = &"forward"
var action_backward: StringName = &"backward"
var action_left: StringName = &"left"
var action_right: StringName = &"right"
var action_jump: StringName = &"jump"
var action_crouch: StringName = &"Crouch"
var action_attack: StringName = &"Attack"
var action_reload: StringName = &"Reload"
var action_zoom: StringName = &"Zoom"
var action_pickup: StringName = &"PickUp"
var action_light: StringName = &"Light"
var action_grapple: StringName = &"Grapple"
var action_weapon_slot_1: StringName = &"Weapon Slot 1"
var action_weapon_slot_2: StringName = &"Weapon Slot 2"
var action_weapon_slot_3: StringName = &"Weapon Slot 3"
var action_weapon_slot_4: StringName = &"Weapon Slot 4"
var action_weapon_slot_5: StringName = &"Weapon Slot 5"
var action_weapon_slot_6: StringName = &"Weapon Slot 6"


func is_action_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action)

func is_action_just_pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action)

func is_action_just_released(action: StringName) -> bool:
	return Input.is_action_just_released(action)

func get_vector(neg_x: StringName, pos_x: StringName, neg_y: StringName, pos_y: StringName) -> Vector2:
	return Input.get_vector(neg_x, pos_x, neg_y, pos_y)

func get_movement_vector() -> Vector2:
	return Input.get_vector(action_left, action_right, action_forward, action_backward)
