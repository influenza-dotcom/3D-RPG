extends Control
signal startup_gate_finished
## StartMenu — the main menu (Continue / New Game / Settings / Quit). Built in code. The shipping boot scene
## is res://scenes/computerroom.tscn (project main_scene), which instances this menu at runtime over its 3D
## computer-room intro with show_background off; run standalone (scenes/start_menu.tscn) it still works as a
## full menu on its own skin backdrop. "New Game" threaded-loads the game scene behind a pure-black boot
## intro (a fading quote card) and swaps to it once ready; "Settings" opens the shared OptionsMenu autoload
## (the very same menu Escape brings up in-game); "Quit Game" exits. The mouse is freed here so the menu is
## clickable.

const GAME_SCENE := "res://scenes/game.tscn"
## The character-creation overlay (name + zero-sum stat build), shown between "New Game" and the boot. Preloaded
## by path (no class_name) so it stays off the global class cache; instanced on demand in _on_new_game.
const CharacterCreationScreen := preload("res://scripts/ui/character_creation.gd")
## The first-launch Terms-of-Service consent gate (the fake, comedic EULA). Shown ONCE — after the startup internet
## warning on the very first boot, before the menu is usable — when Settings.tos_accepted is false; accepting records
## consent (Settings.accept_tos), declining offers only Quit. Preloaded by path (no class_name) like CharacterCreationScreen.
## See _open_terms.
const TermsScreen := preload("res://scripts/ui/terms_of_service_screen.gd")

## The boot quote card (a black screen, white text fading in then out) shown while the game loads, before the
## world fades in. The quotes are DESIGNER-AUTHORED in res://resources/ui/boot_quotes.tres (a `BootQuotes`
## resource — add/edit/reorder them in the inspector, no code). One is picked at random for each New Game start.
## FALLBACK_QUOTE is used only if that resource is missing / empty / fails to load, so the main menu ALWAYS boots.
const BOOT_QUOTES_PATH := "res://resources/ui/boot_quotes.tres"
const FALLBACK_QUOTE := {"text": "Fuck you \n Die"}
const QUOTE_FADE_IN := 2.2   ## seconds the white text takes to rise from black (slow, per the brief)
const QUOTE_HOLD := 2.6      ## seconds the text holds full-bright to be read
const QUOTE_FADE_OUT := 1.6  ## seconds the text fades back to black before the world begins

## The front-of-boot internet warning: fixed cards shown on every normal launch before the TOS, the computer-room
## intro, or the menu. Played one line at a time on the SAME black fade card the boot quote uses (fade in -> hold
## -> fade out, per the QUOTE_* timing above). It is intentionally separate from Settings.tos_accepted so accepting
## the TOS does not suppress this warning on later boots — but the flag DOES decide whether it can be skipped:
## a first-time player must sit through the cards (see _internet_warning_skippable).
const INTERNET_WARNING_CARDS: PackedStringArray = [
	"This game is connected to the internet.",
	"Everything you do will be remembered.",
]
const MENU_REVEAL_INPUT_SHIELD := 0.22

## Draw the skin's full-screen backdrop behind the buttons (texture/scene/flat colour). The standalone scene
## keeps it on; a host scene with its own visuals behind the menu (the ComputerRoom boot intro) turns it off
## so the world shows through. The boot cover + quote card are unaffected — they stay opaque either way.
@export var show_background := true
@export var wait_for_host_boot := false

var _buttons: VBoxContainer
var _black: ColorRect           ## full-screen black cover shown during load + the quote intro
var _quote_root: Control        ## the quote card; its modulate.a is tweened to fade the text in/out
var _quote_label: Label         ## the quote text (set to a random authored quote when a game starts)
var _attrib_label: Label        ## the quote attribution
var _loading := false
var _quote_done := false        ## the intro quote has finished (or was skipped) — gates the scene swap
var _quote_tween: Tween
var _char_create = null          ## the live CharacterCreation overlay (untyped: accessed for its confirmed/cancelled signals)
var _terms_screen = null         ## the live first-launch Terms-of-Service gate (untyped: accessed for its accepted/quit_requested signals)
var _internet_warning_pending := false
var _internet_warning_active := false
## On a genuine first launch (Settings.tos_accepted false) the warning cards CANNOT be skipped — the player has to
## read them before the TOS gate. Latched when the cards start so accepting mid-sequence can't retroactively unlock
## the skip. Every later boot (and the debug_always_show_tos replay, so devs aren't stuck) skips on "press anything".
var _internet_warning_skippable := true
var _menu_input_locked := false
var _menu_input_shield: Control
var _startup_gate_finished := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuStyle.apply(self)  # shared menu Theme (buttons/panels/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	_build_ui()
	visibility_changed.connect(_on_visibility_changed)
	# Boot order: the internet warning is the first normal-launch visual, like an epilepsy warning card. Only after
	# it clears do we show the first-launch TOS or let the hosted computer-room intro start making sound.
	_begin_menu_boot_flow()

