extends Control
## StartMenu — the boot scene (project main_scene). Built in code. "New Game" threaded-loads the game
## scene behind a progress bar and swaps to it once ready; "Settings" opens the shared OptionsMenu
## autoload (the very same menu Escape brings up in-game); "Quit Game" exits. The mouse is freed here so
## the menu is clickable.

const GAME_SCENE := "res://scenes/game.tscn"

var _buttons: VBoxContainer
var _loading_box: VBoxContainer
var _progress: ProgressBar
var _loading := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var menu_theme := Theme.new()
	menu_theme.default_font_size = 16
	self.theme = menu_theme
	_build_ui()
	# DEBUG convenience: boot straight into the game, skipping this menu (toggled in Settings > Game). Continues
	# the autosave if one exists (loaded at boot by GameState), else drops into a fresh game.
	if Settings.debug_skip_menu:
		_start_game()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.07, 1.0)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = str(ProjectSettings.get_setting("application/config/name", "RPG"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	col.add_child(title)

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

	_loading_box = VBoxContainer.new()
	_loading_box.add_theme_constant_override("separation", 8)
	_loading_box.visible = false
	col.add_child(_loading_box)
	var loading_label := Label.new()
	loading_label.text = "Loading..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_box.add_child(loading_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(240, 16)
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_loading_box.add_child(_progress)

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

## Begin the threaded load of the game scene behind the progress bar; _process polls + swaps when ready. Shared by
## New Game / Continue / debug-skip — the only difference between them is whether GameState was reset first.
func _start_game() -> void:
	if _loading:
		return
	_loading = true
	_buttons.visible = false
	_loading_box.visible = true
	ResourceLoader.load_threaded_request(GAME_SCENE)  # async — _process polls + swaps when ready

func _on_settings() -> void:
	OptionsMenu.open()

func _on_quit() -> void:
	get_tree().quit()

func _process(_delta: float) -> void:
	if not _loading:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, progress)
	if not progress.is_empty():
		_progress.value = float(progress[0]) * 100.0
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
			get_tree().change_scene_to_packed(packed)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("StartMenu: failed to load %s" % GAME_SCENE)
			_loading = false
			_buttons.visible = true
			_loading_box.visible = false
