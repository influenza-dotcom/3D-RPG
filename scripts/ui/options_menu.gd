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
##
## AUTHORED SCENE: the static chrome lives in scenes/ui/options_menu.tscn (this autoload IS that scene —
## see project.godot [autoload]); this script binds it by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters) on top, so a designer rearranges the panel in the editor
## and the skin keeps owning colours/fonts/width pins. The TAB PAGES stay 100% code-built (_rebuild_tabs
## generates every tab + row from SettingsCatalog/ActionCatalog) — the scene authors only the empty %Tabs
## container. NO text is authored in the scene — every string is set here from PlayerText (l10n + the
## text-debt ratchet own strings, never a .tscn). tests/test_options_menu_scene.gd pins the wiring.

signal opened
signal closed

const PANEL_MARGIN := 0.07  ## fraction of the screen left as a border around the panel (adapts to any res). The Panel's anchor fractions are AUTHORED in the scene; this const is the pin the scene test checks them against.

## Row-layout metrics (px in the ~792x444 UI canvas) shared by the three row builders — one label column on
## the left, one control rail on the right — now live on MenuSkin as English-measured budgets a per-locale
## skin can retune: setting_label_col_width / setting_label_col_width_dense (the name-column rails),
## slider_readout_width (EXACT readout column, cap_label'd) and rebind_button_width (fixed keybind column,
## cap_button'd). See MenuSkin's "Layout budgets" group for each knob's fit math; only non-text layout
## numbers stay as consts here.

## A page with MORE rows than this — and only plain value rows (no section headers / keybind rows) — lays
## out two-up (see _page_columns) so it fits the ~245px tab page without scrolling. Accessibility is the only
## tab over the threshold (18 rows today, and it keeps growing — don't re-pin the exact count here); every
## other tab is <=7 rows and stays single-column.
const TWO_UP_ROW_THRESHOLD := 8

## The declarative source of truth for every row + tab (and which actions are rebindable). Authored in the
## inspector; consumed only here. See resources/settings/SettingSpec.gd for the model.
const CATALOG := preload("res://resources/settings/SettingsCatalog.tres")
## The rebindable input actions, as data. Its keybind_specs() generates the Controls tab's section headers +
## rebind rows (as SettingSpecs), appended to CATALOG.specs in _rebuild_tabs. See scripts/input/action_spec.gd.
const ACTION_CATALOG := preload("res://resources/input/ActionCatalog.tres")
## For the shared player_alive mid-death gate in open() — same preload every sibling screen uses
## (player_menus.gd has no class_name on purpose, so it must be preloaded by path).
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")

var _root: Control
var _tabs: TabContainer
var _first_focus: Control
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
## Staged settings edits (setter Callable -> pending value); flushed to Settings on Apply, dropped on Revert.
var _pending: Dictionary = {}
var _apply_btn: Button = null
var _save_load_btn: Button = null  ## "Save / Load" (the manual slot screen) — only shown in-game, like Main Menu (see open())
var _main_menu_btn: Button = null  ## "Main Menu" (return to start screen) — only shown in-game (see open())
var _quit_confirm: Control = null  ## the Quit Game confirmation overlay (dim + dialog) — see _bind_ui

var _rebinding_action: StringName = &""
var _rebind_button: Button = null

