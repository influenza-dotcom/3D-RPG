extends CanvasLayer
## OptionsMenu — the Settings overlay, built entirely in code and registered as an autoload so ONE
## instance serves both the start menu and in-game play, surviving scene changes. Toggled with ui_cancel
## (Escape / controller B).
##
## It does NOT pause the SceneTree — the world keeps simulating, as requested. To stop menu clicks from
## leaking into gameplay (poll-based input ignores GUI focus), it instead FREEZES the player subtree via
## process_mode while open, and releases the mouse for the UI; both are restored on close. Every control
## data-binds to the Settings autoload, so this file only ever reads/writes Settings — it never reaches
## into gameplay systems.

signal opened
signal closed

const PANEL_MARGIN := 0.07  ## fraction of the screen left as a border around the panel (adapts to any res)

var _root: Control
var _tabs: TabContainer
var _first_focus: Control
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

## Actions offered on the Controls tab (action name -> display label).
const REBINDABLE: Array[Dictionary] = [
	{"action": &"forward", "label": "Move Forward"},
	{"action": &"backward", "label": "Move Backward"},
	{"action": &"left", "label": "Move Left"},
	{"action": &"right", "label": "Move Right"},
	{"action": &"jump", "label": "Jump"},
	{"action": &"Crouch", "label": "Crouch"},
	{"action": &"Attack", "label": "Attack"},
	{"action": &"Zoom", "label": "Aim"},
	{"action": &"Reload", "label": "Reload"},
	{"action": &"PickUp", "label": "Interact"},
	{"action": &"Light", "label": "Laser / Light"},
	{"action": &"Grapple", "label": "Grapple"},
	{"action": &"NightVision", "label": "Night Vision"},
]
var _rebinding_action: StringName = &""
var _rebind_button: Button = null

func _ready() -> void:
	layer = 128                                  # above the HUD (default layer 1)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working regardless of any pause
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

# ---------------------------------------------------------------------------------------------------
# Open / close — release the mouse + freeze the player, no SceneTree pause
# ---------------------------------------------------------------------------------------------------

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	if _is_open or DialogueManager.is_active():
		return  # don't fight the dialogue UI for the mouse / Escape
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_freeze_player(true)
	_root.visible = true
	if is_instance_valid(_first_focus):
		_first_focus.grab_focus()
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	_freeze_player(false)
	Input.mouse_mode = _prev_mouse_mode
	closed.emit()

## Non-pausing, Dark Souls style: the menu NO LONGER freezes the player — the world AND the player keep
## running, and the player stays vulnerable (enemies can still hit you while you menu). Player CONTROL is
## suppressed instead, gated on OptionsMenu.is_open() in the player (move/jump), MouseInput (fire) and
## ScopeIn (aim), so menu clicks/keys don't drive the character.
func _freeze_player(_frozen: bool) -> void:
	pass

## The human player, not a companion (companions join &"Player" for targeting but are NPCs).
func _find_real_player() -> Node:
	for p in get_tree().get_nodes_in_group(&"Player"):
		if not (p is NPC):
			return p
	return null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# UI construction (code-built so it needs no scene authoring)
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so nothing falls through behind the menu
	var theme := Theme.new()
	theme.default_font_size = 13
	_root.theme = theme
	add_child(_root)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.6)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dimmer)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Inset by a fraction of the screen so the panel fills most of it at ANY resolution (low-res viewport).
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)

	_build_video_tab()
	_build_audio_tab()
	_build_game_tab()
	_build_controls_tab()
	_build_accessibility_tab()

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	bottom.add_child(close_btn)
	var quit_btn := Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.pressed.connect(_on_quit)
	bottom.add_child(quit_btn)

