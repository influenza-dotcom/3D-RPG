extends CanvasLayer
## SaveLoadScreen — the player-facing MANUAL SAVE / LOAD slot menu over GameState's already-complete backend
## (GameState.gd "Manual save / quicksave / named slots (ML-1)"). Code-built + registered as an autoload like
## the sibling screens (quest_journal.gd is the skeleton this clones; layer/margins match the inventory-style
## chrome). One row per FILE: the quicksave (LOAD-only — F5 owns writing it, player.gd) then
## Slot 1..GameState.SLOT_COUNT. An existing file's row shows its metadata — the saved level's authored
## LevelData.display_name + the file's modified time (slot_metadata below, a pure unit-testable helper);
## a missing file shows an "Empty" caption instead.
##
## Two modes via open(in_game):
##   • in-game (the Options menu's "Save / Load" button — Options CLOSES first, so modals never stack): every
##     slot row offers Save (with an overwrite-confirm dialog over an occupied slot — the options_menu
##     quit-confirm clone) and Load. Loading routes through GameState.load_from_slot / quickload, whose
##     reload path (_load_and_reload) sweeps every modal itself — including this screen — before the scene swap.
##   • menu mode (the start menu's "Load Game" button): LOAD-only. A load runs GameState.load_from_disk on the
##     file's path and then hands off to the `boot` Callable open() was given (StartMenu passes _start_game —
##     the exact boot Continue uses; the parsed [world_snapshot] is consumed by GameRoot on boot).
##
## NON-pausing on purpose — the OptionsMenu Dark-Souls posture: the world keeps simulating and the player stays
## vulnerable; player CONTROL is suppressed via the InputManager modal registry instead (this screen is ONE
## _modal_reg row there, pausing = false, which wires gameplay_suppressed / any_modal_open / close_all_modals).
## These slot files are the EXACT-SNAPSHOT tier; the lean autosave/Continue profile is deliberately NOT a row
## here — presenting it as a manual save would blur the two products (CLAUDE.md "Save semantics must be explicit").

signal opened
signal closed

const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## for the shared player_alive mid-death gate

const PANEL_MARGIN := 0.12   ## same border as the other inventory-style screens — shared chrome
const QUICKSAVE_SLOT := 0    ## row key for the quicksave (real slots are 1..GameState.SLOT_COUNT; 0 never collides)
const ROW_LABEL_WIDTH := 110 ## px floor for the slot-name column so every row's metadata starts on one rail (layout, not text)

var _root: Control
var _list: VBoxContainer
var _status: Label            ## screen-local failure line (the TOAST_QUICKSAVE_FAILED idiom, but painted here, not toasted)
var _confirm: Control         ## the overwrite-confirm overlay (dim + fixed-width dialog) — armed by Save on an occupied slot
var _is_open := false
var _in_game := false         ## open(true) = Save+Load rows; open(false) = the start menu's LOAD-only mode
var _boot := Callable()       ## menu mode only: run AFTER a successful load_from_disk (StartMenu hands in _start_game)
var _pending_slot := 0        ## which slot the armed overwrite-confirm would write
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _focus_target: Button = null   ## first row button of the CURRENT paint — the pad/keyboard landing spot (rows rebuild per repaint)
var _confirm_cancel: Button        ## the overwrite-confirm's Cancel — focused when the confirm arms (the SAFE default for a pad)

func _ready() -> void:
	layer = 121                                  # above the Pip-Boy tabs (120), below OptionsMenu (128) — CharacterInspect's slot
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## Open the slot menu. `in_game` picks the mode (see the header); `boot` is consumed only by menu mode.
## Refuses over any other modal like every screen (the shared registry guard — no stacked overlays), plus the
## two control-only suppressors a registry query can't see (a conversation, the name-entry box).
func open(in_game: bool, boot: Callable = Callable()) -> void:
	if _is_open or DialogueManager.is_active() or NameEntryDialog.is_open() or InputManager.any_modal_open(self):
		return
	# Refuse mid-death in-game, like every sibling screen (stats/journal/inventory): a dead player can still
	# reach Options, and a save captured here would persist the post-death penalties (wallet already bequeathed
	# to the killer, respawn stamped at the death spot) over a good slot. Menu mode has no player to be dead.
	if in_game and not PlayerMenus.player_alive(get_tree()):
		return
	_in_game = in_game
	_boot = boot
	_status.text = ""
	_confirm.visible = false   # never reopen onto a stale armed confirm (the OptionsMenu quit-confirm rule)
	_rebuild()
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # free the cursor for the rows (restored on close)
	_is_open = true
	_root.visible = true
	# Seed pad/keyboard focus on the first row button (the OptionsMenu _first_focus idiom) — without a focus
	# owner, ui navigation is dead and a pad player could open the screen but press nothing on it.
	if _focus_target != null:
		_focus_target.grab_focus()
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	_confirm.visible = false
	Input.mouse_mode = _prev_mouse_mode   # in-game that's CAPTURED; at the start menu it stays VISIBLE
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	# Close on ui_cancel OR the Interact key — the sibling-modal idiom (shop_screen.gd). An armed overwrite
	# confirm swallows the press instead (dismiss it, keep the menu up), mirroring the Options quit-confirm.
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(InputManager.action_pickup):
		if _confirm.visible:
			_confirm.visible = false
			if _focus_target != null:
				_focus_target.grab_focus()   # same hand-back as the Cancel button
		else:
			close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Slot metadata — pure + static so tests can pin it without instancing the screen (no _ready, no tree)
