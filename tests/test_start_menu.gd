extends GutTest
## Smoke test: the boot scene instantiates and builds its menu (without actually loading the game).

func test_start_menu_builds() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	# Isolate "builds without auto-loading" from the debug straight-to-game boot: if the env's settings.cfg has
	# debug-skip ON (a dev convenience — e.g. skipping the boot quote), _ready would call _start_game() and flip
	# _loading true, which is correct behaviour but not what this smoke test checks. Force it off + restore.
	var prev_skip: bool = Settings.debug_skip_menu
	Settings.debug_skip_menu = false
	var inst := scene.instantiate()
	add_child_autofree(inst)
	# "Continue" is built ONLY when a save file exists on disk (GameState.has_save_file()), so the
	# count is environment-dependent: 3 on a clean profile, 4 once the player has an autosave. Pin
	# against the live condition instead of a fixed 3 (we must NOT delete the user's real save here).
	var expected := 4 if GameState.has_save_file() else 3
	assert_eq(inst._buttons.get_child_count(), expected,
		"New Game / Settings / Quit (+ Continue when a save exists) buttons built")
	assert_false(inst._loading, "should not be loading until New Game is pressed")
	Settings.debug_skip_menu = prev_skip

func test_intro_quote_skips_on_click_or_key_press() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	var prev_skip: bool = Settings.debug_skip_menu
	Settings.debug_skip_menu = false
	var inst := scene.instantiate()
	add_child_autofree(inst)
	inst._loading = true
	inst._quote_done = false
	inst._black.visible = true
	inst._quote_root.modulate.a = 1.0
	inst._quote_tween = inst.create_tween()
	inst._quote_tween.tween_interval(1.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	inst._input(click)
	assert_true(inst._quote_done, "left-click should skip the boot quote while loading")
	assert_almost_eq(inst._quote_root.modulate.a, 0.0, 0.001,
		"skipping should hide the quote immediately")
	assert_false(inst._quote_tween.is_valid(), "skipping should kill the in-flight quote tween")

	inst._quote_done = false
	inst._quote_root.modulate.a = 1.0
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	inst._input(key)
	assert_true(inst._quote_done, "any key press should also skip the boot quote while loading")
	Settings.debug_skip_menu = prev_skip

func test_intro_quote_ignores_key_release_and_echo() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	var prev_skip: bool = Settings.debug_skip_menu
	Settings.debug_skip_menu = false
	var inst := scene.instantiate()
	add_child_autofree(inst)
	inst._loading = true
	inst._quote_done = false
	inst._black.visible = true
	var release := InputEventKey.new()
	release.keycode = KEY_SPACE
	release.pressed = false
	assert_false(inst._is_intro_quote_skip_event(release), "key release should not skip the boot quote")
	var echo := InputEventKey.new()
	echo.keycode = KEY_SPACE
	echo.pressed = true
	echo.echo = true
	assert_false(inst._is_intro_quote_skip_event(echo), "key-repeat echo should not retrigger quote skip")
	Settings.debug_skip_menu = prev_skip
