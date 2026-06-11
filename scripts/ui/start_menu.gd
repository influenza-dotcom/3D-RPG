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
	# DEBUG convenience: boot straight into a new game, skipping this menu (toggled in Settings > Game).
	if Settings.debug_skip_menu:
		_on_new_game()

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

func _on_new_game() -> void:
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
