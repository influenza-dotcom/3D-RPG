extends CanvasLayer
## SaveLoadScreen — the player-facing MANUAL SAVE / LOAD slot menu over GameState's already-complete backend
## (GameState.gd "Manual save / quicksave / named slots (ML-1)"). Registered as an autoload like the sibling
## screens (layer/margins match the inventory-style chrome). One row per FILE: the quicksave (LOAD-only —
## F5 owns writing it, player.gd) then
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
## _modal_reg row there, blocks_tabs = false, which wires gameplay_suppressed / any_modal_open / close_all_modals).
## These slot files are the EXACT-SNAPSHOT tier; the lean autosave/Continue profile is deliberately NOT a row
## here — presenting it as a manual save would blur the two products (CLAUDE.md "Save semantics must be explicit").
##
## AUTHORED SCENE: the static chrome lives in scenes/ui/save_load_screen.tscn (this autoload IS that scene —
## see project.godot [autoload]); this script binds it by %unique name in _bind_ui and applies the skin-driven
## look (MenuStyle style_* adopters) on top, so a designer rearranges the panel in the editor and the skin
## keeps owning colours/fonts/width pins. The per-slot ROWS stay code-built (_rebuild/_add_row — they repaint
## from live disk state) into the authored %List container, and so is the PINNED Back row under %Status (the
## screen's only non-slot control — its way OUT; see _bind_ui). NO text is authored in the scene — every string
## is set here from PlayerText. tests/test_save_load_screen_scene.gd pins the wiring.

signal opened
signal closed

const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## for the shared player_alive mid-death gate

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
var _back_btn: Button              ## the PINNED way out (code-built in _bind_ui) — also the focus seed when NO row has a button

