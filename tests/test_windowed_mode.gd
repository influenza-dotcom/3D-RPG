extends GutTest
## Contract: WINDOWED mode must stay playable. Two seams, both of which broke the game for a real player who
## picked Windowed in Options (2026-08-16):
##  1. project.godot `display/window/size/no_focus` — ON, Godot's Windows DisplayServer strips WS_VISIBLE and
##     answers clicks with MA_NOACTIVATE for the main window the moment it leaves fullscreen, so the game window
##     VANISHES and cannot be focused (fullscreen masks it, which is how the flag shipped unnoticed since the first
##     commit). It is one editor checkbox away from coming back (Project Settings > Display > Window > No Focus).
##  2. Settings' windowed placement — a windowed_size the size of the monitor (the 1920x1080 preset on a 1080p
##     screen) landed the title bar above the screen with resizable=false + maximize_disabled leaving no way back;
##     Settings.fitting_resolutions is the pure rule both the Options row and apply_video now share.
##  3. The cost of rule 2, reported 2026-08-20: hiding every preset whose DECORATED frame overflows the screen left
##     a 1080p player THREE window sizes and no native one. The ladder is denser now and a preset that only fits
##     without the caption + borders is placed BORDERLESS (Settings.needs_borderless) instead of being dropped.
## Everything here runs headless: ProjectSettings reads project.godot, the fit rule is pure, and a bare Settings
## instance has no window (get_window() null), which is exactly the "nothing to measure against" fallback path.

func test_project_window_is_focusable() -> void:
	# ProjectSettings returns the stored value or the fallback; a missing key = the engine default = false.
	var v = ProjectSettings.get_setting("display/window/size/no_focus", false)
	assert_false(v == true,
		"project.godot display/window/size/no_focus must stay OFF: a no_focus main window goes invisible + "
		+ "unclickable in Windowed mode on Windows (see managers/Settings.gd apply_video). Untick "
		+ "Project Settings > Display > Window > No Focus.")

func test_windowed_is_the_first_window_mode() -> void:
	# The Options row's index 0 == Windowed; the fit/centre path in apply_video keys off MODE_WINDOWED.
	var script := load("res://managers/Settings.gd")
	assert_eq(int(script.WINDOW_MODES[0]), int(Window.MODE_WINDOWED), "WINDOW_MODES[0] is Windowed")
	assert_eq(script.RESOLUTIONS.size(), 12, "twelve ~16:9 windowed presets (640x360 .. 3840x2160)")
	assert_true(script.RESOLUTIONS.has(Vector2i(1920, 1080)),
		"the most common native size is a preset (offered borderless on a screen that cannot decorate it)")
	var ascending := true
	for i in range(1, script.RESOLUTIONS.size()):
		ascending = ascending and script.RESOLUTIONS[i].x > script.RESOLUTIONS[i - 1].x
	assert_true(ascending, "presets ascend — the Options cycler steps small-to-large, and fitting_resolutions "
		+ "preserves the order so its last entry is its largest")
	for r in script.RESOLUTIONS:
		# ~16:9 (1366x768 is the one classic near-miss): the fit fallback swaps between presets, so they must
		# share the canvas shape or the swap would change the picture, not just its size.
		assert_true(r is Vector2i and absf(float(r.x) / float(r.y) - 16.0 / 9.0) < 0.01,
			"preset %s is ~16:9 (the canvas keeps its shape when apply_video falls back between presets)" % [r])