func _ready() -> void:
	layer = 128                                  # above the HUD (default layer 1) — also authored in the scene
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working regardless of any pause
	_bind_ui()
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
	# Refuse MID-DEATH, like every sibling screen (Inventory / Stats / Reputation / Journal / CharacterInspect /
	# SaveLoad). We are a NON-pausing PROCESS_MODE_ALWAYS autoload, so Escape keeps reaching _unhandled_input all
	# through the death cinematic AND the in-place checkpoint revive — where the player stays in-tree with the
	# _dead latch set and hp 0 (Character.is_alive() == false). die() slams us shut (Player._close_open_modals ->
	# InputManager.close_all_modals) and _respawn_at_checkpoint sweeps a second time for exactly this reason, but
	# nothing stopped Escape from RE-opening the settings menu over the black screen / death card in between —
	# with a freed cursor, a live Main Menu + Save/Load + Quit row, and a rebind capture that outlives the revive.
	# Gating the toggle here (not in _unhandled_input) covers every caller. Death is always a BOUNDED sequence
	# ending in a respawn or a scene reload, so this can't strand the player with no way out.
	# player_alive() is true when there is no player at all, so the start menu / character creation still open
	# Options normally — this gate is strictly about being dead, never about being player-less.
	if not PlayerMenus.player_alive(get_tree()):
		return
	_is_open = true
	# Rebuild the tabs fresh from the CURRENT Settings each open, dropping any edits left unapplied last time.
	_pending.clear()
	_rebuild_tabs()
	_refresh_apply_state()
	# Only offer "Main Menu" + "Save / Load" while in-game (a player exists) — at the start menu the first is a
	# redundant reload and the second has no player to capture (the menu's own "Load Game" covers loading there).
	var in_game := _find_real_player() != null
	if is_instance_valid(_main_menu_btn):
		_main_menu_btn.visible = in_game
	if is_instance_valid(_save_load_btn):
		_save_load_btn.visible = in_game
	if _quit_confirm != null:
		_quit_confirm.visible = false  # a forced close (death) can leave an armed confirm behind; never reopen onto it
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
		# An armed quit-confirm swallows this Escape: dismiss it and stop, so the same press can't
		# also toggle the whole menu shut underneath the overlay.
		if _quit_confirm != null and _quit_confirm.visible:
			_quit_confirm.visible = false
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/options_menu.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE only (containers, anchors, size flags, the fixed bottom-row button set, the quit-confirm
## scaffold); the skin keeps owning colours/fonts/separations via the style_* adopters, and every string
## is set HERE from PlayerText. What each piece still guarantees (the same contracts the old procedural
## build carried):
##  * %Root eats clicks (mouse_filter STOP, authored) so nothing falls through behind the menu; the Panel
##    is inset by the PANEL_MARGIN anchor fractions (authored — the scene test pins them against the
##    const) so it fills most of the screen at ANY resolution (low-res viewport).
##  * the TAB PAGES stay 100% code-built: _rebuild_tabs generates every tab + row from the catalogs into
##    the authored (empty) %Tabs container, so the scene can never drift from SettingsCatalog.tres.
##  * "Save / Load" + "Main Menu" are the buttons that appear only in-game (hidden at the start screen —
##    see open()). They are authored FIRST so they sit together at the LEFT end of the END-aligned
##    (right-justified) %Bottom cluster: hiding them then only frees space on the left, and
##    Apply/Revert/Close/Quit — all to their right, pinned to the panel's right edge — keep their exact
##    positions. (When Main Menu sat mid-cluster, toggling it reflowed every button to its right.)
##  * the quit-confirm overlay is a dim + fixed-width dialog stacked over the whole menu (%QuitConfirm is
##    %Root's LAST child so it draws on top of the panel). Quit Game only ARMS it; nothing kills the
##    process but its Confirm, so a misclick at the end of the bottom row is no longer fatal. Cancel and
##    Escape (_unhandled_input) both dismiss. Both captions are static consts, so the card never reflows;
##    style_dialog_card pins %QuitCard to skin.dialog_width (the make_dialog discipline).
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/sliders/tabs/tooltips/fonts) — reskin via resources/ui/menu_skin.tres; also sound-wires the authored buttons
	MenuStyle.style_dim(%Dim)

	var vbox: VBoxContainer = %VBox
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared title/content rhythm (MenuSkin)

	var title: Label = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(title)
	title.text = MenuStyle.title_text(PlayerText.OPTIONS_TITLE)

	_tabs = %Tabs
	_rebuild_tabs()

	var bottom: HBoxContainer = %Bottom
	MenuStyle.style_button_row(bottom)  # END alignment is authored; only the skin's separation is adopted
	_save_load_btn = %SaveLoadButton
	_save_load_btn.text = PlayerText.OPTIONS_SAVE_LOAD
	_save_load_btn.pressed.connect(_on_save_load)
	_main_menu_btn = %MainMenuButton
	_main_menu_btn.text = PlayerText.OPTIONS_MAIN_MENU
	_main_menu_btn.pressed.connect(_on_main_menu)
	_apply_btn = %ApplyButton
	_apply_btn.text = PlayerText.OPTIONS_APPLY
	_apply_btn.pressed.connect(_apply_pending)
	var revert_btn: Button = %RevertButton
	revert_btn.text = PlayerText.OPTIONS_REVERT
	revert_btn.pressed.connect(_revert)
	var close_btn: Button = %CloseButton
	close_btn.text = PlayerText.CLOSE
	close_btn.pressed.connect(close)
	var quit_btn: Button = %QuitButton
	quit_btn.text = PlayerText.OPTIONS_QUIT_GAME
	quit_btn.pressed.connect(_show_quit_confirm)
	_refresh_apply_state()

	# Quit-confirm overlay adoption (see the header bullet): dim + centered fixed-width card, both authored.
	_quit_confirm = %QuitConfirm
	MenuStyle.style_dim(%QuitDim)
	MenuStyle.style_dialog_card(%QuitCard)
	var quit_title: Label = MenuStyle.cap_label(%QuitTitle)
	MenuStyle.style_title(quit_title)
	quit_title.text = MenuStyle.title_text(PlayerText.OPTIONS_QUIT_GAME)
	MenuStyle.style_button_row(%ConfirmRow)  # CENTER alignment is authored
	var confirm_btn: Button = %ConfirmButton
	confirm_btn.text = PlayerText.CONFIRM
	confirm_btn.custom_minimum_size.x = float(MenuStyle.skin.dialog_button_min_width)
	confirm_btn.pressed.connect(_on_quit)
	var cancel_btn: Button = %CancelButton
	cancel_btn.text = PlayerText.CANCEL
	cancel_btn.custom_minimum_size.x = float(MenuStyle.skin.dialog_button_min_width)
	cancel_btn.pressed.connect(_hide_quit_confirm)

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
		var columns: Array[VBoxContainer] = _page_columns(_add_tab(String(tab), _tab_title(tab, tab_specs)), tab_specs)
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
			# "No cap", not "Uncapped": the readout column is exactly skin.slider_readout_width (56px
			# English budget) and "Uncapped" measures ~64px at body_size 12 — it would ellipsize. Keep
			# UNCAPPED strings inside that budget.
			return func(v): return "No cap" if int(v) == 0 else str(int(v))
		SettingSpec.ValueFormat.SENSITIVITY:
			return func(v): return str(int(round(remap(v, Settings.SENS_MIN, Settings.SENS_MAX, 1.0, 100.0))))
		SettingSpec.ValueFormat.ONE_DECIMAL:
			return func(v): return "%.1f" % v
		_:
			return func(v): return str(v)

