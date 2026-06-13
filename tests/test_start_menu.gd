extends GutTest
## Smoke test: the boot scene instantiates and builds its menu (without actually loading the game).

func test_start_menu_builds() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	var inst := scene.instantiate()
	add_child_autofree(inst)
	# "Continue" is built ONLY when a save file exists on disk (GameState.has_save_file()), so the
	# count is environment-dependent: 3 on a clean profile, 4 once the player has an autosave. Pin
	# against the live condition instead of a fixed 3 (we must NOT delete the user's real save here).
	var expected := 4 if GameState.has_save_file() else 3
	assert_eq(inst._buttons.get_child_count(), expected,
		"New Game / Settings / Quit (+ Continue when a save exists) buttons built")
	assert_false(inst._loading, "should not be loading until New Game is pressed")
