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
## Weapon slots 1-10 (keys 1-0): consumed by the HOTBAR (scripts/ui/hotbar.gd) — pressing one equips the
## weapon / uses the consumable auto-assigned to that slot. (Slots 1-7 are the original weapon-switch
## actions, revived; 8-10 were added with the hotbar. The Tab inventory remains the full bag UI.)
var action_weapon_slot_1: StringName = &"Weapon Slot 1"
var action_weapon_slot_2: StringName = &"Weapon Slot 2"
var action_weapon_slot_3: StringName = &"Weapon Slot 3"
var action_weapon_slot_4: StringName = &"Weapon Slot 4"
var action_weapon_slot_5: StringName = &"Weapon Slot 5"
var action_weapon_slot_6: StringName = &"Weapon Slot 6"
var action_weapon_slot_7: StringName = &"Weapon Slot 7"
var action_weapon_slot_8: StringName = &"Weapon Slot 8"
var action_weapon_slot_9: StringName = &"Weapon Slot 9"
var action_weapon_slot_10: StringName = &"Weapon Slot 10"
## The ten hotbar actions in slot order (index 0 = key "1" … index 9 = key "0") — the Hotbar iterates this.
var hotbar_actions: Array[StringName] = [
	&"Weapon Slot 1", &"Weapon Slot 2", &"Weapon Slot 3", &"Weapon Slot 4", &"Weapon Slot 5",
	&"Weapon Slot 6", &"Weapon Slot 7", &"Weapon Slot 8", &"Weapon Slot 9", &"Weapon Slot 10",
]
## Opens/closes the backpack (Tab). The full bag UI; the hotbar covers the quick-equip keys.
var action_inventory: StringName = &"Inventory"
## Grab-to-throw (Z): picks up the aimed throwable to CARRY/THROW it. Distinct from PickUp/Interact (E),
## which adds a dual item to the inventory instead — so an item that's both takeable AND throwable uses E
## to stash and Z to throw.
var action_throw: StringName = &"Throw"


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

var using_controller: bool = false  ## true when the last significant input was a gamepad — drives haptics

func _ready() -> void:
	_add_default_controller_bindings()

## Track whether the player is on a gamepad right now, so screen shake can rumble it (ScreenShake._rumble).
## Stick drift is ignored (only past-half-deflection counts); any key/mouse input flips back to false.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		using_controller = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		using_controller = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		using_controller = false

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

## The display label for `action`'s CURRENT binding ("E", "Mouse 1", ...): prefer the keyboard/mouse event
## (what's usually rebound), else the first event. Read LIVE from the InputMap each call, so a rebind shows
## immediately. The CANONICAL copy of the rebind-button label logic (OptionsMenu delegates here); also
## drives the interact key-hints on the hover readout ("[E] Talk to Kyle", "[Z] Pick Up").
func display_key(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "(none)"
	var events := InputMap.action_get_events(action)
	for e in events:
		if e is InputEventKey or e is InputEventMouseButton:
			return event_label(e)
	if not events.is_empty():
		return event_label(events[0])
	return "(unbound)"

## A short human label for one InputEvent binding ("E", "Mouse 1", "Pad 3", "Axis 5").
func event_label(e: InputEvent) -> String:
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	if e is InputEventMouseButton:
		return "Mouse %d" % (e as InputEventMouseButton).button_index
	if e is InputEventJoypadButton:
		return "Pad %d" % (e as InputEventJoypadButton).button_index
	if e is InputEventJoypadMotion:
		return "Axis %d" % (e as InputEventJoypadMotion).axis
	return "?"