func _on_visibility_changed() -> void:
	_maybe_start_internet_warning()

func _build_ui() -> void:
	if show_background:
		add_child(MenuStyle.make_menu_background())  # FIRST child — artist's swappable menu bg (texture/scene, else flat colour)

	# The button column is pinned to the RIGHT of the screen and vertically centred, filling the empty right-hand
	# space: the shipping boot scene (computerroom.tscn) shows its 3D computer-room intro across the frame, so the
	# menu drops into the room's empty right side rather than sitting on top of the centre. A full-rect HBox with
	# END alignment hugs the column to the right edge; offset_right insets it by a gutter so it isn't flush. Run
	# standalone (show_background on) the flat backdrop simply fills behind it in the same spot.
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_right = -(5 * MenuStyle.skin.panel_content_margin)  # right-edge gutter (skin-scaled)
	row.alignment = BoxContainer.ALIGNMENT_END
	add_child(row)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER  # vertically centre the buttons within the full-height column
	row.add_child(col)

	# No title text on the menu -- the game's name is revealed in-world (the SkyTitle intro drop), so the menu
	# stays clean. The right-aligned column keeps the buttons together in the room's empty space.
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	col.add_child(_buttons)
	# "Continue" resumes the autosave (loaded at boot by GameState); only shown when a save file exists. "New
	# Game" wipes the loaded profile back to fresh defaults before starting (Dark Souls: one save, overwritten).
	if GameState.has_save_file():
		_add_button(PlayerText.START_MENU_CONTINUE, _on_continue)
	_add_button(PlayerText.START_MENU_NEW_GAME, _on_new_game)
	_add_button(PlayerText.START_MENU_SETTINGS, _on_settings)
	_add_button(PlayerText.START_MENU_QUIT, _on_quit)

	_build_intro_overlay()

## The boot cover: a full-screen BLACK rect (no loading bar — the load happens behind pure black) with the quote
## card centred on top. Built hidden + last so it sits above the menu; shown when a game starts.
func _build_intro_overlay() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks during the intro
	_black.visible = false
	add_child(_black)

	# The card root is a full-rect MarginContainer with wide SIDE GUTTERS: an authored quote longer than the
	# canvas WRAPS inside the gutters instead of clipping both edges (the old CenterContainer let the label's
	# single-line width run edge-to-edge). _quote_root stays the SINGLE fade handle — _play_intro_quote /
	# _skip_intro_quote tween/reset its modulate.a.
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gutter := 4 * MenuStyle.skin.panel_content_margin
	margins.add_theme_constant_override("margin_left", gutter)
	margins.add_theme_constant_override("margin_right", gutter)
	margins.modulate.a = 0.0  # starts invisible; the tween fades it in then out
	_quote_root = margins
	_black.add_child(_quote_root)

	# The VBox fills the gutter-inset rect; ALIGNMENT_CENTER keeps the card vertically centred while the
	# full-width fill gives the quote label the whole inner width to wrap against.
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 26)
	_quote_root.add_child(col)

	# Text is filled in when a New Game starts (a fresh random quote each time) — see _play_intro_quote.
	# Typography is SKIN-DERIVED (2x the menu's title/hint sizes — identical to the old hardcoded 30/22 at
	# default skin values) so a reskin scales the boot card with the rest of the UI.
	_quote_label = Label.new()
	_quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote_label.add_theme_font_size_override(&"font_size", 2 * MenuStyle.skin.title_size)
	_quote_label.add_theme_color_override(&"font_color", Color.WHITE)
	col.add_child(_quote_label)

	_attrib_label = Label.new()
	_attrib_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attrib_label.add_theme_font_size_override(&"font_size", 2 * MenuStyle.skin.hint_size)
	_attrib_label.add_theme_color_override(&"font_color", MenuStyle.dim_color())
	col.add_child(_attrib_label)

	_menu_input_shield = Control.new()
	_menu_input_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_input_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_input_shield.visible = false
	add_child(_menu_input_shield)

func _add_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(MenuStyle.skin.start_button_min_width, 0)  # skin floor: widest English caption + air
	b.pressed.connect(handler)
	_buttons.add_child(b)
	return b