func _build_video_tab() -> void:
	var tab := _add_tab("Video")
	var mode_ob := _option_row(tab, "Window Mode", ["Windowed", "Borderless", "Fullscreen"],
		Settings.window_mode, Settings.set_window_mode)
	_first_focus = mode_ob  # first interactive control — focused on open for keyboard/controller nav
	var res_items: Array[String] = []
	for r in Settings.RESOLUTIONS:
		res_items.append("%d x %d" % [r.x, r.y])
	var res_sel: int = Settings.RESOLUTIONS.find(Settings.windowed_size)
	_option_row(tab, "Resolution", res_items, maxi(res_sel, 0), _on_resolution_selected)
	_check_row(tab, "V-Sync", Settings.vsync, Settings.set_vsync)
	_slider_row(tab, "Max FPS", 0, 360, 1, Settings.max_fps,
		func(v): Settings.set_max_fps(int(v)),
		func(v): return "Uncapped" if int(v) == 0 else str(int(v)))
	_slider_row(tab, "Render Scale", Settings.RENDER_SCALE_MIN, Settings.RENDER_SCALE_MAX, 0.05, Settings.render_scale,
		func(v): Settings.set_render_scale(v),
		func(v): return "%d%%" % int(round(v * 100.0)))
	_slider_row(tab, "Field of View", Settings.FOV_MIN, Settings.FOV_MAX, 1, Settings.fov,
		func(v): Settings.set_fov(v),
		func(v): return str(int(v)))

func _build_audio_tab() -> void:
	var tab := _add_tab("Audio")
	var labels := {&"Master": "Master", &"music": "Music", &"sfx": "Effects", &"ambient": "Ambient", &"voice": "Voice"}
	for bus in Settings.VOLUME_BUSES:
		var b: StringName = bus
		# Bind the bus (reliable value capture) rather than a lambda closing over the loop variable —
		# GDScript loop-var capture made every audio slider target the LAST bus (voice), so none worked.
		_slider_row(tab, String(labels.get(b, String(b))), 0.0, 1.0, 0.01, Settings.get_volume(b),
			_set_volume_for.bind(b),
			func(v): return "%d%%" % int(round(v * 100.0)))

## Audio slider setter: bound per-bus in _build_audio_tab so each slider controls its own bus.
func _set_volume_for(value: float, bus: StringName) -> void:
	Settings.set_volume(bus, value)

func _build_game_tab() -> void:
	var tab := _add_tab("Game")
	_slider_row(tab, "Mouse Sensitivity", Settings.SENS_MIN, Settings.SENS_MAX, 0.0001, Settings.mouse_sensitivity,
		func(v): Settings.set_mouse_sensitivity(v),
		func(v): return str(int(round(remap(v, Settings.SENS_MIN, Settings.SENS_MAX, 1.0, 100.0)))))
	_slider_row(tab, "Controller Look", 0.5, 10.0, 0.1, Settings.controller_look_sensitivity,
		func(v): Settings.set_controller_look_sensitivity(v),
		func(v): return "%.1f" % v)
	_check_row(tab, "Invert Look Y", Settings.invert_look_y, Settings.set_invert_look_y)

func _build_controls_tab() -> void:
	var tab := _add_tab("Controls")
	var note := Label.new()
	note.text = "Click a binding, then press a key or button (Esc cancels)."
	note.add_theme_font_size_override("font_size", 11)
	note.modulate = Color(1.0, 1.0, 1.0, 0.6)
	tab.add_child(note)
	for entry in REBINDABLE:
		_rebind_row(tab, entry["action"], String(entry["label"]))

func _rebind_row(parent: VBoxContainer, action: StringName, label_text: String) -> void:
	var btn := Button.new()
	btn.text = _binding_label(action)
	btn.pressed.connect(_begin_rebind.bind(action, btn))
	_row(parent, label_text, btn)

## The current binding shown on a rebind button: prefer the keyboard/mouse event (what's usually
## rebound), else the first event.
func _binding_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "(none)"
	var events := InputMap.action_get_events(action)
	for e in events:
		if e is InputEventKey or e is InputEventMouseButton:
			return _event_label(e)
	if not events.is_empty():
		return _event_label(events[0])
	return "(unbound)"

func _event_label(e: InputEvent) -> String:
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	if e is InputEventMouseButton:
		return "Mouse %d" % (e as InputEventMouseButton).button_index
	if e is InputEventJoypadButton:
		return "Pad %d" % (e as InputEventJoypadButton).button_index
	if e is InputEventJoypadMotion:
		return "Axis %d" % (e as InputEventJoypadMotion).axis
	return "?"

func _begin_rebind(action: StringName, btn: Button) -> void:
	_rebinding_action = action
	_rebind_button = btn
	btn.text = "Press a key/button..."

