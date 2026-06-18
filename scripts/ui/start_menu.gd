extends Control
## StartMenu — the boot scene (project main_scene). Built in code. "New Game" threaded-loads the game
## scene behind a pure-black boot intro (a fading quote card) and swaps to it once ready; "Settings" opens the shared OptionsMenu
## autoload (the very same menu Escape brings up in-game); "Quit Game" exits. The mouse is freed here so
## the menu is clickable.

const GAME_SCENE := "res://scenes/game.tscn"

## The boot quote card (a black screen, white text fading in then out) shown while the game loads, before the
## world fades in. The quotes are DESIGNER-AUTHORED in res://resources/ui/boot_quotes.tres (a `BootQuotes`
## resource — add/edit/reorder them in the inspector, no code). One is picked at random each game start.
## FALLBACK_QUOTE is used only if that resource is missing / empty / fails to load, so the main menu ALWAYS boots.
const BOOT_QUOTES_PATH := "res://resources/ui/boot_quotes.tres"
const FALLBACK_QUOTE := {"text": "She who makes a reloading beast of herself\ngets rid of the pain of being a headshotting machine.", "attribution": "Samuel \"Bodyshot\" Johnson"}
const QUOTE_FADE_IN := 2.2   ## seconds the white text takes to rise from black (slow, per the brief)
const QUOTE_HOLD := 2.6      ## seconds the text holds full-bright to be read
const QUOTE_FADE_OUT := 1.6  ## seconds the text fades back to black before the world begins

var _buttons: VBoxContainer
var _black: ColorRect           ## full-screen black cover shown during load + the quote intro
var _quote_root: Control        ## the quote card; its modulate.a is tweened to fade the text in/out
var _quote_label: Label         ## the quote text (set to a random authored quote when a game starts)
var _attrib_label: Label        ## the quote attribution
var _loading := false
var _quote_done := false        ## the intro quote has finished (or was skipped) — gates the scene swap
var _quote_tween: Tween

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
	add_child(MenuStyle.make_menu_background())  # FIRST child — artist's swappable menu bg (texture/scene, else flat colour)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# No title text on the menu -- the game's name is revealed in-world (the SkyTitle intro drop), so the menu
	# stays clean. The CenterContainer keeps the button column centred, filling the space the title used to take.
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

	_quote_root = CenterContainer.new()
	_quote_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quote_root.modulate.a = 0.0  # starts invisible; the tween fades it in then out
	_black.add_child(_quote_root)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 26)
	_quote_root.add_child(col)

	# Text is filled in when a game starts (a fresh random quote each time) — see _play_intro_quote.
	_quote_label = Label.new()
	_quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote_label.add_theme_font_size_override(&"font_size", 30)
	_quote_label.add_theme_color_override(&"font_color", Color.WHITE)
	col.add_child(_quote_label)

	_attrib_label = Label.new()
	_attrib_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attrib_label.add_theme_font_size_override(&"font_size", 22)
	_attrib_label.add_theme_color_override(&"font_color", Color(0.78, 0.78, 0.78))
	col.add_child(_attrib_label)

func _add_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 0)
	b.pressed.connect(handler)
	_buttons.add_child(b)
	return b

## New Game: drop the loaded autosave back to fresh defaults (the Player then seeds itself — loaded = false), then
## start. The disk file is overwritten by the first autosave, not now, so a New-Game-then-quit keeps a prior save.
func _on_new_game() -> void:
	GameState.reset_for_new_game()
	_start_game()

## Continue: keep the profile loaded at boot (loaded = true) and start — the Player applies the saved build and
## resumes at the saved respawn point.
func _on_continue() -> void:
	_start_game()

## Begin the threaded load of the game scene behind the black boot intro; _process polls + swaps once BOTH the
## load is done AND the quote has finished. Shared by New Game / Continue / debug-skip — the only difference
## between them is whether GameState was reset first (debug-skip also skips the quote).
func _start_game() -> void:
	if _loading:
		return
	_loading = true
	_quote_done = false
	Player.arm_intro()  # the spawn fade-in then drops the in-sky game title
	_buttons.visible = false
	_black.visible = true  # pure black behind the load (no progress bar) — the quote plays over it
	ResourceLoader.load_threaded_request(GAME_SCENE)  # async — _process polls + swaps when ready
	_play_intro_quote()

## Fade the quote card in -> hold -> fade out, then flag the intro done so _process can swap once the scene has
## ALSO finished loading (whichever takes longer wins, so the quote is never cut off and the load is never seen).
## The debug straight-to-game boot skips the quote (instant done).
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