## New Game: open CHARACTER CREATION first (name + the zero-sum stat build). The profile isn't reset and nothing
## loads until the player clicks "Begin" — so backing out leaves any existing save untouched.
func _on_new_game() -> void:
	if _char_create != null:
		return
	_buttons.visible = false
	_char_create = CharacterCreationScreen.new()
	_char_create.confirmed.connect(_on_character_confirmed)
	_char_create.cancelled.connect(_on_character_cancelled)
	add_child(_char_create)

## "Begin": NOW drop the loaded autosave back to fresh defaults (the Player then seeds itself — loaded = false),
## THEN stamp the chosen name + stat build onto the fresh profile (reset clears stat_values, so this must follow
## it), then start. The disk file is overwritten by the first autosave, not now, so New-Game-then-quit keeps a
## prior save.
func _on_character_confirmed(character_name: String, stat_values: Dictionary, appearance: Dictionary) -> void:
	GameState.reset_for_new_game()
	GameState.player_name = character_name
	GameState.appearance = appearance.duplicate()  # the chosen head/body/colours; carried on every save from here
	for stat in stat_values:
		GameState.stat_values[stat] = int(stat_values[stat])
	GameState.profile_active = true  # a created character IS an authoritative run even before the first autosave (P0-2)
	_close_character_creation()
	_start_game(true)

## "Back": discard the creation overlay and return to the menu buttons. No profile change, no load.
func _on_character_cancelled() -> void:
	_close_character_creation()
	_buttons.visible = true
	# Backing out lands keyboard-ready too — same guarded first-button focus as the shield release.
	if _buttons != null and _buttons.visible and _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Control).grab_focus()

func _close_character_creation() -> void:
	if _char_create != null:
		_char_create.queue_free()
		_char_create = null

## First launch: raise the Terms-of-Service gate over the hidden menu. It cannot be dismissed except by agreeing
## (accepted) or leaving (quit_requested) — there is no path to New Game until consent is recorded.
func _open_terms() -> void:
	if _terms_screen != null:
		return
	_buttons.visible = false
	_terms_screen = TermsScreen.new()
	_terms_screen.accepted.connect(_on_terms_accepted)
	_terms_screen.quit_requested.connect(_on_quit)
	add_child(_terms_screen)

## Consent given: persist it (so the gate never returns on this install), drop the overlay, then release the startup
## gate that either starts the hosted room/menu or continues debug straight-to-game.
func _on_terms_accepted() -> void:
	Settings.accept_tos()
	_close_terms()
	_finish_startup_gate()

func _close_terms() -> void:
	if _terms_screen != null:
		_terms_screen.queue_free()
		_terms_screen = null

## Queue the startup warning. The computer-room host instances this menu while it is hidden, so the cards wait
## until the menu is visible in-tree before starting.
func _begin_menu_boot_flow() -> void:
	_buttons.visible = false
	_set_menu_buttons_disabled(true)
	_internet_warning_pending = true
	_maybe_start_internet_warning()

func _maybe_start_internet_warning() -> void:
	if not _internet_warning_pending or _internet_warning_active or not is_visible_in_tree():
		return
	_play_internet_warning()

func _play_internet_warning() -> void:
	_internet_warning_pending = false
	_internet_warning_skippable = Settings.tos_accepted
	if INTERNET_WARNING_CARDS.is_empty():
		_reveal_menu_after_internet_warning()
		return
	_internet_warning_active = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN  # nothing to click over the black cold open — a lingering arrow reads as a bug
	_attrib_label.visible = false               # these cards have no source line
	_black.visible = true
	if _quote_tween != null and _quote_tween.is_valid():
		_quote_tween.kill()
	_quote_root.modulate.a = 0.0
	_quote_tween = create_tween()
	for line in INTERNET_WARNING_CARDS:
		var text := line  # capture per-iteration so each callback shows ITS card, not the loop's last line
		_quote_tween.tween_callback(func() -> void: _quote_label.text = text)  # swap at the trough (alpha 0), unseen
		_quote_tween.tween_property(_quote_root, "modulate:a", 1.0, QUOTE_FADE_IN)
		_quote_tween.tween_interval(QUOTE_HOLD)
		_quote_tween.tween_property(_quote_root, "modulate:a", 0.0, QUOTE_FADE_OUT)
	_quote_tween.tween_callback(_reveal_menu_after_internet_warning)

## Skip the warning (any key / left-click while it plays, ONLY once the TOS has been accepted on a previous boot),
## jumping to the next startup gate step. Killing the tween
## stops its remaining cards and final reveal callback, so the manual reveal here is the only one.
func _skip_internet_warning() -> void:
	if _quote_tween != null and _quote_tween.is_valid():
		_quote_tween.kill()
	_reveal_menu_after_internet_warning()