## While a rebind is armed, capture the next key / mouse-button / gamepad-button PRESS as the new binding
## (Esc cancels). Runs in _input (before the GUI) so the captured press doesn't also click something.
func _input(event: InputEvent) -> void:
	if _rebinding_action == &"":
		return
	var captured: InputEvent = null
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		captured = event
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		captured = event
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		captured = event
	if captured == null:
		return
	get_viewport().set_input_as_handled()
	if not (captured is InputEventKey and (captured as InputEventKey).physical_keycode == KEY_ESCAPE):
		Settings.rebind_action(_rebinding_action, _normalize_event(captured))
	_end_rebind()

## Strip an event down to just its binding identity (no position / pressed-state noise) for storage.
func _normalize_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = (event as InputEventKey).physical_keycode
		return k
	if event is InputEventMouseButton:
		var mb := InputEventMouseButton.new()
		mb.button_index = (event as InputEventMouseButton).button_index
		return mb
	if event is InputEventJoypadButton:
		var jb := InputEventJoypadButton.new()
		jb.button_index = (event as InputEventJoypadButton).button_index
		return jb
	return event

func _end_rebind() -> void:
	if _rebind_button != null:
		_rebind_button.text = _binding_label(_rebinding_action)
	_rebinding_action = &""
	_rebind_button = null

func _build_accessibility_tab() -> void:
	var tab := _add_tab("Accessibility")
	_slider_row(tab, "Screen Shake", 0.0, 2.0, 0.05, Settings.screen_shake_scale,
		func(v): Settings.set_screen_shake_scale(v),
		func(v): return "%d%%" % int(round(v * 100.0)))
	_check_row(tab, "Hit Stop", Settings.hitstop_enabled, Settings.set_hitstop_enabled)
	_option_row(tab, "Colorblind Filter", ["Off", "Protanopia", "Deuteranopia", "Tritanopia"],
		Settings.colorblind_mode, Settings.set_colorblind_mode)
	_check_row(tab, "Colorblind-Safe Cues", Settings.colorblind_safe_cues, Settings.set_colorblind_safe_cues)

# ---------------------------------------------------------------------------------------------------
# Row / control builders
# ---------------------------------------------------------------------------------------------------

## A scrollable tab page (overflow scrolls rather than clipping at low resolutions). Returns the VBox
## rows are added to; the tab title is the page node's name.
func _add_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	scroll.add_child(margin)
	_tabs.add_child(scroll)
	return v

## A labelled row: a fixed-width name on the left, the control filling the rest.
func _row(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 130
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	parent.add_child(h)

## Slider row with a live, right-aligned value readout. `setter` applies the value to Settings;
## `formatter` turns the raw value into display text. Value is set BEFORE connecting so the initial
## assignment doesn't fire the setter (and re-save) during construction.
func _slider_row(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step: float,
		value: float, setter: Callable, formatter: Callable) -> void:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 130
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size.x = 120
	h.add_child(s)
	var val := Label.new()
	val.custom_minimum_size.x = 56
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.text = formatter.call(value)
	h.add_child(val)
	s.value_changed.connect(_on_slider_changed.bind(val, setter, formatter))
	parent.add_child(h)

func _on_slider_changed(value: float, val_label: Label, setter: Callable, formatter: Callable) -> void:
	val_label.text = formatter.call(value)
	setter.call(value)

## Dropdown row. `on_select` takes the selected index. Selection set BEFORE connecting (same reason).
func _option_row(parent: VBoxContainer, label_text: String, items: Array, selected: int, on_select: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(str(it))
	ob.selected = clampi(selected, 0, items.size() - 1)
	ob.item_selected.connect(on_select)
	_row(parent, label_text, ob)
	return ob

func _check_row(parent: VBoxContainer, label_text: String, pressed: bool, on_toggle: Callable) -> void:
	var c := CheckButton.new()
	c.button_pressed = pressed
	c.toggled.connect(on_toggle)
	_row(parent, label_text, c)

func _on_resolution_selected(index: int) -> void:
	Settings.set_windowed_size(Settings.RESOLUTIONS[index])

func _on_quit() -> void:
	get_tree().quit()
