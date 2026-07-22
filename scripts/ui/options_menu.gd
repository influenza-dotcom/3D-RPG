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
## (the player / MouseInput / ScopeIn gate on InputManager.gameplay_suppressed(), so every registered modal covers
## these gates automatically) and the mouse is released for the UI.

signal opened
signal closed

const PANEL_MARGIN := 0.07  ## fraction of the screen left as a border around the panel (adapts to any res)

## Row-layout metrics (px in the ~792x444 UI canvas). Shared by the three row builders so every tab's
## controls sit on the same vertical rails: one label column on the left, one control rail on the right.
const LABEL_COL_WIDTH := 130.0        ## left name-column floor on a full-width row
const LABEL_COL_WIDTH_DENSE := 110.0  ## label floor inside a two-up column — 110 + 10 + 120 (slider) + 10 + 56 (readout) = 306 fits a ~310px half-column at 792x444; the full 130 would overflow it
const SLIDER_READOUT_WIDTH := 56.0    ## right-aligned slider value column ("Uncapped" is the widest readout)
const REBIND_BTN_MIN_WIDTH := 110.0   ## keybind buttons: a fixed-width right-aligned column, not full-width bars
## A page with MORE rows than this — and only plain value rows (no section headers / keybind rows) — lays
## out two-up (see _page_columns) so it fits the ~245px tab page without scrolling. Accessibility's 14 rows
## trip it; every other tab is <=7 rows and stays single-column.
const TWO_UP_ROW_THRESHOLD := 8

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
	# Refuse to open over any other modal (derives from the shared InputManager registry — no inline list to drift;
	# NameEntryDialog is kept explicit since it's a control-only suppressor, not a _modal_reg entry). T1.
	if _is_open or DialogueManager.is_active() or NameEntryDialog.is_open() or InputManager.any_modal_open(self):
		return  # don't fight another modal for the mouse / Escape (no stacked overlays — symmetric with every screen's own gate + InputManager.gameplay_suppressed)
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
	# CANCEL any armed rebind BEFORE closing (button still valid here). Otherwise a forced close (InputManager.close_all_modals
	# on death — Options is non-pausing, so the player can die mid-rebind) leaves _rebinding_action set while this ALWAYS-
	# processing autoload keeps capturing: the next key/pad press anywhere is swallowed, bound, and persisted with no UI — and
	# a later reopen frees the row Button, so the eventual _end_rebind writes .text on a freed node. _end_rebind only restores
	# the label (never calls rebind_action), so cancelling here is a clean abort. No-op when nothing is armed.
	_end_rebind()
	_is_open = false
	_root.visible = false
	_freeze_player(false)
	Input.mouse_mode = _prev_mouse_mode
	closed.emit()

## Non-pausing, Dark Souls style: the menu NO LONGER freezes the player — the world AND the player keep
## running, and the player stays vulnerable (enemies can still hit you while you menu). Player CONTROL is
## suppressed instead: the player (move/jump), MouseInput (fire) and ScopeIn (aim) all gate on
## InputManager.gameplay_suppressed(), which derives from the single _modal_reg registry (every modal screen) plus
## CutscenePlayer / NameEntryDialog — so menu clicks/keys (left-click is also Attack) don't drive the character while
## ANY registered overlay is up, not just this one.
func _freeze_player(_frozen: bool) -> void:
	pass

## The human player, not a companion (companions join &"Player" for targeting but are NPCs).
func _find_real_player() -> Node:
	return Groups.human_player(get_tree())  # M6: the one non-companion human-player filter lives on Groups (no local NPC dep)

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
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared title/content rhythm (MenuSkin)
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
	bottom.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	vbox.add_child(bottom)
	# "Main Menu" is the ONE button that appears only in-game (hidden at the start screen — see open()). It is
	# added FIRST so it sits at the LEFT end of this END-aligned (right-justified) cluster: hiding it then only
	# frees space on the left, and Apply/Revert/Close/Quit — all to its right, pinned to the panel's right edge
	# — keep their exact positions. When it sat mid-cluster, toggling it reflowed every button to its right.
	_main_menu_btn = Button.new()
	_main_menu_btn.text = "Main Menu"
	_main_menu_btn.pressed.connect(_on_main_menu)
	bottom.add_child(_main_menu_btn)
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
	var quit_btn := Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.pressed.connect(_on_quit)
	bottom.add_child(quit_btn)
	_refresh_apply_state()

