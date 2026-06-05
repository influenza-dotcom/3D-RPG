extends GutTest
## Smoke test: the boot scene instantiates and builds its menu (without actually loading the game).

func test_start_menu_builds() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	var inst := scene.instantiate()
	add_child_autofree(inst)
	assert_eq(inst._buttons.get_child_count(), 3, "New Game / Settings / Quit buttons built")
	assert_false(inst._loading, "should not be loading until New Game is pressed")
