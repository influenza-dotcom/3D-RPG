extends GutTest
## Smoke tests for the OptionsMenu autoload — it builds its tabbed UI at startup, and open/close toggles
## cleanly with no player present (the start-menu path; in-game it additionally freezes the player).

func after_each() -> void:
	if OptionsMenu.is_open():
		OptionsMenu.close()

func test_autoload_and_tabs_built() -> void:
	assert_not_null(OptionsMenu, "OptionsMenu autoload should be registered")
	assert_eq(OptionsMenu._tabs.get_tab_count(), 4, "Video/Audio/Game/Accessibility tabs should be built")

func test_open_close_toggles() -> void:
	assert_false(OptionsMenu.is_open(), "starts closed")
	OptionsMenu.open()
	assert_true(OptionsMenu.is_open(), "open() opens")
	OptionsMenu.close()
	assert_false(OptionsMenu.is_open(), "close() closes")

func test_toggle_round_trips() -> void:
	OptionsMenu.toggle()
	assert_true(OptionsMenu.is_open(), "toggle opens from closed")
	OptionsMenu.toggle()
	assert_false(OptionsMenu.is_open(), "toggle closes from open")