# ---------------------------------------------------------------------------------------------------
# Catalog-driven tab construction — every row is emitted from a SettingSpec
# ---------------------------------------------------------------------------------------------------

## (Re)build the tab pages from the catalog + CURRENT Settings — on first build, on open, and on Revert — so
## the controls always reflect what's actually applied. Specs are grouped per tab FIRST (tabs are created in
## the order their first spec is seen; rows stay in spec order) so each page can pick its layout from its FULL
## row list before emitting: a dense all-value page goes two-up (see _page_columns), the rest single-column.
## _first_focus = the first focusable control (for keyboard/controller).
func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_first_focus = null
	# The Controls tab's rebind rows are GENERATED from the ActionCatalog (section headers + keybind rows) and
	# appended after the hand-authored specs, so they land on the Controls page after its hint row.
	var specs: Array = CATALOG.specs.duplicate()
	specs.append_array(ACTION_CATALOG.keybind_specs())
	var by_tab: Dictionary = {}  # tab name (StringName) -> Array of its specs, in catalog order
	for spec in specs:
		# specs is Array[SettingSpec], but GDScript types an extracted element as the script resource and
		# won't cast/unify it to the `SettingSpec` class_name — so the row builders take the spec as Variant
		# and read its @export fields dynamically (the SettingSpec.Widget / .ValueFormat enums still resolve).
		if spec == null:
			continue
		if not by_tab.has(spec.tab):
			by_tab[spec.tab] = []
		(by_tab[spec.tab] as Array).append(spec)
	for tab in by_tab:
		var tab_specs: Array = by_tab[tab]
		var columns: Array[VBoxContainer] = _page_columns(_add_tab(String(tab)), tab_specs)
		# Split-half across the columns (a single-column page's one "column" IS the page): the first
		# ceil(n/2) rows fill the left column top-to-bottom, the rest the right, so the catalog's reading
		# order survives per column and _first_focus (first focusable in spec order) lands top-left.
		var split: int = ceili(tab_specs.size() / 2.0) if columns.size() > 1 else tab_specs.size()
		for i in tab_specs.size():
			var control := _emit_row(columns[0] if i < split else columns[1], tab_specs[i])
			if _first_focus == null and control != null:
				_first_focus = control

## The column VBoxes a tab page's rows are emitted into. Most pages: [page] itself (one column). A DENSE
## page — more than TWO_UP_ROW_THRESHOLD rows, ALL plain value rows (a SECTION header or KEYBIND row means
## the Controls-style list, which must stay one readable column) — gets TWO equal-width columns inside an
## HBox so ~13 rows fit the ~245px page height with no scrolling. Columns carry `_dense_column` meta so
## _label_col_width shrinks the label floor to keep a slider row inside the ~310px half-width (see consts).
func _page_columns(page: VBoxContainer, tab_specs: Array) -> Array[VBoxContainer]:
	var dense: bool = tab_specs.size() > TWO_UP_ROW_THRESHOLD
	if dense:
		for spec in tab_specs:
			if spec.control == SettingSpec.Widget.SECTION or spec.control == SettingSpec.Widget.KEYBIND:
				dense = false
				break
	if not dense:
		return [page]
	var two_up := HBoxContainer.new()
	two_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two_up.add_theme_constant_override("separation", 10)  # matches the row gap; a wider gutter would squeeze the slider rows out of their half-column (306px min vs ~310px)
	page.add_child(two_up)
	var columns: Array[VBoxContainer] = []
	for _i in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # two EXPAND_FILL siblings split the width evenly
		col.add_theme_constant_override("separation", 10)     # same row rhythm as a single-column page (_add_tab)
		col.set_meta(&"_dense_column", true)
		two_up.add_child(col)
		columns.append(col)
	return columns

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
	if res_sel == -1:
		# The live size isn't one of the presets (a custom window size). Surface it as its own trailing
		# entry showing the TRUE dimensions, rather than clamping the display to index 0 and lying about it.
		var cur: Vector2i = Settings.windowed_size
		res_items.append("%d x %d (custom)" % [cur.x, cur.y])
		res_sel = res_items.size() - 1
	return _option_row(parent, _spec.label, res_items, res_sel, _on_resolution_selected)