func test_fitting_resolutions_keeps_only_presets_that_fit_with_decorations() -> void:
	var script := load("res://managers/Settings.gd")
	var presets: Array[Vector2i] = []
	presets.assign(script.RESOLUTIONS)
	# A 1920x1080 monitor with a 40 px taskbar and a 6x29 caption/border frame (the measured Windows 10 numbers):
	# 1920x1080 must NOT fit (it is the case that parked the caption off-screen), 1600x900 is the biggest that does.
	var fits: Array = script.fitting_resolutions(presets, Vector2i(1920, 1040), Vector2i(6, 29))
	assert_eq(fits, [Vector2i(640, 360), Vector2i(854, 480), Vector2i(960, 540), Vector2i(1024, 576),
			Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900)],
		"1080p work area + decorations: every preset that fits DECORATED, in ascending order (1920x1080 needs the "
		+ "borderless rule below, and nothing above it fits at all)")
	# Decorations count: 1600x900 fits a bare 1606x929 usable area but not one pixel less in either axis.
	assert_eq(script.fitting_resolutions(presets, Vector2i(1606, 929), Vector2i(6, 29)).back(), Vector2i(1600, 900),
		"the decorated frame is compared, not the bare client size")
	assert_eq(script.fitting_resolutions(presets, Vector2i(1605, 929), Vector2i(6, 29)).back(), Vector2i(1366, 768),
		"one pixel too narrow for the decorated 1600x900 frame drops it")
	# A small screen keeps only the low rungs (the reason the ladder starts well below 720p).
	assert_eq(script.fitting_resolutions(presets, Vector2i(1024, 768), Vector2i(6, 29)),
		[Vector2i(640, 360), Vector2i(854, 480), Vector2i(960, 540)],
		"a 1024x768 work area fits the three smallest presets decorated (1024x576 needs 1030 px of width)")
	# Nothing fits on a screen smaller than the smallest preset -> empty (callers pick their own fallback).
	assert_eq(script.fitting_resolutions(presets, Vector2i(320, 240), Vector2i(6, 29)).size(), 0,
		"a 320x240 screen fits no preset")
	# A 4K work area fits every preset; the input order is preserved.
	assert_eq(script.fitting_resolutions(presets, Vector2i(3840, 2160), Vector2i.ZERO), presets,
		"a 4K screen offers every preset in the authored order")

func test_fit_windowed_size_keeps_shrinks_or_clamps() -> void:
	var script := load("res://managers/Settings.gd")
	var presets: Array[Vector2i] = []
	presets.assign(script.RESOLUTIONS)
	var deco := Vector2i(6, 29)
	# Fits -> unchanged (this is the common path: nothing to heal).
	assert_eq(script.fit_windowed_size(Vector2i(1280, 720), Vector2i(1920, 1080), deco, presets), Vector2i(1280, 720),
		"a size that fits is returned as-is")
	# The player's real case: 1920x1080 on a 1920x1080 screen -> the largest preset that fits, 1600x900.
	assert_eq(script.fit_windowed_size(Vector2i(1920, 1080), Vector2i(1920, 1080), deco, presets), Vector2i(1600, 900),
		"the monitor-sized preset re-fits to the largest preset that fits with decorations")
	# 'Largest' is by AREA, not list order: a shuffled preset list gives the same answer.
	var shuffled: Array[Vector2i] = [Vector2i(3840, 2160), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1366, 768)]
	assert_eq(script.fit_windowed_size(Vector2i(1920, 1080), Vector2i(1920, 1080), deco, shuffled), Vector2i(1600, 900),
		"largest fitting preset is chosen by area, independent of RESOLUTIONS order")
	# A screen that fits SOME preset takes the largest of them rather than a clamp.
	assert_eq(script.fit_windowed_size(Vector2i(1920, 1080), Vector2i(1024, 768), deco, presets), Vector2i(960, 540),
		"a 1024x768 work area re-fits to the largest preset it can decorate")
	# Nothing fits -> clamp to the usable client area (a screen smaller than every preset).
	assert_eq(script.fit_windowed_size(Vector2i(1920, 1080), Vector2i(600, 400), deco, presets), Vector2i(594, 371),
		"when no preset fits the size is clamped to usable minus decorations")