## Advance after the startup warning. Fresh installs (or the debug replay toggle) show TOS next; accepted installs
## release the room/menu gate. The short input shield keeps the skip click/key from activating controls underneath it.
func _reveal_menu_after_internet_warning() -> void:
	_internet_warning_pending = false
	_internet_warning_active = false
	if _quote_tween != null and _quote_tween.is_valid():
		_quote_tween.kill()
	_quote_root.modulate.a = 0.0
	_black.visible = false
	_attrib_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Show the TOS on a fresh install (tos_accepted false) OR whenever the Settings > Game debug toggle forces a replay
	# — so a dev can re-see the gate every launch without wiping settings.cfg. Accepting a replay just re-records consent.
	if Settings.debug_always_show_tos or not Settings.tos_accepted:
		_open_terms()
		return
	_finish_startup_gate()

func _finish_startup_gate() -> void:
	if _startup_gate_finished:
		return
	_startup_gate_finished = true
	if Settings.debug_skip_menu:
		_start_game()
		return
	if wait_for_host_boot:
		_buttons.visible = false
		_set_menu_buttons_disabled(true)
		startup_gate_finished.emit()
		return
	startup_gate_finished.emit()
	reveal_hosted_menu()

func reveal_hosted_menu() -> void:
	if _loading or _terms_screen != null:
		return
	# Enable BEFORE showing: the buttons must wear their final colour on the first visible frame (no
	# disabled-grey flash popping to normal at shield release). The shield is the real input block —
	# its full-rect STOP filter eats the mouse and _menu_input_locked swallows keys — so the disable
	# was redundant as a guard.
	_set_menu_buttons_disabled(false)
	_buttons.visible = true
	_arm_menu_input_shield()

func _arm_menu_input_shield() -> void:
	_menu_input_locked = true
	if _menu_input_shield != null:
		_menu_input_shield.visible = true
	var timer := get_tree().create_timer(MENU_REVEAL_INPUT_SHIELD, true)
	timer.timeout.connect(_release_menu_input_shield, CONNECT_ONE_SHOT)

func _release_menu_input_shield() -> void:
	_menu_input_locked = false
	if _menu_input_shield != null:
		_menu_input_shield.visible = false
	if _buttons != null and _buttons.visible:
		_set_menu_buttons_disabled(false)
	# Land keyboard/controller-ready: Godot focus navigation is inert with nothing focused, so focus the
	# first button (the theme's focus stylebox highlights it — the same first-item cue Options shows).
	if _buttons != null and _buttons.visible and _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Control).grab_focus()

func _set_menu_buttons_disabled(disabled: bool) -> void:
	if _buttons == null:
		return
	for child in _buttons.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = disabled

func _input(event: InputEvent) -> void:
	# The menu warning and the New Game boot quote both skip on "press anything", but they can't be live at once.
	# Check the warning first, then keep the reveal shield armed for the click that dismissed it.
	if _internet_warning_active and _black != null and _black.visible and _is_skip_press(event):
		# Swallow the press either way: on a first launch the cards play out in full, but the input must not fall
		# through to the menu/quote branches underneath the black cover.
		if _internet_warning_skippable:
			_skip_internet_warning()
		get_viewport().set_input_as_handled()
	elif _menu_input_locked and _is_menu_reveal_input(event):
		get_viewport().set_input_as_handled()
	elif _is_intro_quote_skip_event(event):
		_skip_intro_quote()
		get_viewport().set_input_as_handled()

func _is_intro_quote_skip_event(event: InputEvent) -> bool:
	if not _loading or _quote_done or _black == null or not _black.visible:
		return false
	return _is_skip_press(event)

func _is_menu_reveal_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		return true
	if event is InputEventMouseButton:
		return true
	return event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"Attack")

## True for the "press anything to skip" inputs shared by both intro sequences: any key-down (no echo), the Attack
## action, or a left-click. Each caller adds its own visibility/state gate before consulting this.
func _is_skip_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo
	if event.is_action_pressed(&"Attack"):
		return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false

## Continue: keep the profile loaded at boot (loaded = true) and start — the Player applies the saved build and
## resumes at the saved respawn point. (_start_game hides the cursor for the black boot intro.)
func _on_continue() -> void:
	_start_game()