## Window-mode dropdown — items are CODE-defined (Settings.WINDOW_MODES order) rather than spec.options, so the
## editor can't drop them on a SettingsCatalog.tres re-save (a recurring quirk that left this an empty dropdown +
## a red baseline test). Current index + staged setter come from the spec's getter/setter, exactly like the old
## generic DROPDOWN path. A CUSTOM spec, so test_dropdowns_have_options no longer needs options in the .tres.
func _emit_window_mode(parent: VBoxContainer, spec: Variant) -> Control:
	return _option_row(parent, spec.label, [PlayerText.OPTIONS_WINDOWED, PlayerText.OPTIONS_BORDERLESS, PlayerText.OPTIONS_EXCLUSIVE_FULLSCREEN], int(_spec_current(spec)), _spec_setter(spec))

## Colorblind-filter dropdown — code-defined items (0..3 -> none/protan/deutan/tritan), same reason as window mode.
func _emit_colorblind_mode(parent: VBoxContainer, spec: Variant) -> Control:
	return _option_row(parent, spec.label, ["None", "Protanopia", "Deuteranopia", "Tritanopia"], int(_spec_current(spec)), _spec_setter(spec))

## Difficulty dropdown — code-defined items (0..2 -> Easy/Normal/Hard, the DifficultySettings.Level order), same
## CUSTOM-spec reason as window mode. Binds the spec's getter/setter (Settings.difficulty_level / set_difficulty).
func _emit_difficulty(parent: VBoxContainer, spec: Variant) -> Control:
	return _option_row(parent, spec.label, ["Easy", "Normal", "Hard"], int(_spec_current(spec)), _spec_setter(spec))

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
	clear_btn.text = PlayerText.DEFAULT
	clear_btn.pressed.connect(_clear_music_folder.bind(path_btn))
	box.add_child(clear_btn)
	_row(parent, spec.label, box)
	return path_btn

## The picker button's caption: the chosen folder, or a "using each radio's own folder" note when unset.
func _music_folder_label() -> String:
	var f: String = Settings.music_folder
	return f if not f.is_empty() else PlayerText.OPTIONS_MUSIC_FOLDER_DEFAULT

## Open a native directory picker; on a pick, persist it + refresh the button. The dialog is one-shot (freed on
## select/cancel) so the menu never accumulates hidden dialogs. The callbacks are BOUND GUARDED METHODS, not
## lambdas: `path_btn` is a row Button that a tab rebuild (_rebuild_tabs) can free between opening the dialog and
## the pick. A lambda that CAPTURED it would error BEFORE its body ran (project rule: freed-capture guard is
## useless), silently losing the setting AND leaking the dialog. Bound args arrive as method params, so
## is_instance_valid() can guard them — the pick persists even if the row Button is gone. (`dlg` is add_child'd to
## self/persistent, so only path_btn is at risk, but we guard both.)
func _open_music_folder_dialog(path_btn: Button) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = PlayerText.OPTIONS_CHOOSE_MUSIC_FOLDER
	if not Settings.music_folder.is_empty():
		dlg.current_dir = Settings.music_folder
	add_child(dlg)
	# dir_selected emits `d`; bound args (dlg, path_btn) append AFTER it, so the param order is d, dlg, path_btn.
	dlg.dir_selected.connect(_on_music_folder_picked.bind(dlg, path_btn))
	dlg.canceled.connect(_free_dialog.bind(dlg))
	dlg.popup_centered(Vector2i(720, 480))

## A folder was picked: persist it FIRST (the pick must survive even if the row Button was freed by a tab rebuild),
## then refresh the caption only if the row still exists, and free the one-shot dialog.
## `path_btn` is UNTYPED on purpose (F-C46): a tab rebuild can FREE the row Button between the dialog opening and
## this callback, and a concrete `path_btn: Button` param would trip "Invalid type (previously freed)" on the
## argument bind — BEFORE the body's is_instance_valid guard could run. An untyped (Variant) param accepts the
## freed handle, so is_instance_valid() below can no-op the refresh and the pick still persists.
func _on_music_folder_picked(d: String, dlg: FileDialog, path_btn) -> void:
	Settings.set_music_folder(d)                 # persist FIRST — the pick must survive a freed row button
	if is_instance_valid(path_btn):
		path_btn.text = _music_folder_label()    # refresh the caption only if the row still exists
	_free_dialog(dlg)

