extends CanvasLayer
## OptionsMenu — the Settings overlay, registered as an autoload so ONE instance serves both the start menu
## and in-game play, surviving scene changes. Toggled with ui_cancel (Escape / controller B).
##
## The rows are DATA: every tab is generated from resources/settings/SettingsCatalog.tres (an ordered list
## of SettingSpec), so adding an option is "add a typed var + setter to Settings.gd, then add one row to the
## catalog" — never hand-wiring UI here. This file only reads/writes the Settings autoload, never gameplay.
## Each control STAGES its edit into _pending and nothing touches Settings until APPLY (Revert / reopening
## drops them). (Key rebinds are the one exception — they bind live, since the key-press itself confirms.)
##
## It does NOT pause the SceneTree — the world keeps simulating, as requested. To stop menu clicks from
## leaking into gameplay (poll-based input ignores GUI focus), the player's CONTROL is suppressed instead
## (gated on OptionsMenu.is_open() in the player / MouseInput / ScopeIn) and the mouse is released for the UI.

signal opened
signal closed

const PANEL_MARGIN := 0.07  ## fraction of the screen left as a border around the panel (adapts to any res)

## The declarative source of truth for every row + tab (and which actions are rebindable). Authored in the
## inspector; consumed only here. See resources/settings/SettingSpec.gd for the model.
const CATALOG := preload("res://resources/settings/SettingsCatalog.tres")
## The rebindable input actions, as data. Its keybind_specs() generates the Controls tab's section headers +
## rebind rows (as SettingSpecs), appended to CATALOG.specs in _rebuild_tabs. See scripts/input/action_spec.gd.
const ACTION_CATALOG := preload("res://resources/input/ActionCatalog.tres")