## Begin the threaded load of the game scene behind the black boot intro; _process polls + swaps once BOTH the
## load is done AND the quote has finished (or was intentionally skipped). New Game shows the quote; Continue
## and debug-skip go straight through on pure black.
func _start_game(show_quote := false) -> void:
	if _loading:
		return
	AudioManager.stop_sfx()
	_menu_input_locked = false
	if _menu_input_shield != null:
		_menu_input_shield.visible = false
	_set_menu_buttons_disabled(false)
	_loading = true
	_quote_done = false
	# Hide the cursor the moment we leave the (clickable, MOUSE_MODE_VISIBLE) menu — the black boot intro / quote
	# card has nothing to click, so a lingering arrow reads as a bug. Shared by every start path (Begin, Continue,
	# debug-skip); the game scene re-grabs the mouse as CAPTURED once the Player spawns (mouse_input.gd). The load
	# FAILED branch in _process restores VISIBLE so a failed boot lands back on a clickable menu.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	Player.arm_intro()  # the spawn fade-in then drops the in-sky game title
	_buttons.visible = false
	_black.visible = true  # pure black behind the load (no progress bar) — the quote plays over it
	ResourceLoader.load_threaded_request(GAME_SCENE)  # async — _process polls + swaps when ready
	if show_quote:
		_play_intro_quote()
	else:
		_skip_intro_quote()

func _skip_intro_quote() -> void:
	if _quote_tween != null and _quote_tween.is_valid():
		_quote_tween.kill()
	_quote_root.modulate.a = 0.0
	_quote_done = true

## Fade the quote card in -> hold -> fade out, then flag the intro done so _process can swap once the scene has
## ALSO finished loading (whichever takes longer wins, so the quote is never cut off and the load is never seen).
## Continue and the debug straight-to-game boot skip this path.
func _play_intro_quote() -> void:
	if Settings.debug_skip_menu:
		_quote_done = true
		return
	var q := _pick_quote()  # a fresh random quote for this boot
	_quote_label.text = str(q.get("text", ""))
	_attrib_label.text = PlayerText.boot_quote_attribution(str(q.get("attribution", "")))
	_attrib_label.visible = true  # re-show in case the menu warning hid it (its cards carry no byline)
	if _quote_tween != null and _quote_tween.is_valid():
		_quote_tween.kill()
	_quote_root.modulate.a = 0.0
	_quote_tween = create_tween()
	_quote_tween.tween_property(_quote_root, "modulate:a", 1.0, QUOTE_FADE_IN)
	_quote_tween.tween_interval(QUOTE_HOLD)
	_quote_tween.tween_property(_quote_root, "modulate:a", 0.0, QUOTE_FADE_OUT)
	_quote_tween.tween_callback(func() -> void: _quote_done = true)

## A {text, attribution} for the boot card: a random quote from the designer-authored BootQuotes resource, or
## FALLBACK_QUOTE if it's missing / empty / fails to load. Loaded at RUNTIME (not a compile-time preload) and
## read DUCK-TYPED, so this main boot scene never gains a hard dependency on the BootQuotes class — a broken or
## absent resource degrades to the fallback instead of stopping the game from launching.
func _pick_quote() -> Dictionary:
	if ResourceLoader.exists(BOOT_QUOTES_PATH):
		var res: Variant = load(BOOT_QUOTES_PATH)
		if res != null and "quotes" in res and not res.quotes.is_empty():
			var q: Variant = res.quotes[randi() % res.quotes.size()]
			if q != null and "text" in q:
				return {"text": str(q.text), "attribution": str(q.attribution)}
	return FALLBACK_QUOTE

func _on_settings() -> void:
	OptionsMenu.open()

func _on_quit() -> void:
	get_tree().quit()

func _process(_delta: float) -> void:
	if not _loading:
		return
	match ResourceLoader.load_threaded_get_status(GAME_SCENE):
		ResourceLoader.THREAD_LOAD_LOADED:
			# Hold on pure black until the intro quote has finished — the swap into the game (which itself starts
			# black and fades in) is invisible, so the black is unbroken from menu through to the world fade-in.
			if _quote_done:
				var packed := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
				get_tree().change_scene_to_packed(packed)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("StartMenu: failed to load %s" % GAME_SCENE)
			if _quote_tween != null and _quote_tween.is_valid():
				_quote_tween.kill()
			_loading = false
			_quote_done = false
			_buttons.visible = true
			_set_menu_buttons_disabled(false)
			# A failed load lands back keyboard-ready — same guarded first-button focus as the shield release.
			if _buttons != null and _buttons.visible and _buttons.get_child_count() > 0:
				(_buttons.get_child(0) as Control).grab_focus()
			_menu_input_locked = false
			if _menu_input_shield != null:
				_menu_input_shield.visible = false
			_black.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