# --- Custom row builders (the few rows that aren't pure value-binding; named by spec.custom_handler) ---

## Resolution chooser: items + selection derive from Settings.RESOLUTIONS / windowed_size, and the staged
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
		res_items.append(TextFormat.subst(PlayerText.OPTIONS_RESOLUTION_CUSTOM, {"w": str(cur.x), "h": str(cur.y)}))
		res_sel = res_items.size() - 1
	return _option_row(parent, _spec.label, res_items, res_sel, _on_resolution_selected)

## Window-mode chooser — items are CODE-defined (Settings.WINDOW_MODES order) rather than spec.options, so the
## editor can't drop them on a SettingsCatalog.tres re-save (a recurring quirk that left this an empty chooser +
## a red baseline test). Current index + staged setter come from the spec's getter/setter, exactly like the old
## generic DROPDOWN path. A CUSTOM spec, so test_dropdowns_have_options no longer needs options in the .tres.
func _emit_window_mode(parent: VBoxContainer, spec: Variant) -> Control:
	return _option_row(parent, spec.label, [PlayerText.OPTIONS_WINDOWED, PlayerText.OPTIONS_BORDERLESS, PlayerText.OPTIONS_EXCLUSIVE_FULLSCREEN], int(_spec_current(spec)), _spec_setter(spec))