## The 2026-08-20 report: "there's a very small amount of resolutions, no 1920x1080?" — on a 1080p monitor the
## decorated rule can never offer the native size (1926x1109 of frame on a 1920 px screen), so it is offered as a
## BORDERLESS window instead. Same rule, one screen argument.
func test_native_size_is_offered_and_kept_as_a_borderless_window() -> void:
	var script := load("res://managers/Settings.gd")
	var presets: Array[Vector2i] = []
	presets.assign(script.RESOLUTIONS)
	var deco := Vector2i(6, 29)
	var usable := Vector2i(1920, 1040)   # 1080p with a 40 px taskbar
	var screen := Vector2i(1920, 1080)   # ...and the physical panel behind it
	var fits: Array = script.fitting_resolutions(presets, usable, deco, screen)
	assert_true(fits.has(Vector2i(1920, 1080)), "the native size is offered on its own monitor")
	assert_false(fits.has(Vector2i(2560, 1440)), "a preset larger than the physical screen is still never offered")
	assert_eq(fits.back(), Vector2i(1920, 1080), "order is preserved, so the native size is the list's last entry")
	# needs_borderless is what tells _place_windowed (and the Options caption) which of those two rules let it in.
	assert_true(script.needs_borderless(Vector2i(1920, 1080), usable, deco, screen),
		"the native size fits only once the caption + borders are dropped")
	assert_false(script.needs_borderless(Vector2i(1600, 900), usable, deco, screen),
		"a preset that fits decorated keeps its title bar")
	assert_false(script.needs_borderless(Vector2i(2560, 1440), usable, deco, screen),
		"a preset bigger than the physical screen is not rescued by dropping the decorations")
	assert_false(script.needs_borderless(Vector2i(1920, 1080), usable, deco, Vector2i.ZERO),
		"no measured screen (headless / bare instance) is never borderless")
	# ...and the fit rule must not shrink it back down on the way to the window.
	assert_eq(script.fit_windowed_size(Vector2i(1920, 1080), usable, deco, presets, screen), Vector2i(1920, 1080),
		"a size that fits the bare screen survives fit_windowed_size instead of dropping to 1600x900")
	assert_eq(script.fit_windowed_size(Vector2i(1920, 1080), usable, deco, presets), Vector2i(1600, 900),
		"without a screen argument the old decorated-only rule still applies")

func test_centred_frame_origin_centres_and_keeps_the_caption_on_screen() -> void:
	var script := load("res://managers/Settings.gd")
	# The measured 1600x900 case: frame 1606x929 in a 1920x1080 work area at origin -> (157, 75).
	assert_eq(script.centred_frame_origin(Rect2i(0, 0, 1920, 1080), Vector2i(1606, 929)), Vector2i(157, 75),
		"decorated frame is centred in the usable rect")
	# A secondary monitor whose work area starts at (1920, 40): centring is relative to ITS origin.
	assert_eq(script.centred_frame_origin(Rect2i(1920, 40, 1920, 1040), Vector2i(1286, 749)), Vector2i(1920 + 317, 40 + 145),
		"centring uses the usable rect's own origin (multi-monitor)")
	# A frame bigger than the usable rect never goes above/left of it (caption stays reachable).
	assert_eq(script.centred_frame_origin(Rect2i(0, 0, 1920, 1080), Vector2i(1926, 1109)), Vector2i(0, 0),
		"an oversize frame is pinned to the usable rect's top-left, never centred off-screen")

func test_available_resolutions_falls_back_to_all_presets_without_a_window() -> void:
	# The Options row must never be empty: a bare Settings has no window (headless too), so it offers the whole
	# preset list rather than nothing.
	var s = load("res://managers/Settings.gd").new()
	var offered: Array = s.available_resolutions()
	assert_eq(offered, Array(s.RESOLUTIONS), "no window to measure against -> every preset is offered")
	assert_eq(offered.get_typed_builtin(), TYPE_VECTOR2I, "returns a typed Array[Vector2i] the row can iterate + find in")
	s.free()

func test_bare_settings_apply_video_is_a_no_op_off_tree() -> void:
	# apply_video is called by every video setter; a bare instance must survive it (get_window() is null) and
	# must not touch the user's real settings.cfg (_loaded stays false so save_settings early-returns).
	var s = load("res://managers/Settings.gd").new()
	s.set_windowed_size(Vector2i(1920, 1080))
	assert_eq(s.windowed_size, Vector2i(1920, 1080), "off-tree there is no screen to fit against, so the value stands")
	s.set_window_mode(0)
	assert_eq(s.window_mode, 0, "window_mode index 0 (Windowed) sticks off-tree")
	assert_false(s._loaded, "a bare instance never persists (save_settings guard)")
	# The Options row asks this per offered preset while building; off-tree there is no screen, so it must answer
	# false rather than reach into a null window (the row would otherwise crash before it could be shown).
	assert_false(s.is_borderless_size(Vector2i(1920, 1080)), "no window to measure -> nothing is borderless")
	s.free()
