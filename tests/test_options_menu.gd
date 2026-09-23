extends GutTest
## Smoke tests for the OptionsMenu autoload — it builds its tabbed UI at startup, and open/close toggles
## cleanly with no player present (the start-menu path; in-game it additionally freezes the player).

## The glyph test below paints a sentinel through the SHARED skin; snapshot the shipped glyphs so no later test (or
## suite) inherits it, and repaint the Options tree if the sentinel ever landed in it.
var _shipped_prev_glyph := ""
var _shipped_next_glyph := ""

func before_each() -> void:
	_shipped_prev_glyph = MenuStyle.skin.cycler_prev_glyph
	_shipped_next_glyph = MenuStyle.skin.cycler_next_glyph

func after_each() -> void:
	if OptionsMenu.is_open():
		OptionsMenu.close()
	if MenuStyle.skin.cycler_prev_glyph != _shipped_prev_glyph or MenuStyle.skin.cycler_next_glyph != _shipped_next_glyph:
		MenuStyle.skin.cycler_prev_glyph = _shipped_prev_glyph
		MenuStyle.skin.cycler_next_glyph = _shipped_next_glyph
		OptionsMenu._rebuild_tabs()  # repaint the hidden tree with the shipped glyphs (open()'s own rebuild, minus its sting)

func test_autoload_and_tabs_built() -> void:
	assert_not_null(OptionsMenu, "OptionsMenu autoload should be registered")
	assert_eq(OptionsMenu._tabs.get_tab_count(), 6, "Video/Audio/Game/HUD/Accessibility/Controls tabs should be built")

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

## Every button in the built Options tree whose caption is exactly `text`.
func _buttons_painting(text: String) -> Array[Button]:
	var out: Array[Button] = []
	for n in OptionsMenu._root.find_children("*", "Button", true, false):
		if (n as Button).text == text:
			out.append(n as Button)
	return out

func test_choice_cyclers_paint_their_arrows_from_the_skin() -> void:
	# MenuSkin is the ONE glyph home: the cycler arrows are a designer @export (an RTL locale swaps the pair in its
	# own menu_skin.tres), never a literal in options_menu.gd. Driven, not read back: repaint the tree with a sentinel
	# pair on the live skin and every choice row must pick it up — both arrows, on the same rows.
	MenuStyle.skin.cycler_prev_glyph = "[prev]"
	MenuStyle.skin.cycler_next_glyph = "[next]"
	OptionsMenu._rebuild_tabs()  # the rebuild open() runs on every open: every tab from the live catalog + the live skin
	var prevs := _buttons_painting("[prev]")
	var nexts := _buttons_painting("[next]")
	assert_gt(prevs.size(), 0, "the choice cyclers paint the skin's prev glyph — a designer's glyph edit must reach the Options rows")
	assert_eq(nexts.size(), prevs.size(), "every cycler that paints the skin's prev arrow paints its next arrow too")
	for b in prevs:
		var row := b.get_parent()
		assert_eq(row.get_child(row.get_child_count() - 1), _buttons_painting_in(row, "[next]"),
			"the skin's next arrow closes the SAME row its prev arrow opens (%s)" % row.name)

func _buttons_painting_in(row: Node, text: String) -> Button:
	for c in row.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
	return null

func test_shipped_cycler_glyphs_are_distinct_and_renderable() -> void:
	# The arrows default to plain ASCII because a pixel font once painted guillemets as tofu. The requirement behind
	# that choice, not the choice: whatever pair ships (the .tres AND the .gd defaults a locale skin falls back to)
	# must be two DIFFERENT glyphs — or a cycler cannot say which way it steps — that the font the Options Buttons
	# actually paint with can render. Read off the tree _ready built (no open(): nothing here needs the modal up).
	var arrows := _buttons_painting(String(MenuStyle.skin.cycler_prev_glyph))
	assert_gt(arrows.size(), 0, "precondition: the Options tree paints the shipped prev arrow on a cycler row")
	if arrows.is_empty():
		return
	var font: Font = arrows[0].get_theme_font(&"font")
	assert_true(font != null, "precondition: the cycler arrow resolves a theme font")
	if font == null:
		return
	var defaults := MenuSkin.new()
	for pair in [[MenuStyle.skin, "the shipped menu_skin.tres"], [defaults, "MenuSkin's .gd defaults"]]:
		var prev := String(pair[0].cycler_prev_glyph)
		var next := String(pair[0].cycler_next_glyph)
		assert_ne(prev, "", "%s: the prev arrow is not blank" % pair[1])
		assert_ne(next, "", "%s: the next arrow is not blank" % pair[1])
		assert_ne(prev, next, "%s: the two arrows differ, or a cycler cannot show which way it steps" % pair[1])
		for glyph in [prev, next]:
			for i in glyph.length():
				assert_true(font.has_char(glyph.unicode_at(i)),
					"%s: '%s' must be a glyph the menu font renders — a missing one paints as tofu on every cycler row" % [pair[1], glyph])
	defaults = null  # Resource (RefCounted) — release per the project test idiom