## Colorblind-filter chooser — code-defined items (0..3 -> none/protan/deutan/tritan), same reason as window
## mode. ARRAY ORDER IS BEHAVIOUR (index-mapped setter) — the PlayerText consts only re-word, never re-order.
func _emit_colorblind_mode(parent: VBoxContainer, spec: Variant) -> Control:
	return _option_row(parent, spec.label, [PlayerText.OPTIONS_CB_NONE, PlayerText.OPTIONS_CB_PROTANOPIA, PlayerText.OPTIONS_CB_DEUTERANOPIA, PlayerText.OPTIONS_CB_TRITANOPIA], int(_spec_current(spec)), _spec_setter(spec))

## Difficulty chooser — code-defined items (0..2 -> Easy/Normal/Hard, the DifficultySettings.Level order), same
## CUSTOM-spec reason as window mode. Binds the spec's getter/setter (Settings.difficulty_level / set_difficulty).
## ARRAY ORDER IS BEHAVIOUR — must stay the DifficultySettings.Level order; the consts only re-word.
func _emit_difficulty(parent: VBoxContainer, spec: Variant) -> Control:
	return _option_row(parent, spec.label, [PlayerText.OPTIONS_DIFFICULTY_EASY, PlayerText.OPTIONS_DIFFICULTY_NORMAL, PlayerText.OPTIONS_DIFFICULTY_HARD], int(_spec_current(spec)), _spec_setter(spec))

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
## Casing goes through MenuStyle.title_text — the ONE casing chokepoint (skin.uppercase_titles) — never a
## local .to_upper(), so a skin that turns uppercase off (no meaningful uppercase in CJK etc.) covers this too.
func _rebind_section(parent: VBoxContainer, title: String) -> void:
	var l := Label.new()
	l.text = MenuStyle.title_text(title)
	l.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	l.add_theme_color_override(&"font_color", MenuStyle.accent())
	parent.add_child(l)

func _rebind_row(parent: VBoxContainer, action: StringName, label_text: String) -> void:
	var btn := Button.new()
	btn.custom_minimum_size.x = float(MenuStyle.skin.rebind_button_width)  # fixed-width right-aligned binding column, not a full-width bar (English-measured skin budget)
	# cap_button makes that width EXACT, not a floor: without it, arming a rebind swapped in the long bind
	# prompt and grew the button ~50px leftward (min width = caption width), breaking the column every click.
	MenuStyle.cap_button(btn)
	btn.text = _binding_label(action)
	btn.pressed.connect(_begin_rebind.bind(action, btn))
	_row(parent, label_text, btn, false)

## The current binding shown on a rebind button — the canonical logic now lives on InputManager
## (get_action_binding / event_label), shared with the hover readout's interact key-hints ("[E] Talk to Kyle").
func _binding_label(action: StringName) -> String:
	return InputManager.get_action_binding(action)

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

## The VISIBLE title for a tab page: the first non-empty spec.tab_label in catalog order, else the key
## itself — so today's catalog (no tab_labels authored) paints exactly what it always did. Do NOT resave
## SettingsCatalog.tres from code to author labels (the editor drops PackedStringArray options on re-save,
## per SettingSpec's @risk); hand-edit the .tres text or leave the fallback.
func _tab_title(tab: StringName, tab_specs: Array) -> String:
	for spec in tab_specs:
		if spec != null and not String(spec.tab_label).is_empty():
			return String(spec.tab_label)  # explicit String: specs are duck-typed Variants here (see _rebuild_tabs)
	return String(tab)