# ---------------------------------------------------------------------------------------------------

## Read the display facts for one save file: {exists: bool, level_name: String, time_text: String}.
## level_name is the saved [level].path LevelData's AUTHORED display_name (a display string never derives from
## an id — blank/unresolvable degrades to "" and the caption drops to its time-only template). time_text is the
## file's modified time via Time.get_datetime_string_from_unix_time. An unreadable file reports exists = false
## (its row paints Empty; a Load on it would fail the same way), so junk on disk can't crash the paint.
static func slot_metadata(path: String) -> Dictionary:
	var none := {"exists": false, "level_name": "", "time_text": ""}
	if not FileAccess.file_exists(path):
		return none
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return none
	var level_name := ""
	var raw_level: Variant = cfg.get_value("level", "path", "")  # same key save_to_disk stamps (GameState.gd)
	if raw_level is String and not (raw_level as String).is_empty() and ResourceLoader.exists(raw_level):
		var ld: Variant = load(raw_level)  # runtime load, duck-typed read — a deleted/reshaped .tres degrades, never crashes
		if ld != null:
			var dn: Variant = ld.get(&"display_name")
			if dn is String:
				level_name = dn
	var mtime := FileAccess.get_modified_time(path)
	var time_text := Time.get_datetime_string_from_unix_time(mtime, true) if mtime > 0 else ""
	return {"exists": true, "level_name": level_name, "time_text": time_text}

# ---------------------------------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStyle.apply(_root)
	add_child(_root)
	_root.add_child(MenuStyle.make_dim())

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared title/content rhythm (MenuSkin)
	panel.add_child(vbox)
	vbox.add_child(MenuStyle.make_title(PlayerText.SAVE_LOAD_TITLE))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)

	# The failure line (a failed disk write / a vanished file). Built EMPTY and only ever assigned PlayerText
	# consts — kept in the tree so the panel height never hops when a failure appears (make_dialog's constant-
	# line-count rule, applied to a full panel).
	_status = MenuStyle.make_hint("")
	vbox.add_child(_status)

	# Overwrite-confirm overlay — a dim + fixed-width dialog stacked over the whole panel (added to the root
	# LAST so it draws on top), cloned from options_menu.gd's quit-confirm. Save on an occupied slot only ARMS
	# this; nothing overwrites a file but its Confirm, so a misclick can't eat a save. Cancel and Escape
	# (_unhandled_input) both dismiss. Both captions are static consts, so the card never reflows.
	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	_root.add_child(_confirm)
	_confirm.add_child(MenuStyle.make_dim())
	var card := MenuStyle.make_dialog(_confirm)
	card.add_child(MenuStyle.make_title(PlayerText.SAVE_LOAD_OVERWRITE_TITLE))
	var confirm_row := HBoxContainer.new()
	confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_row.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	card.add_child(confirm_row)
	var confirm_btn := Button.new()
	confirm_btn.text = PlayerText.CONFIRM
	confirm_btn.custom_minimum_size.x = float(MenuStyle.skin.dialog_button_min_width)
	confirm_btn.pressed.connect(_on_confirm_overwrite)
	confirm_row.add_child(confirm_btn)
	_confirm_cancel = Button.new()
	_confirm_cancel.text = PlayerText.CANCEL
	_confirm_cancel.custom_minimum_size.x = float(MenuStyle.skin.dialog_button_min_width)
	_confirm_cancel.pressed.connect(_on_cancel_overwrite)
	confirm_row.add_child(_confirm_cancel)

## Repaint every row from the CURRENT disk state — on open and after any save/load attempt, so a just-written
## slot immediately shows its new metadata and a vanished file drops back to Empty.
func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_focus_target = null   # the old rows are dying (queue_free) — only a button from THIS paint may take focus
	_add_row(QUICKSAVE_SLOT, PlayerText.SAVE_LOAD_QUICKSAVE_ROW, GameState.QUICKSAVE_PATH)
	for i in range(1, GameState.SLOT_COUNT + 1):
		_add_row(i, PlayerText.save_slot_label(i), GameState.slot_path(i))
	# A repaint while open (post-save, post-failed-load) re-seats pad focus on the fresh rows; during open()
	# _is_open is still false and open() does its own grab after the panel becomes visible.
	if _is_open and _focus_target != null:
		_focus_target.grab_focus()