func test_every_tab_page_reserves_a_real_scrollbar_gutter() -> void:
	# THE PAGE MUST ADMIT IT SCROLLS. Controls runs 44 rebind rows and Accessibility 33 settings through a
	# ~245px page. Both scrolled; neither said so, because the themed bar was drawn ZERO px wide (see
	# MenuStyle's scrollbar block) — the audit screenshot shows four bindings, a fifth sliced through, and a
	# bare right edge. Two halves are pinned here, and the SECOND is the one that bites:
	#   (a) the bar exists (AUTO: it paints only on a page that really overflows, i.e. Controls — a full-height
	#       track on a six-row Audio page read as a defect), and has a width a mouse can actually hit;
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
		assert_eq(page.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO,
			"%s shows a scrollbar only when it overflows" % page.name)
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


func test_release_build_drops_debug_only_rows() -> void:
	# OS.is_debug_build() is always true under GUT, so the filter takes the flag: the release path must drop
	# every debug_only spec (the two "Debug:" Game-tab rows) and keep the rest in catalog order; the debug path
	# keeps everything. This is what stops the debug toggles from shipping in an export.
	var cat: SettingsCatalog = load("res://resources/settings/SettingsCatalog.tres")
	var debug_rows: Array = OptionsMenu.visible_specs(cat.specs, true)
	var release_rows: Array = OptionsMenu.visible_specs(cat.specs, false)
	assert_eq(debug_rows.size(), cat.specs.size(), "a debug build shows every catalog row")
	assert_eq(release_rows.size(), cat.specs.size() - 2, "a release build drops exactly the two Debug: rows")
	var i := 0
	for spec in release_rows:
		assert_false(spec.debug_only, "no debug_only row survives the release filter: %s" % spec.key)
		while cat.specs[i].debug_only:
			i += 1
		assert_eq(spec, cat.specs[i], "the surviving rows keep catalog order")
		i += 1


## The built row whose label column reads exactly `label_text`: the HBoxContainer _row emitted, whose
## child 0 is that Label and whose child 1 is the control (for a cycler, the prev/value/next box).
func _labelled_row(label_text: String) -> HBoxContainer:
	for n in OptionsMenu._root.find_children("*", "Label", true, false):
		if (n as Label).text == label_text:
			return n.get_parent() as HBoxContainer
	return null

func test_language_row_is_greyed_out_while_english_is_the_only_catalog() -> void:
	# No `.po` is listed under Project Settings -> Localization -> Translations yet, so the Language chooser has
	# exactly ONE true value. A live cycler there would offer "System" and "English" — two captions painting the
	# same English — and buzz (play_denied) on every step, which reads as a broken language menu. So the row is
	# built GREYED at the source locale's own name: the player can read "English, and that is all there is" off
	# the menu itself. Gated on the same count check _emit_language uses, so the day a catalog ships this test
	# goes QUIET instead of red — and the live-cycler branch below is what test_choice_rows_* already covers.
	if Localization.available_locales().size() > 1:
		pass_test("a translation catalog ships — the Language row is live, so there is nothing to grey out")
		return
	OptionsMenu.open()
	var row := _labelled_row("Language")
	assert_not_null(row, "the Game tab still emits a Language row — greyed is VISIBLE, not dropped")
	if row == null:
		OptionsMenu.close()
		return
	var cycler := row.get_child(1) as HBoxContainer
	var value_btn := cycler.get_child(1) as Button
	assert_eq(value_btn.text, Localization.locale_label(Localization.source_locale()),
		"the greyed row states the one language this build speaks, by the engine's own name for it")
	for i in cycler.get_child_count():
		assert_true((cycler.get_child(i) as Button).disabled,
			"every surface of the Language cycler is disabled, so the theme paints all three greyed (child %d)" % i)
	assert_eq(value_btn.focus_mode, Control.FOCUS_NONE, "and D-pad nav walks past the dead row")
	for i in cycler.get_child_count():  # MenuStyle wires its own press SOUND to every button; only the step must be absent
		assert_false(_connects_to(cycler.get_child(i).pressed, &"_cycle_option"),
			"no cycle step is wired to a row that cannot change (child %d)" % i)
	assert_false(_connects_to(value_btn.gui_input, &"_on_cycler_gui_input"),
		"nor the keyboard path: a disabled Button stops emitting `pressed` but still forwards gui_input, which would keep cycling the dead row")
	assert_eq(row.get_child(0).get_theme_color(&"font_color"), MenuStyle.skin.disabled_text_color,
		"the NAME greys with the control — a live-looking label beside a dead cycler reads as a bug, not a limitation")
	OptionsMenu.close()

## True when `sig` has a connection whose target method is `method` — the connection-level twin of "this
## button still steps the cycler", used where MenuStyle's own sound connection makes a bare emptiness check lie.
func _connects_to(sig: Signal, method: StringName) -> bool:
	for c in sig.get_connections():
		if (c["callable"] as Callable).get_method() == method:
			return true
	return false
