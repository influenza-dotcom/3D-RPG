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
var action_weapon_slot_7: StringName = &"Weapon Slot 7"


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

func _ready() -> void:
	_add_default_controller_bindings()

## Controller defaults, added in CODE so we don't hand-author InputEvent objects in project.godot. Left
## stick -> movement (so Input.get_vector picks it up automatically); right stick -> a new look_* action
## set read by MouseInput; face buttons / triggers / d-pad cover the rest. Each add is dup-guarded, so
## re-applying (or a future rebind layer) is safe.
func _add_default_controller_bindings() -> void:
	for a in [&"look_left", &"look_right", &"look_up", &"look_down"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
	_bind_axis(action_left, JOY_AXIS_LEFT_X, -1.0)
	_bind_axis(action_right, JOY_AXIS_LEFT_X, 1.0)
	_bind_axis(action_forward, JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis(action_backward, JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis(&"look_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_axis(&"look_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_axis(&"look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_axis(&"look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_bind_button(action_jump, JOY_BUTTON_A)
	_bind_button(action_crouch, JOY_BUTTON_B)
	_bind_button(action_reload, JOY_BUTTON_X)
	_bind_button(action_pickup, JOY_BUTTON_Y)
	_bind_button(action_light, JOY_BUTTON_LEFT_STICK)
	_bind_button(action_grapple, JOY_BUTTON_RIGHT_STICK)
	_bind_axis(action_attack, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_axis(action_zoom, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_bind_button(action_weapon_slot_1, JOY_BUTTON_DPAD_UP)
	_bind_button(action_weapon_slot_2, JOY_BUTTON_DPAD_RIGHT)
	_bind_button(action_weapon_slot_3, JOY_BUTTON_DPAD_DOWN)
	_bind_button(action_weapon_slot_4, JOY_BUTTON_DPAD_LEFT)

func _bind_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button:
			return  # already bound
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _bind_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		var m := e as InputEventJoypadMotion
		if m != null and m.axis == axis and signf(m.axis_value) == signf(value):
			return  # already bound
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
