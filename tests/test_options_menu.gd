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

func test_choice_rows_are_in_canvas_cyclers_not_popups() -> void:
	# The Options dropdowns became < value > cyclers: with embed_subwindows OFF (project.godot, deliberate)
	# an OptionButton's PopupMenu is a NATIVE OS window that escapes the 792x444 retro pipeline entirely
	# (desktop-res glyphs, no PS1 warp). Pin that nothing in the built Options tree can spawn one.
	OptionsMenu.open()  # rebuilds every tab from the live catalog, so this sweeps every generated row
	var offenders: Array = OptionsMenu._root.find_children("*", "OptionButton", true, false)
	assert_eq(offenders.size(), 0,
		"no OptionButton may exist in the Options tree — choice rows are in-canvas cyclers (a native popup escapes the retro viewport)")
	OptionsMenu.close()

func test_menu_skin_cycler_glyph_defaults() -> void:
	# The cycler arrow glyphs are MenuSkin designer @exports whose defaults live in the .gd, so the shipped
	# menu_skin.tres needed no edit. Plain ASCII on purpose — the pixel font renders guillemets as tofu.
	# MenuSkin is the ONE glyph home (the character creator's part cyclers read the same exports).
	var s := MenuSkin.new()
	assert_eq(s.cycler_prev_glyph, "<", "cycler prev glyph defaults to plain ASCII <")
	assert_eq(s.cycler_next_glyph, ">", "cycler next glyph defaults to plain ASCII >")
	s = null  # Resource (RefCounted) — release per the project test idiom

func test_every_tab_page_shows_a_real_scrollbar_paid_for_out_of_its_gutter() -> void:
	# THE PAGE MUST ADMIT IT SCROLLS. Controls runs 44 rebind rows and Accessibility 33 settings through a
	# ~245px page. Both scrolled; neither said so, because the themed bar was drawn ZERO px wide (see
	# MenuStyle's scrollbar block) — the audit screenshot shows four bindings, a fifth sliced through, and a
	# bare right edge. Two halves are pinned here, and the SECOND is the one that bites:
	#   (a) the bar exists, is always up (not AUTO — every tab must reserve the same rail), and has a width
	#       a mouse can actually hit;
	#   (b) that width is BOUGHT from the page's own right margin, not added to the page. The Accessibility
	#       two-up columns clear the panel by ~17px, and a page minimum wider than the card's anchor band
	#       GROWS THE WHOLE CARD (tests/test_menu_layout_stability.gd) — so the two horizontal insets plus the
	#       bar must still come to exactly PAGE_MARGIN * 2.
	OptionsMenu.open()
	var page_margin: int = int(OptionsMenu.get_script().get_script_constant_map().get("PAGE_MARGIN", 0))
	assert_gt(page_margin, 0, "the page inset budget is declared as a const")
	var width: int = MenuStyle.skin.scrollbar_width
	assert_gt(width, 0, "the skin draws scrollbars with real width")
	for i in OptionsMenu._tabs.get_tab_count():
		var page := OptionsMenu._tabs.get_tab_control(i) as ScrollContainer
		assert_not_null(page, "tab %d's page is the ScrollContainer _add_tab built" % i)
		if page == null:
			continue
		assert_eq(page.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_SHOW_ALWAYS,
			"%s shows its scrollbar before the player wheels" % page.name)
		assert_eq(page.get_v_scroll_bar().get_combined_minimum_size().x, float(width),
			"%s's bar is skin.scrollbar_width wide — visible AND grabbable" % page.name)
		# By TYPE, not by index: a ScrollContainer's own two bars are (internal) children as well.
		var found: Array[Node] = page.find_children("*", "MarginContainer", false, false)
		assert_false(found.is_empty(), "%s's rows sit in the inset MarginContainer" % page.name)
		if found.is_empty():
			continue
		var margin := found[0] as MarginContainer
		var insets: int = (margin.get_theme_constant(&"margin_left")
			+ margin.get_theme_constant(&"margin_right"))
		assert_eq(insets + width, page_margin * 2,
			"%s pays for the bar out of its right inset — the page minimum is unchanged" % page.name)
	OptionsMenu.close()


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
