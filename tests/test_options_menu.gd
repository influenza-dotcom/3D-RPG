extends GutTest
## Smoke tests for the OptionsMenu autoload — it builds its tabbed UI at startup, and open/close toggles
## cleanly with no player present (the start-menu path; in-game it additionally freezes the player).

func after_each() -> void:
	if OptionsMenu.is_open():
		OptionsMenu.close()

func test_autoload_and_tabs_built() -> void:
	assert_not_null(OptionsMenu, "OptionsMenu autoload should be registered")
	assert_eq(OptionsMenu._tabs.get_tab_count(), 5, "Video/Audio/Game/Controls/Accessibility tabs should be built")

func test_menu_style_sounds_route_to_sfx_bus() -> void:
	assert_eq(MenuStyle._hover_player.bus, &"sfx",
		"menu hover sounds must route to the SFX bus so the SFX volume slider controls them independently of Master")
	assert_eq(MenuStyle._click_player.bus, &"sfx",
		"menu click sounds must route to the SFX bus so UI clicks follow the same audio-routing contract as other one-shots")

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