## A scrollable tab page (overflow scrolls rather than clipping at low resolutions). Returns the VBox rows
## are added to. `key` (String(spec.tab)) becomes the page node's NAME — the stable id — while `title` is
## painted via set_tab_title, so re-wording a tab's display title can never change what code looks up.
## (The old single-arg version fused them: the node name WAS the visible title.)
func _add_tab(key: String, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = key  # the KEY, never display prose — TabContainer would otherwise title the tab from it
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
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, title)  # explicit title: display text, decoupled from the node name
	return v

## A labelled row: a fixed-width name on the left, the control on the right. `expand` picks the control's
## layout: true (the choice cyclers, the music-folder picker; sliders build their own row) fills the remaining width;
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
## via `_dense_column` meta) gets the narrower skin.setting_label_col_width_dense so its slider rows still
## fit the ~310px half-width; full-width pages use skin.setting_label_col_width so every tab's controls
## start on the same rail. Both are English-measured MenuSkin budgets (see that group's fit math).
func _label_col_width(parent: Control) -> float:
	if parent.has_meta(&"_dense_column"):
		return float(MenuStyle.skin.setting_label_col_width_dense)
	return float(MenuStyle.skin.setting_label_col_width)

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
	val.custom_minimum_size.x = float(MenuStyle.skin.slider_readout_width)  # EXACT English-measured skin budget (see MenuSkin)
	# cap_label pins the readout to EXACTLY that width: an over-wide string ("No cap" used to be "Uncapped",
	# which beat the 56px floor) otherwise grows the label and shrinks the EXPAND_FILL slider mid-drag,
	# sliding the grabber out from under the cursor.
	MenuStyle.cap_label(val)
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

## Choice row: an in-canvas < value > CYCLER, not an OptionButton. With embed_subwindows OFF (deliberate —
## see MenuStyle's tooltip note) a dropdown's PopupMenu is a NATIVE OS window, which escapes the 792x444
## retro pipeline entirely (desktop-res glyphs, no PS1 warp, floats over the fullscreen canvas). A cycler
## keeps every pixel inside the viewport. `on_select` takes the selected index — same contract as the old
## item_selected wiring, and cycling STAGES through _stage keyed by the value button, so re-cycling
## overwrites the row's one pending entry. The current index rides in metadata on the value button (the
## items arrays are short — wrap-around cycling loses nothing vs a full list). Initial caption is painted
## BEFORE any signal wiring (same construction-time-silence reason as the sliders). Returns the VALUE
## button, the row's ONE focus target (_emit_row/_first_focus contract): prev/next are FOCUS_NONE so D-pad
## vertical nav lands on a single control per row. Press = step forward; ui_left/ui_right on it step
## back/forward (the HSlider rows are the precedent for a focused row control eating left/right).
func _option_row(parent: VBoxContainer, label_text: String, items: Array, selected: int, on_select: Callable) -> Button:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var prev_btn := Button.new()
	prev_btn.text = MenuStyle.skin.cycler_prev_glyph
	prev_btn.focus_mode = Control.FOCUS_NONE
	box.add_child(prev_btn)
	var value_btn := Button.new()
	value_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# cap_button: the caption changes per entry ("1920 x 1080" vs "Windowed"), so an over-wide one must
	# clip instead of reflowing the row width every step.
	MenuStyle.cap_button(value_btn)
	var idx := clampi(selected, 0, items.size() - 1)
	value_btn.set_meta(&"cycle_index", idx)
	if not items.is_empty():  # an empty catalog options array leaves the caption blank (the old empty dropdown)
		value_btn.text = str(items[idx])
	box.add_child(value_btn)
	var next_btn := Button.new()
	next_btn.text = MenuStyle.skin.cycler_next_glyph
	next_btn.focus_mode = Control.FOCUS_NONE
	box.add_child(next_btn)
	# Bound-method Callables, not capturing lambdas (project rule: a freed-capture lambda errors before any guard).
	prev_btn.pressed.connect(_cycle_option.bind(-1, value_btn, items, on_select))
	next_btn.pressed.connect(_cycle_option.bind(1, value_btn, items, on_select))
	value_btn.pressed.connect(_cycle_option.bind(1, value_btn, items, on_select))  # Enter/Space/click on the value = next
	value_btn.gui_input.connect(_on_cycler_gui_input.bind(value_btn, items, on_select))
	_row(parent, label_text, box)
	return value_btn