## One slot row: name | metadata caption | [Save] [Load]. The caption is cap_label'd so RUNTIME metadata (an
## unbounded authored level name) can never widen the panel past its anchors (horizontal scroll is disabled).
## The button rail is two FIXED-width cells — an absent button leaves a same-width spacer — so the Save and
## Load columns stay aligned across rows whose affordances differ (quicksave = load-only, empty = save-only).
func _add_row(slot: int, label_text: String, path: String) -> void:
	var meta := slot_metadata(path)
	var exists := bool(meta["exists"])
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	var name_l := Label.new()
	name_l.text = label_text
	name_l.custom_minimum_size.x = ROW_LABEL_WIDTH
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_l)
	var cap := Label.new()
	MenuStyle.cap_label(cap)  # runtime metadata must clip with "…", never push the panel wider
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if exists:
		cap.text = PlayerText.save_slot_caption(String(meta["level_name"]), String(meta["time_text"]))
	else:
		cap.text = PlayerText.SAVE_LOAD_EMPTY
		cap.add_theme_color_override(&"font_color", MenuStyle.dim_color())
	row.add_child(cap)
	# Save: slots only (F5 owns writing the quicksave) and only in-game (menu mode has no player to capture).
	_add_rail_cell(row, PlayerText.SAVE_LOAD_SAVE, _on_save_pressed.bind(slot), _in_game and slot != QUICKSAVE_SLOT)
	# Load: any EXISTING file, in both modes (has_quicksave/has_slot gate = the file's presence on disk).
	_add_rail_cell(row, PlayerText.SAVE_LOAD_LOAD, _on_load_pressed.bind(slot), exists)
	_list.add_child(row)

## One fixed-width cell of a row's button rail: a Button when the affordance applies, else an equal-width
## spacer so the columns hold. Bound-method Callables, never capturing lambdas (project rule: a freed-capture
## lambda errors before any guard — these rows are freed on every repaint).
func _add_rail_cell(row: HBoxContainer, caption: String, cb: Callable, present: bool) -> void:
	var w := float(MenuStyle.skin.dialog_button_min_width)
	if present:
		var b := Button.new()
		b.text = caption
		b.custom_minimum_size.x = w
		MenuStyle.cap_button(b)  # EXACT width, not a floor — a re-worded caption must clip, not shift the rail
		b.pressed.connect(cb)
		row.add_child(b)
		if _focus_target == null:
			_focus_target = b   # first button of this paint = the pad/keyboard landing spot
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size.x = w
		row.add_child(spacer)

# ---------------------------------------------------------------------------------------------------
# Save / Load actions
# ---------------------------------------------------------------------------------------------------

## Save clicked on slot `slot`: an occupied slot arms the overwrite confirm (only its Confirm writes);
## an empty one writes immediately.
func _on_save_pressed(slot: int) -> void:
	if GameState.has_slot(slot):
		_pending_slot = slot
		_confirm.visible = true
		_confirm_cancel.grab_focus()   # pad focus lands on the SAFE choice — Confirm is one deliberate step away
		return
	_do_save(slot)

func _on_confirm_overwrite() -> void:
	_confirm.visible = false
	_do_save(_pending_slot)

func _on_cancel_overwrite() -> void:
	_confirm.visible = false
	if _focus_target != null:
		_focus_target.grab_focus()   # hand pad focus back to the rows (Confirm's path re-seats via _rebuild)

## Capture the live human player into `slot`. save_to_slot returns true ONLY when the file actually persisted
## (GameState._capture_and_write), so the failure line can never paint over a save that silently didn't happen
## — and a repaint on success shows the fresh metadata immediately.
func _do_save(slot: int) -> void:
	var player := Groups.human_player(get_tree())  # the ONE non-companion human-player filter (Groups consts enforced)
	if player == null or not GameState.save_to_slot(player, slot):
		_status.text = PlayerText.SAVE_LOAD_SAVE_FAILED
		return
	_status.text = ""
	_rebuild()

## Load clicked. In-game the GameState reload path is the whole story: it closes every modal (including this
## screen) and reloads the scene, so success needs nothing from us — only a failure (file vanished/unreadable
## since the paint) stays here to report + repaint. Menu mode loads the profile into memory and hands off to
## the boot Callable (the Continue path: loaded = true, GameRoot consumes the parsed [world_snapshot] on boot).
func _on_load_pressed(slot: int) -> void:
	if _in_game:
		var ok := GameState.quickload() if slot == QUICKSAVE_SLOT else GameState.load_from_slot(slot)
		if not ok:
			_status.text = PlayerText.SAVE_LOAD_LOAD_FAILED
			_rebuild()
		return
	var path := String(GameState.QUICKSAVE_PATH) if slot == QUICKSAVE_SLOT else GameState.slot_path(slot)
	if not GameState.load_from_disk(path):
		_status.text = PlayerText.SAVE_LOAD_LOAD_FAILED
		_rebuild()
		return
	# Close FIRST (restores the menu's mouse mode + lets StartMenu re-show its buttons via `closed`), THEN boot
	# — _start_game immediately re-hides those buttons behind the black boot cover, same as Continue.
	var boot := _boot
	close()
	if boot.is_valid():
		boot.call()