## Free the one-shot picker (on select OR cancel), guarded so a double-signal / already-freed dialog is a no-op.
func _free_dialog(dlg: FileDialog) -> void:
	if is_instance_valid(dlg):
		dlg.queue_free()

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
	btn.custom_minimum_size.x = REBIND_BTN_MIN_WIDTH  # fixed-width right-aligned binding column, not a full-width bar
	btn.text = _binding_label(action)
	btn.pressed.connect(_begin_rebind.bind(action, btn))
	_row(parent, label_text, btn, false)

## The current binding shown on a rebind button — the canonical logic now lives on InputManager
## (get_action_binding / event_label), shared with the hover readout's interact key-hints ("[E] Talk to Kyle").
func _binding_label(action: StringName) -> String:
	return InputManager.get_action_binding(action)

func _event_label(e: InputEvent) -> String:
	return InputManager.event_label(e)

func _begin_rebind(action: StringName, btn: Button) -> void:
	_rebinding_action = action
	_rebind_button = btn
	btn.text = PlayerText.OPTIONS_BIND_PROMPT

## While a rebind is armed, capture the next key / mouse-button / gamepad-button PRESS as the new binding
## (Esc cancels). Runs in _input (before the GUI) so the captured press doesn't also click something.
func _input(event: InputEvent) -> void:
	if not _is_open or _rebinding_action == &"":  # never capture a binding while the menu is closed (autoload runs ALWAYS)
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
	if is_instance_valid(_rebind_button):  # is_instance_valid, not != null: a tab rebuild may have freed the row Button
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

## A labelled row: a fixed-width name on the left, the control on the right. `expand` picks the control's
## layout: true (dropdowns, the music-folder picker; sliders build their own row) fills the remaining width;
## false (toggles, rebind buttons) shrinks the control onto a right-aligned rail — the LABEL absorbs the
## slack instead — so small controls form one clean right-edge column across every tab instead of stretching
## into full-width bars.
func _row(parent: VBoxContainer, label_text: String, control: Control, expand: bool = true) -> void:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = _label_col_width(parent)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER  # sit on the control's centerline, not riding high beside taller widgets
	h.add_child(l)
	if expand:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # the label takes the slack so the control lands on the right rail
		control.size_flags_horizontal = Control.SIZE_SHRINK_END
	h.add_child(control)
	parent.add_child(h)

## The label-column floor for a row emitted into `parent`: a dense two-up column (see _page_columns, tagged
## via `_dense_column` meta) gets the narrower LABEL_COL_WIDTH_DENSE so its slider rows still fit the ~310px
## half-width; full-width pages use LABEL_COL_WIDTH so every tab's controls start on the same rail.
func _label_col_width(parent: Control) -> float:
	return LABEL_COL_WIDTH_DENSE if parent.has_meta(&"_dense_column") else LABEL_COL_WIDTH

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
	l.custom_minimum_size.x = _label_col_width(parent)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER  # same centerline treatment as _row's label
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
	val.custom_minimum_size.x = SLIDER_READOUT_WIDTH
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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

## Checkbox row. Returns the CheckButton (focus target). Shrunk onto the right rail — a full-width
## CheckButton renders as a row-wide focus/hover bar with the switch stranded at its far end.
func _check_row(parent: VBoxContainer, label_text: String, pressed: bool, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = pressed
	c.toggled.connect(_stage_signal.bind(c, on_toggle))
	_row(parent, label_text, c, false)
	return c

## --- Staged apply: controls write to _pending; nothing reaches Settings until Apply (Revert / reopen drops
## it). Keyed by the CONTROL node, so re-touching a control overwrites its own pending value. ---

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
	# A trailing "(custom)" entry (index past the presets) represents the already-active non-preset size —
	# selecting it is a no-op rather than an out-of-bounds RESOLUTIONS read.
	if index < 0 or index >= Settings.RESOLUTIONS.size():
		return
	Settings.set_windowed_size(Settings.RESOLUTIONS[index])

func _on_quit() -> void:
	get_tree().quit()

## "Main Menu": close this overlay and return to the start screen WITHOUT closing the app. Only reachable
## in-game — open() hides this button at the start menu.
func _on_main_menu() -> void:
	close()
	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