## Step a cycler row by `dir` (+1/-1, wrapping): repaint the value caption and STAGE the new index —
## keyed by the value button, so repeated cycling keeps exactly one pending entry (the dropdown's contract).
func _cycle_option(dir: int, value_btn: Button, items: Array, on_select: Callable) -> void:
	var n := items.size()
	if n == 0:
		return
	var i: int = (int(value_btn.get_meta(&"cycle_index", 0)) + dir + n) % n
	value_btn.set_meta(&"cycle_index", i)
	value_btn.text = str(items[i])
	_stage(value_btn, on_select, i)

## The focused value button eats ui_left/ui_right to step the cycler (echo allowed, so holding a key
## repeats like a slider drag). accept_event() keeps the press from ALSO moving focus sideways — the
## dense two-up pages put a second column beside this one.
func _on_cycler_gui_input(event: InputEvent, value_btn: Button, items: Array, on_select: Callable) -> void:
	var dir := 0
	if event.is_action_pressed("ui_left", true):
		dir = -1
	elif event.is_action_pressed("ui_right", true):
		dir = 1
	if dir == 0:
		return
	value_btn.accept_event()
	_cycle_option(dir, value_btn, items, on_select)

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
## via connect(_stage_signal.bind(control, setter)) — used for the checkboxes (the cyclers stage directly
## in _cycle_option, since their "value" is metadata rather than a signal payload).
func _stage_signal(value: Variant, control: Object, setter: Callable) -> void:
	_stage(control, setter, value)

## Commit every staged change (each Settings setter applies to the engine + persists), then clear. Keyed by
## the CONTROL node (a reliable Dictionary key), so each control contributes exactly one pending apply.
func _apply_pending() -> void:
	for apply_cb in _pending.values():
		(apply_cb as Callable).call()
	_pending.clear()
	_refresh_apply_state()

## Drop the staged changes and rebuild the controls from the unchanged Settings. This is the ONE
## _rebuild_tabs call that runs while the menu is on screen (open()'s runs before _root turns visible), and
## a TabContainer whose pages are all freed + re-added resets to tab 0 — so the current tab is captured and
## restored or Revert would visibly bounce the player back to the first tab. Tab order is deterministic
## across rebuilds (catalog insertion order), so the same index lands on the same tab.
func _revert() -> void:
	_pending.clear()
	var cur := _tabs.current_tab if _tabs != null else 0
	_rebuild_tabs()
	if _tabs != null:
		_tabs.current_tab = clampi(cur, 0, _tabs.get_tab_count() - 1)
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

## The bottom row's Quit Game arms the confirm overlay; only the overlay's Confirm reaches _on_quit.
func _show_quit_confirm() -> void:
	_quit_confirm.visible = true

func _hide_quit_confirm() -> void:
	_quit_confirm.visible = false

func _on_quit() -> void:
	get_tree().quit()

## "Main Menu": close this overlay and return to the start screen WITHOUT closing the app. Only reachable
## in-game — open() hides this button at the start menu.
func _on_main_menu() -> void:
	close()
	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")

## "Save / Load": close this overlay FIRST, then open the manual-slot screen in its in-game mode — sequential,
## never stacked (every screen's open() refuses over another modal via the shared registry, so closing before
## opening is the only order that works). Only reachable in-game — open() hides this button at the start menu.
func _on_save_load() -> void:
	close()
	SaveLoadScreen.open(true)
