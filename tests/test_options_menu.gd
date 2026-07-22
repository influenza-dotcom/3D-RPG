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

func test_music_folder_pick_survives_a_freed_row_button() -> void:
	# F-C46: the folder pick is a BOUND GUARDED METHOD, not a freed-capture lambda — so a pick that lands after the
	# row Button was freed (a Controls-tab rebuild frees it) still PERSISTS the setting instead of erroring before
	# the body runs. Drive _on_music_folder_picked with a freed path_btn and a null dlg (both guarded by
	# is_instance_valid) and assert the setting stuck without a crash. Restore the real setting afterward (the
	# setter writes config to disk).
	var prev: String = Settings.music_folder
	var freed_btn := Button.new()
	freed_btn.free()  # simulate the row Button being freed between opening the dialog and the pick
	OptionsMenu._on_music_folder_picked("res://", null, freed_btn)  # null dlg + freed btn -> the guards no-op
	assert_eq(Settings.music_folder, "res://", "the pick persisted despite the freed row button (guarded method, not lambda)")
	Settings.set_music_folder(prev)  # restore
	assert_eq(Settings.music_folder, prev, "the prior music folder is restored after the test")

func test_close_cancels_an_armed_rebind() -> void:
	# Options is a NON-pausing ALWAYS-processing autoload, so a forced close (InputManager.close_all_modals on player
	# death mid-rebind) must CANCEL the armed capture — else _rebinding_action stays set and the next key/pad press
	# anywhere is silently swallowed, bound, and persisted with no UI. close() now routes through _end_rebind().
	OptionsMenu.open()
	var btn := Button.new()
	add_child_autofree(btn)
	OptionsMenu._begin_rebind(&"jump", btn)
	assert_eq(OptionsMenu._rebinding_action, &"jump", "the rebind is armed")
	OptionsMenu.close()
	assert_eq(OptionsMenu._rebinding_action, &"", "close() cancels the armed rebind — no lingering global capture")
	assert_null(OptionsMenu._rebind_button, "and drops the row-button reference")