var _root: Control
var _tabs: TabContainer
var _first_focus: Control
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
## Staged settings edits (setter Callable -> pending value); flushed to Settings on Apply, dropped on Revert.
var _pending: Dictionary = {}
var _apply_btn: Button = null
var _main_menu_btn: Button = null  ## "Main Menu" (return to start screen) — only shown in-game (see open())

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
	if _is_open or DialogueManager.is_active() or InventoryScreen.is_open() or LootScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open() or LevelUpScreen.is_open() or StatsScreen.is_open():
		return  # don't fight another modal for the mouse / Escape (no stacked overlays — symmetric with every screen's own gate)
	_is_open = true
	# Rebuild the tabs fresh from the CURRENT Settings each open, dropping any edits left unapplied last time.
	_pending.clear()
	_rebuild_tabs()
	_refresh_apply_state()
	# Only offer "Main Menu" while in-game (a player exists) — at the start menu it'd be a redundant reload.
	if is_instance_valid(_main_menu_btn):
		_main_menu_btn.visible = _find_real_player() != null
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
## ScopeIn (aim) — the SAME gates also check InventoryScreen / LootScreen — so menu clicks/keys (left-click
## is also Attack) don't drive the character while any overlay is up.
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
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/sliders/tabs/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	add_child(_root)

	_root.add_child(MenuStyle.make_dim())

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

	var title := MenuStyle.make_title("Settings")
	vbox.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)

	_rebuild_tabs()

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)
	_apply_btn = Button.new()
	_apply_btn.text = "Apply"
	_apply_btn.pressed.connect(_apply_pending)
	bottom.add_child(_apply_btn)
	var revert_btn := Button.new()
	revert_btn.text = "Revert"
	revert_btn.pressed.connect(_revert)
	bottom.add_child(revert_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	bottom.add_child(close_btn)
	_main_menu_btn = Button.new()
	_main_menu_btn.text = "Main Menu"
	_main_menu_btn.pressed.connect(_on_main_menu)
	bottom.add_child(_main_menu_btn)
	var quit_btn := Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.pressed.connect(_on_quit)
	bottom.add_child(quit_btn)
	_refresh_apply_state()

# ---------------------------------------------------------------------------------------------------
# Catalog-driven tab construction — every row is emitted from a SettingSpec
# ---------------------------------------------------------------------------------------------------

## (Re)build the tab pages from the catalog + CURRENT Settings — on first build, on open, and on Revert — so
## the controls always reflect what's actually applied. Tabs are created in the order their first spec is
## seen; rows are emitted in spec order. _first_focus = the first focusable control (for keyboard/controller).
func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_first_focus = null
	var pages: Dictionary = {}  # tab name (StringName) -> its VBoxContainer
	# The Controls tab's rebind rows are GENERATED from the ActionCatalog (section headers + keybind rows) and
	# appended after the hand-authored specs, so they land on the Controls page after its hint row.
	var specs: Array = CATALOG.specs.duplicate()
	specs.append_array(ACTION_CATALOG.keybind_specs())
	for spec in specs:
		# specs is Array[SettingSpec], but GDScript types an extracted element as the script resource and
		# won't cast/unify it to the `SettingSpec` class_name — so the row builders take the spec as Variant
		# and read its @export fields dynamically (the SettingSpec.Widget / .ValueFormat enums still resolve).
		if spec == null:
			continue
		var page: VBoxContainer = pages.get(spec.tab)
		if page == null:
			page = _add_tab(String(spec.tab))
			pages[spec.tab] = page
		var control := _emit_row(page, spec)
		if _first_focus == null and control != null:
			_first_focus = control

## Emit ONE row for `spec` into its tab page and return the focusable control it created (or null for
## headers / notes). Toggle/Slider/Dropdown bind to a Settings getter+setter by name; Section is a header;
## Keybind routes to the live rebinder; Custom delegates to a named builder for the non-value-binding rows.
func _emit_row(parent: VBoxContainer, spec: Variant) -> Control:
	match spec.control:
		SettingSpec.Widget.SECTION:
			_rebind_section(parent, spec.label)
			return null
		SettingSpec.Widget.TOGGLE:
			return _check_row(parent, spec.label, bool(_spec_current(spec)), _spec_setter(spec))
		SettingSpec.Widget.SLIDER:
			return _slider_row(parent, spec.label, spec.min_value, spec.max_value, spec.step,
				float(_spec_current(spec)), _spec_setter(spec), _formatter_for(spec.value_format))
		SettingSpec.Widget.DROPDOWN:
			return _option_row(parent, spec.label, Array(spec.options), int(_spec_current(spec)), _spec_setter(spec))
		SettingSpec.Widget.KEYBIND:
			_rebind_row(parent, spec.rebind_action, spec.label)
			return null
		SettingSpec.Widget.CUSTOM:
			return call(spec.custom_handler, parent, spec) as Control
	return null

## The control's CURRENT value, read through the Settings typed API. A `bind` (the volume bus) is the leading
## argument to a method getter (Settings.get_volume(bus)); otherwise the getter names a property (Settings.fov).
func _spec_current(spec: Variant) -> Variant:
	if spec.bind != &"":
		return Settings.call(spec.getter, spec.bind)
	return Settings.get(spec.getter)

## A Callable that applies this spec's value to Settings — staged through _pending, committed on Apply. A
## `bind` becomes the LEADING arg so set_volume(bus, value) keeps its order; `as_int` narrows the slider's
## float for an int setter (Max FPS). Everything else is a direct Callable onto the named Settings setter.
func _spec_setter(spec: Variant) -> Callable:
	var m: StringName = spec.setter
	if spec.bind != &"":
		var lead: StringName = spec.bind
		return func(v): Settings.call(m, lead, v)
	if spec.as_int:
		return func(v): Settings.call(m, int(v))
	return Callable(Settings, m)

## The slider readout formatter for a SettingSpec.ValueFormat — the per-row formatter lambdas, made data.
func _formatter_for(fmt: int) -> Callable:
	match fmt:
		SettingSpec.ValueFormat.PERCENT:
			return func(v): return "%d%%" % int(round(v * 100.0))
		SettingSpec.ValueFormat.INTEGER:
			return func(v): return str(int(v))
		SettingSpec.ValueFormat.UNCAPPED:
			return func(v): return "Uncapped" if int(v) == 0 else str(int(v))
		SettingSpec.ValueFormat.SENSITIVITY:
			return func(v): return str(int(round(remap(v, Settings.SENS_MIN, Settings.SENS_MAX, 1.0, 100.0))))
		SettingSpec.ValueFormat.ONE_DECIMAL:
			return func(v): return "%.1f" % v
		_:
			return func(v): return str(v)

# --- Custom row builders (the few rows that aren't pure value-binding; named by spec.custom_handler) ---

## Resolution dropdown: items + selection derive from Settings.RESOLUTIONS / windowed_size, and the staged
## setter maps the chosen index back to a Vector2i (_on_resolution_selected). Driven by a Custom spec so it
## still lives in the catalog's order, but the index<->Vector2i mapping stays code.
func _emit_resolution(parent: VBoxContainer, _spec: Variant) -> Control:
	var res_items: Array[String] = []
	for r in Settings.RESOLUTIONS:
		res_items.append("%d x %d" % [r.x, r.y])
	var res_sel: int = Settings.RESOLUTIONS.find(Settings.windowed_size)
	return _option_row(parent, _spec.label, res_items, maxi(res_sel, 0), _on_resolution_selected)

## A non-interactive hint line (the Controls "click a binding…" note). Returns null — not a focus target.
func _emit_hint(parent: VBoxContainer, spec: Variant) -> Control:
	parent.add_child(MenuStyle.make_hint(spec.label))
	return null

## Music-folder picker (Audio tab): a button showing the player's chosen folder (or the per-radio default) that
## opens a directory FileDialog, plus a "Default" reset. IMMEDIATE — like the old account row, it writes
## Settings directly (set_music_folder persists) rather than staging through Apply, since a folder isn't a
## revertible slider. Radios pick the new folder up on their next turn-on.
func _emit_music_folder(parent: VBoxContainer, spec: Variant) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var path_btn := Button.new()
	path_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_btn.clip_text = true
	path_btn.text = _music_folder_label()
	path_btn.pressed.connect(_open_music_folder_dialog.bind(path_btn))
	box.add_child(path_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Default"
	clear_btn.pressed.connect(_clear_music_folder.bind(path_btn))
	box.add_child(clear_btn)
	_row(parent, spec.label, box)
	return path_btn

## The picker button's caption: the chosen folder, or a "using each radio's own folder" note when unset.
func _music_folder_label() -> String:
	var f: String = Settings.music_folder
	return f if not f.is_empty() else "Default (each radio's own folder)"

## Open a native directory picker; on a pick, persist it + refresh the button. The dialog is one-shot (freed on
## select/cancel) so the menu never accumulates hidden dialogs.
func _open_music_folder_dialog(path_btn: Button) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = "Choose a music folder"
	if not Settings.music_folder.is_empty():
		dlg.current_dir = Settings.music_folder
	add_child(dlg)
	dlg.dir_selected.connect(func(d: String) -> void:
		Settings.set_music_folder(d)
		path_btn.text = _music_folder_label()
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered(Vector2i(720, 480))

## "Default" reset: clear the override so radios revert to their own curated res:// folders.
func _clear_music_folder(path_btn: Button) -> void:
	Settings.set_music_folder("")
	path_btn.text = _music_folder_label()

# ---------------------------------------------------------------------------------------------------
# Keybind rebinding (binds LIVE — the key-press itself is the confirmation)
# ---------------------------------------------------------------------------------------------------

## A section header in the Controls list (Movement / Combat / Interface / Hotbar) so a binding is easy to find.
func _rebind_section(parent: VBoxContainer, title: String) -> void:
	var l := Label.new()
	l.text = title.to_upper()
	l.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	l.add_theme_color_override(&"font_color", MenuStyle.accent())
	parent.add_child(l)

func _rebind_row(parent: VBoxContainer, action: StringName, label_text: String) -> void:
	var btn := Button.new()
	btn.text = _binding_label(action)
	btn.pressed.connect(_begin_rebind.bind(action, btn))
	_row(parent, label_text, btn)

## The current binding shown on a rebind button — the canonical logic now lives on InputManager
## (display_key / event_label), shared with the hover readout's interact key-hints ("[E] Talk to Kyle").
func _binding_label(action: StringName) -> String:
	return InputManager.display_key(action)

func _event_label(e: InputEvent) -> String:
	return InputManager.event_label(e)

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
## assignment doesn't fire the setter (and re-save) during construction. Returns the slider (focus target).
func _slider_row(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step: float,
		value: float, setter: Callable, formatter: Callable) -> HSlider:
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
	s.value_changed.connect(_on_slider_changed.bind(s, val, setter, formatter))
	parent.add_child(h)
	return s

func _on_slider_changed(value: float, slider: Control, val_label: Label, setter: Callable, formatter: Callable) -> void:
	val_label.text = formatter.call(value)
	_stage(slider, setter, value)

## Dropdown row. `on_select` takes the selected index. Selection set BEFORE connecting (same reason).
func _option_row(parent: VBoxContainer, label_text: String, items: Array, selected: int, on_select: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(str(it))
	ob.selected = clampi(selected, 0, items.size() - 1)
	ob.item_selected.connect(_stage_signal.bind(ob, on_select))
	_row(parent, label_text, ob)
	return ob

## Checkbox row. Returns the CheckButton (focus target).
func _check_row(parent: VBoxContainer, label_text: String, pressed: bool, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = pressed
	c.toggled.connect(_stage_signal.bind(c, on_toggle))
	_row(parent, label_text, c)
	return c

## --- Staged apply: controls write to _pending; nothing reaches Settings until Apply (Revert / reopen drops
## it). Keyed by the setter Callable, so re-touching a control overwrites its own pending value. ---

func _stage(control: Object, setter: Callable, value: Variant) -> void:
	_pending[control] = func(): setter.call(value)  # closure captures THIS setter+value; re-touch overwrites
	_refresh_apply_state()

## Signal-friendly stager: the emitting control's value arrives first; the control + setter are bound last
## via connect(_stage_signal.bind(control, setter)) — used for the option dropdowns + checkboxes.
func _stage_signal(value: Variant, control: Object, setter: Callable) -> void:
	_stage(control, setter, value)

## Commit every staged change (each Settings setter applies to the engine + persists), then clear. Keyed by
## the CONTROL node (a reliable Dictionary key), so each control contributes exactly one pending apply.
func _apply_pending() -> void:
	for apply_cb in _pending.values():
		(apply_cb as Callable).call()
	_pending.clear()
	_refresh_apply_state()

## Drop the staged changes and rebuild the controls from the unchanged Settings.
func _revert() -> void:
	_pending.clear()
	_rebuild_tabs()
	_refresh_apply_state()

## Apply is enabled only while there's something staged to commit.
func _refresh_apply_state() -> void:
	if _apply_btn != null:
		_apply_btn.disabled = _pending.is_empty()

func _on_resolution_selected(index: int) -> void:
	Settings.set_windowed_size(Settings.RESOLUTIONS[index])

func _on_quit() -> void:
	get_tree().quit()

## "Main Menu": close this overlay and return to the start screen WITHOUT closing the app. Only reachable
## in-game — open() hides this button at the start menu.
func _on_main_menu() -> void:
	close()
	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
