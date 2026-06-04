class_name SprayPainter
extends Node

## The spray can's colour selection — the right-click HSV-wheel picker, its lazily-built CanvasLayer
## UI, and the mousewheel palette state — pulled out of the Attack coordinator into its own child so
## Attack stays a thin firing hub. Attack keeps the actual spray SHOT (_do_spray_paint: lob the blob,
## flash the muzzle, hiss); this owns only WHICH colour that shot uses and the picker that sets it.
##
## A custom pick from the picker wins until the mousewheel is used again, which reverts to the
## weapon's palette. Built code-side and added in Attack._ready, so off-tree (a unit-test Attack via
## .new() with no add_child) it never exists — Attack's facade then reports no open picker and paints
## white, exactly as the monolith did before the picker was ever touched.

## The Attack coordinator that owns this painter. Set right after .new(); read for the equipped weapon
## (its palette) and the holster gate. Never null on-tree (Attack wires it before add_child).
var host: Attack

## Which palette colour the mousewheel has selected for the spray. The splat look + decal cap now
## live on PaintProjectile (the blob the spray lobs), so they're not duplicated here.
var _paint_color_index: int = 0
var _custom_color: Color = Color.WHITE       ## last colour chosen in the right-click picker
var _use_custom_color: bool = false          ## a picker pick overrides the palette until the wheel is used again
var _color_picker_layer: CanvasLayer = null  ## lazily built on first right-click
var _color_picker: ColorPicker = null

func _ready() -> void:
	# Entering a conversation dismisses the spray colour picker (no-op when no picker is open).
	DialogueManager.dialogue_started.connect(_close_picker_for_dialogue)

## Spray-can mouse input (only while the spray is equipped): right-click opens a colour picker,
## mousewheel cycles the palette presets. Neither is bound to anything else in-game.
func _unhandled_input(event: InputEvent) -> void:
	var current_weapon: WeaponData = host.current_weapon
	# While the colour picker is open, ANY press except a left-click (used to pick on the wheel)
	# dismisses it instantly — a key, right-click, the wheel, anything else.
	if is_open():
		var dismiss := false
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			dismiss = true
		elif event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
			dismiss = true
		if dismiss:
			close()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if host.holstered:
		return  # weapon put away — no opening the picker or cycling the spray palette
	if not current_weapon or not current_weapon.is_spray_paint:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		open()
		get_viewport().set_input_as_handled()
		return
	var n := current_weapon.paint_colors.size()
	if n == 0:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_paint_color_index = (_paint_color_index + 1) % n
		_use_custom_color = false
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_paint_color_index = (_paint_color_index + n - 1) % n
		_use_custom_color = false
		get_viewport().set_input_as_handled()

## The colour the spray paints with: a custom pick from the picker wins, otherwise the
## mousewheel-selected palette entry (or white if the weapon defines no palette).
func resolved_color() -> Color:
	if _use_custom_color:
		return _custom_color
	var current_weapon: WeaponData = host.current_weapon
	if current_weapon and current_weapon.paint_colors.size() > 0:
		return current_weapon.paint_colors[_paint_color_index % current_weapon.paint_colors.size()]
	return Color.WHITE

func is_open() -> bool:
	return _color_picker_layer != null and _color_picker_layer.visible

func open() -> void:
	if _color_picker_layer == null:
		_build_color_picker()
	_color_picker.color = resolved_color()
	_color_picker_layer.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if _color_picker_layer:
		_color_picker_layer.visible = false
	# Don't grab the cursor back if a conversation is taking over the mouse (it stays visible for choices).
	if not DialogueManager.is_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Dismiss the spray colour picker when a conversation begins (connected to DialogueManager).
func _close_picker_for_dialogue() -> void:
	if is_open():
		close()

func _on_picker_color_changed(c: Color) -> void:
	_custom_color = c
	_use_custom_color = true

func _build_color_picker() -> void:
	_color_picker_layer = CanvasLayer.new()
	_color_picker_layer.layer = 100  # above the HUD
	add_child(_color_picker_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks off the picker fall through so right-click can close it
	_color_picker_layer.add_child(center)
	# Wrap in a panel so it reads as a proper menu, and trim the bulky sections (presets,
	# eyedropper, mode buttons) + use the compact wheel so it fits comfortably on screen.
	var panel := PanelContainer.new()
	center.add_child(panel)
	_color_picker = ColorPicker.new()
	_color_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	_color_picker.presets_visible = false
	_color_picker.sampler_visible = false
	_color_picker.color_modes_visible = false
	_color_picker.sliders_visible = false
	_color_picker.hex_visible = false
	_color_picker.color = resolved_color()
	_color_picker.color_changed.connect(_on_picker_color_changed)
	panel.add_child(_color_picker)