func _ready() -> void:
	layer = 121                                  # above the Pip-Boy tabs (120), below OptionsMenu (128) — CharacterInspect's slot
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
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
	# This screen is NOT a ModalMenu caller (it owns its own mouse-mode save/restore), so it never inherits
	# grab_mouse()'s open sting — it cues its own. PAST every refusal guard above on purpose: an open refused
	# by a stacked modal / a conversation / mid-death must stay silent.
	MenuStyle.play_open()
	# Seed pad/keyboard focus on the first row button (the OptionsMenu _first_focus idiom) — without a focus
	# owner, ui navigation is dead and a pad player could open the screen but press nothing on it. When NO row
	# carries a button at all — menu mode with every slot empty, the shape of a first-ever launch — the pinned
	# Back button is the one focusable left and takes the seed instead (the chip_install_screen fallback).
	if _focus_target != null:
		_focus_target.grab_focus()
	elif is_instance_valid(_back_btn):
		_back_btn.grab_focus()
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	# The open sting's twin (restore_mouse() gives the ModalMenu screens this for free; we restore the mouse
	# ourselves). Past the not-open guard so the close_all_modals sweep landing on an already-shut screen is
	# silent — and that sweep holds MenuStyle's quiet latch anyway, so a reload-driven close never sounds.
	MenuStyle.play_back()
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
			MenuStyle.play_back()            # a dismissed confirm IS a back; this path is keyboard-only (no button to click-cue it)
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
# UI binding (the static chrome is AUTHORED in scenes/ui/save_load_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene authors
## STRUCTURE only (anchors — including the 0.12 panel margin every inventory-style screen shares — size
## flags, autowrap, the 14px row separation, the disabled horizontal scroll); the skin keeps owning colours,
## fonts, the content_separation rhythm and the dialog width pin, all applied HERE so a menu_skin.tres edit
## restyles this screen with zero scene churn. Two things are NOT in the scene: the per-slot rows (they repaint
## from live disk state — _rebuild, into the authored %List) and the pinned Back row appended to %VBox below.
## Every string is set here from PlayerText.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme + sound-wires the authored Confirm/Cancel buttons
	MenuStyle.style_dim(%Dim)

	# Shared title/content rhythm (MenuSkin) on the authored panel VBox — skin-derived, so code-applied.
	(%VBox as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	var title: Label = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(title)
	title.text = MenuStyle.title_text(PlayerText.SAVE_LOAD_TITLE)

	_list = %List  # rows are code-built per repaint; the scene authors only this container + its scroll

	# The failure line (a failed disk write / a vanished file). Authored EMPTY and only ever assigned
	# PlayerText consts — kept in the tree so the panel height never hops when a failure appears
	# (make_dialog's constant-line-count rule, applied to a full panel).
	_status = %Status
	MenuStyle.style_hint(_status)

	# The PINNED way out. This screen used to hold ONLY the title, the slot rows and the (usually blank) status
	# line: reached from the start menu the cursor is already free and visible, every button on the panel acts on
	# a SLOT, and nothing anywhere said Escape closed it — so a mouse-driven player who opened Load Game with no
	# save to load was simply stranded on a modal with no exit. Its two siblings in the first-run flow (character
	# creation, the TOS gate) both pin an exit row; this is that row.
	# CODE-BUILT into the authored %VBox (the AmountPrompt / map_screen pin-card idiom): the scene authors
	# STRUCTURE and carries NO text, and a row that exists only to hang one PlayerText caption on is chrome this
	# script owns. Appended LAST, so it lands under %Status — the panel's final child, below the row list.
	var back_row := HBoxContainer.new()
	MenuStyle.style_button_row(back_row)              # the shared dialog-row separation (skin knob)
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_back_btn = MenuStyle.cap_button(Button.new())    # a re-worded caption clips; the row can never widen the panel
	_back_btn.text = PlayerText.BACK
	_back_btn.custom_minimum_size.x = float(MenuStyle.skin.dialog_button_min_width)  # the shared button width every dialog row uses
	_back_btn.pressed.connect(close)
	# MUTED: close() fires MenuStyle.play_back() itself on every path past its not-open guard (it has to — the
	# Escape path in _unhandled_input lands there too, and a keyboard back must sound like a mouse one), so the
	# generic click here would double the cue up. Same contract as character_creation's / implant_choice's Back.
	MenuStyle.set_button_sound(_back_btn, &"")
	back_row.add_child(_back_btn)
	(%VBox as VBoxContainer).add_child(back_row)

	# Overwrite-confirm overlay — a dim + fixed-width dialog stacked over the whole panel (authored LAST
	# under %Root so it draws on top), cloned from options_menu.gd's quit-confirm. Save on an occupied slot
	# only ARMS this; nothing overwrites a file but its Confirm, so a misclick can't eat a save. Cancel and
	# Escape (_unhandled_input) both dismiss. Both captions are static consts, so the card never reflows.
	_confirm = %Confirm
	MenuStyle.style_dim(%ConfirmDim)
	MenuStyle.style_compact_card(%ConfirmCard)  # width pin + PLAIN panel (the card is shorter than the artist screen-card art's margins)
	var confirm_title: Label = MenuStyle.cap_label(%ConfirmTitle)
	MenuStyle.style_title(confirm_title)
	confirm_title.text = MenuStyle.title_text(PlayerText.SAVE_LOAD_OVERWRITE_TITLE)
	MenuStyle.style_button_row(%ConfirmRow)
	var confirm_btn: Button = %ConfirmButton
	confirm_btn.text = PlayerText.CONFIRM
	confirm_btn.custom_minimum_size.x = float(MenuStyle.skin.dialog_button_min_width)
	confirm_btn.pressed.connect(_on_confirm_overwrite)
	# An overwrite can still FAIL (a refused disk write), so the commit cue lives in _do_save's success tail —
	# mute this button's generic click or a good overwrite would fire click+commit a frame apart.
	MenuStyle.set_button_sound(confirm_btn, &"")
	_confirm_cancel = %CancelButton
	_confirm_cancel.text = PlayerText.CANCEL
	_confirm_cancel.custom_minimum_size.x = float(MenuStyle.skin.dialog_button_min_width)
	_confirm_cancel.pressed.connect(_on_cancel_overwrite)
	MenuStyle.set_button_sound(_confirm_cancel, &"back")  # a dismissed confirm is a back, not a plain click

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
## IN-GAME the button rail is two FIXED-width cells — an absent button leaves a same-width spacer — so the Save
## and Load columns stay aligned across rows whose affordances differ (quicksave = load-only, empty = save-only).
## MENU MODE has only ONE column (see the Save cell below), and the caption keeps the width that buys.
func _add_row(slot: int, label_text: String, path: String) -> void:
	# Read the metadata off the path the file ACTUALLY lives at: while the debug save sandbox is on
	# (GameState.resolve_save_path maps the five canonical files into user://sandbox/), the raw canonical path is
	# the REAL profile the sandbox exists to protect — painting its caption here would offer a Load button for a
	# file GameState.load_from_slot will not read, and paint "empty" over a sandbox slot that does exist.
	# Identity when the sandbox is off, so a shipped build is unaffected.
	var meta := slot_metadata(GameState.resolve_save_path(path))
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
	# ⭐MENU MODE SKIPS THE CELL ENTIRELY rather than reserving a spacer. _add_rail_cell's same-width spacer buys
	# COLUMN ALIGNMENT between rows whose affordances differ — but in menu mode NO row can ever carry a Save
	# button, so there is nothing to align and the reservation was pure loss: 170 of a ~560px panel row went to
	# an empty cell for a button that mode never shows, squeezing the metadata caption — the level name and
	# timestamp, the ONLY things telling one save from another — down to ~90px, where it ellipsised to "Abb…".
	# In-game the two-cell rail is unchanged (the quicksave row still spaces its missing Save).
	var save_btn: Button = null
	if _in_game:
		save_btn = _add_rail_cell(row, PlayerText.SAVE_LOAD_SAVE, _on_save_pressed.bind(slot), slot != QUICKSAVE_SLOT)
	# Sound, per ROW STATE — the one place the two Save outcomes are still distinguishable. An EMPTY slot's Save
	# writes straight through to _do_save, which owns the commit cue, so mute its generic click (a good write
	# would otherwise be click+commit). An OCCUPIED slot's Save only ARMS the confirm and never writes, so it
	# keeps the plain click. The predicate is has_slot, NOT `exists` — that is exactly what _on_save_pressed
	# branches on at press time (an unreadable file paints Empty but still arms the confirm). Safe to decide at
	# paint time because rows repaint from live disk state (_rebuild) after every write, and nothing else writes
	# a slot while this screen is up (F5 owns only the quicksave row, which carries no Save button).
	if save_btn != null and not GameState.has_slot(slot):
		MenuStyle.set_button_sound(save_btn, &"")
	# Load: any EXISTING file, in both modes (has_quicksave/has_slot gate = the file's presence on disk).
	var load_btn := _add_rail_cell(row, PlayerText.SAVE_LOAD_LOAD, _on_load_pressed.bind(slot), exists)
	# A load can fail (the file vanished since this paint), so its commit cue is gated on success inside
	# _on_load_pressed — mute the click here, and a refused load stays silent (there is no "denied" cue).
	if load_btn != null:
		MenuStyle.set_button_sound(load_btn, &"")
	_list.add_child(row)

## One fixed-width cell of a row's button rail: a Button when the affordance applies, else an equal-width
## spacer so the columns hold. Bound-method Callables, never capturing lambdas (project rule: a freed-capture
## lambda errors before any guard — these rows are freed on every repaint).
## Returns the Button it built (null for a spacer) so the caller can re-point or MUTE its sound — the row's
## sound depends on the row's disk state, which only _add_row knows.
func _add_rail_cell(row: HBoxContainer, caption: String, cb: Callable, present: bool) -> Button:
	var w := float(MenuStyle.skin.dialog_button_min_width)
	if not present:
		var spacer := Control.new()
		spacer.custom_minimum_size.x = w
		row.add_child(spacer)
		return null
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size.x = w
	MenuStyle.cap_button(b)  # EXACT width, not a floor — a re-worded caption must clip, not shift the rail
	b.pressed.connect(cb)
	row.add_child(b)
	if _focus_target == null:
		_focus_target = b   # first button of this paint = the pad/keyboard landing spot
	return b

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
		# A FAILED WRITE is the one place in the game where silence is actively dangerous: the player believes
		# their run is on disk. The status line said so and nothing else did.
		MenuStyle.play_denied()
		_status.text = PlayerText.SAVE_LOAD_SAVE_FAILED
		return
	_status.text = ""
	# A written save is a HEAVY commit. THE one hook for both entry paths (an empty slot's Save and the
	# overwrite confirm), and it sits past the failure return so the two verdicts can't be confused — both of
	# those buttons are muted (see _add_row / _bind_ui), so this pair is the only cue either press produces.
	MenuStyle.play_commit()
	_rebuild()

## Load clicked. In-game the GameState reload path is the whole story: it closes every modal (including this
## screen) and reloads the scene, so success needs nothing from us but the commit cue — only a failure (file
## vanished/unreadable since the paint) stays here to report + repaint. Menu mode loads the profile and hands off to
## the boot Callable (the Continue path: loaded = true, GameRoot consumes the parsed [world_snapshot] on boot).
func _on_load_pressed(slot: int) -> void:
	if _in_game:
		var ok := GameState.quickload() if slot == QUICKSAVE_SLOT else GameState.load_from_slot(slot)
		if not ok:
			MenuStyle.play_denied()  # the file vanished or won't parse since the row was painted
			_status.text = PlayerText.SAVE_LOAD_LOAD_FAILED
			_rebuild()
			return
		# Restoring a run is the save's commit twin. No quiet_next_back needed on THIS branch: the reload path
		# already closed us inside close_all_modals, which holds MenuStyle's quiet latch (and drops it before
		# returning here) — so our own back cue was eaten and this fires clean. The scene reload is deferred and
		# MenuStyle's players are autoload-owned, so the cue survives it.
		MenuStyle.play_commit()
		return
	var path := String(GameState.QUICKSAVE_PATH) if slot == QUICKSAVE_SLOT else GameState.slot_path(slot)
	if not GameState.load_from_disk(path):
		MenuStyle.play_denied()  # menu-mode twin of the in-game failure above
		_status.text = PlayerText.SAVE_LOAD_LOAD_FAILED
		_rebuild()
		return
	# Nothing swept us here: close() below is OUR call, so eat the one back cue it would fire — the commit is
	# the beat that belongs to this press, and the back would land on top of it a frame later.
	MenuStyle.quiet_next_back()
	# Close FIRST (restores the menu's mouse mode + lets StartMenu re-show its buttons via `closed`), THEN boot
	# — _start_game immediately re-hides those buttons behind the black boot cover, same as Continue.
	var boot := _boot
	close()
	if boot.is_valid():
		boot.call()
	# ⭐The commit fires AFTER the boot, never before — the boot Callable is StartMenu._start_game, whose first
	# act is AudioManager.stop_sfx(), and that walks the tree stopping every PLAYING voice on the sfx family
	# (STOP_BUSES: sfx / world / gunshots / speaker), MenuStyle's pool included. Cued ahead of the call, loading from the main menu was silent while Continue rang out for
	# the same act. MenuStyle is an autoload, so the voice survives the scene swap.
	MenuStyle.play_commit()
