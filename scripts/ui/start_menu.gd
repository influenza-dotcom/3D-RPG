extends Control
## StartMenu — the main menu (Continue / New Game / Settings / Quit). Built in code. The shipping boot scene
## is res://computerroom.tscn (project main_scene), which instances this menu at runtime over its 3D
## computer-room intro with show_background off; run standalone (scenes/start_menu.tscn) it still works as a
## full menu on its own skin backdrop. "New Game" threaded-loads the game scene behind a pure-black boot
## intro (a fading quote card) and swaps to it once ready; "Settings" opens the shared OptionsMenu autoload
## (the very same menu Escape brings up in-game); "Quit Game" exits. The mouse is freed here so the menu is
## clickable.

const GAME_SCENE := "res://scenes/game.tscn"
## The character-creation overlay (name + zero-sum stat build), shown between "New Game" and the boot. Preloaded
## by path (no class_name) so it stays off the global class cache; instanced on demand in _on_new_game.
const CharacterCreationScreen := preload("res://scripts/ui/character_creation.gd")

## The boot quote card (a black screen, white text fading in then out) shown while the game loads, before the
## world fades in. The quotes are DESIGNER-AUTHORED in res://resources/ui/boot_quotes.tres (a `BootQuotes`
## resource — add/edit/reorder them in the inspector, no code). One is picked at random for each New Game start.
## FALLBACK_QUOTE is used only if that resource is missing / empty / fails to load, so the main menu ALWAYS boots.
const BOOT_QUOTES_PATH := "res://resources/ui/boot_quotes.tres"
const FALLBACK_QUOTE := {"text": "Fuck you \n Die"}
const QUOTE_FADE_IN := 2.2   ## seconds the white text takes to rise from black (slow, per the brief)
const QUOTE_HOLD := 2.6      ## seconds the text holds full-bright to be read
const QUOTE_FADE_OUT := 1.6  ## seconds the text fades back to black before the world begins

## Draw the skin's full-screen backdrop behind the buttons (texture/scene/flat colour). The standalone scene
## keeps it on; a host scene with its own visuals behind the menu (the ComputerRoom boot intro) turns it off
## so the world shows through. The boot cover + quote card are unaffected — they stay opaque either way.
@export var show_background := true

var _buttons: VBoxContainer
var _black: ColorRect           ## full-screen black cover shown during load + the quote intro
var _quote_root: Control        ## the quote card; its modulate.a is tweened to fade the text in/out
var _quote_label: Label         ## the quote text (set to a random authored quote when a game starts)
var _attrib_label: Label        ## the quote attribution
var _loading := false
var _quote_done := false        ## the intro quote has finished (or was skipped) — gates the scene swap
var _quote_tween: Tween
var _char_create = null          ## the live CharacterCreation overlay (untyped: accessed for its confirmed/cancelled signals)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuStyle.apply(self)  # shared menu Theme (buttons/panels/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	_build_ui()
	# DEBUG convenience: boot straight into the game, skipping this menu (toggled in Settings > Game). Continues
	# the autosave if one exists (loaded at boot by GameState), else drops into a fresh game.
	if Settings.debug_skip_menu:
		_start_game()

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
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER  # vertically centre the buttons within the full-height column
	row.add_child(col)

	# No title text on the menu -- the game's name is revealed in-world (the SkyTitle intro drop), so the menu
	# stays clean. The right-aligned column keeps the buttons together in the room's empty space.
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	col.add_child(_buttons)
	# "Continue" resumes the autosave (loaded at boot by GameState); only shown when a save file exists. "New
	# Game" wipes the loaded profile back to fresh defaults before starting (Dark Souls: one save, overwritten).
	if GameState.has_save_file():
		_add_button("Continue", _on_continue)
	_add_button("New Game", _on_new_game)
	_add_button("Settings", _on_settings)
	_add_button("Quit Game", _on_quit)

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

func _add_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 0)
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

func _close_character_creation() -> void:
	if _char_create != null:
		_char_create.queue_free()
		_char_create = null

func _input(event: InputEvent) -> void:
	if _is_intro_quote_skip_event(event):
		_skip_intro_quote()
		get_viewport().set_input_as_handled()

func _is_intro_quote_skip_event(event: InputEvent) -> bool:
	if not _loading or _quote_done or _black == null or not _black.visible:
		return false
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
## resumes at the saved respawn point.
func _on_continue() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_start_game()

## Begin the threaded load of the game scene behind the black boot intro; _process polls + swaps once BOTH the
## load is done AND the quote has finished (or was intentionally skipped). New Game shows the quote; Continue
## and debug-skip go straight through on pure black.
func _start_game(show_quote := false) -> void:
	if _loading:
		return
	AudioManager.stop_sfx()
	_loading = true
	_quote_done = false
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
	_attrib_label.text = "— %s" % str(q.get("attribution", ""))
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
			_black.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
