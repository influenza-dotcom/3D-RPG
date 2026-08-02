extends GutTest
## Smoke test: the boot scene instantiates and builds its menu (without actually loading the game).

var _prev_skip: bool
var _prev_tos: bool
var _prev_debug_always_show_tos: bool

func before_each() -> void:
	_prev_skip = Settings.debug_skip_menu
	_prev_tos = Settings.tos_accepted
	_prev_debug_always_show_tos = Settings.debug_always_show_tos
	Settings.debug_always_show_tos = false

func after_each() -> void:
	Settings.debug_skip_menu = _prev_skip
	Settings.tos_accepted = _prev_tos
	Settings.debug_always_show_tos = _prev_debug_always_show_tos

func test_start_menu_builds() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	# Isolate this smoke test from the debug straight-to-game boot: debug skip now waits for the startup warning,
	# then auto-loads the game. Force it off here so the test only checks menu construction.
	var prev_skip: bool = Settings.debug_skip_menu
	Settings.debug_skip_menu = false
	var inst := scene.instantiate()
	add_child_autofree(inst)
	# "Continue" is built ONLY when an autosave exists on disk (GameState.has_save_file()) and "Load Game"
	# ONLY when any manual quicksave/slot file does, so the count is environment-dependent: 3 on a clean
	# profile, up to 5 on a lived-in one. Pin against the live conditions instead of a fixed count (we must
	# NOT delete the user's real save files here) — the same disk checks start_menu._build_ui gates on.
	var expected := 3
	if GameState.has_save_file():
		expected += 1
	if GameState.has_quicksave() or _any_manual_slot():
		expected += 1
	assert_eq(inst._buttons.get_child_count(), expected,
		"New Game / Settings / Quit (+ Continue with an autosave, + Load Game with a manual save) buttons built")
	assert_false(inst._loading, "should not be loading until New Game is pressed")
	Settings.debug_skip_menu = prev_skip

## Mirrors start_menu._any_slot_saved (the "Load Game" gate) — duplicated here rather than reached into,
## since the menu instance under test builds before we could stub it.
func _any_manual_slot() -> bool:
	for i in range(1, GameState.SLOT_COUNT + 1):
		if GameState.has_slot(i):
			return true
	return false

func test_internet_warning_plays_each_boot_after_terms_accepted() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true

	var first := scene.instantiate()
	add_child_autofree(first)
	assert_true(first._internet_warning_active, "accepted installs play the internet warning before the menu")
	assert_true(first._black.visible, "internet warning uses the black intro card")

	var second := scene.instantiate()
	add_child_autofree(second)
	assert_true(second._internet_warning_active, "internet warning is per boot, not consumed by tos_accepted")
	assert_true(second._black.visible, "replayed warning is visible on the next menu boot too")

func test_internet_warning_precedes_first_launch_terms() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	Settings.debug_skip_menu = false
	Settings.tos_accepted = false

	var inst := scene.instantiate()
	add_child_autofree(inst)
	assert_true(inst._internet_warning_active, "the internet warning is the first first-launch screen")
	assert_null(inst._terms_screen, "TOS waits until the warning clears")
	assert_false(inst._startup_gate_finished, "the hosted room/menu gate stays closed during the warning")

	inst._skip_internet_warning()
	assert_not_null(inst._terms_screen, "TOS appears after the internet warning on a fresh install")
	assert_false(inst._startup_gate_finished, "the startup gate stays closed until TOS consent")
	assert_false(inst._buttons.visible, "menu buttons remain hidden behind first-launch gates")

## The internet warning is unskippable on a genuine first launch: a first-time player must read the cards before
## the TOS gate. Driven through _input (not _skip_internet_warning) because the skip lives in the input branch.
func test_internet_warning_is_unskippable_on_first_launch() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	Settings.debug_skip_menu = false
	Settings.tos_accepted = false

	var inst := scene.instantiate()
	add_child_autofree(inst)
	assert_false(inst._internet_warning_skippable, "a fresh install cannot skip the warning")

	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.pressed = true
	inst._input(press)
	assert_true(inst._internet_warning_active, "pressing a key does not cut the first-launch warning short")
	assert_null(inst._terms_screen, "the TOS still waits for the cards to finish on their own")
	press = null

func test_internet_warning_is_skippable_once_terms_accepted() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true

	var inst := scene.instantiate()
	add_child_autofree(inst)
	assert_true(inst._internet_warning_skippable, "returning players may skip the warning")

	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.pressed = true
	inst._input(press)
	assert_false(inst._internet_warning_active, "press-anything cuts the warning on an accepted install")
	press = null

func test_internet_warning_waits_until_hosted_menu_is_visible() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true

	var inst := scene.instantiate()
	inst.visible = false
	add_child_autofree(inst)
	assert_true(inst._internet_warning_pending, "hosted hidden menus queue the warning")
	assert_false(inst._internet_warning_active, "hidden hosted menus do not burn through the warning off-screen")
	assert_false(inst._black.visible, "black warning card stays hidden until the menu is revealed")

	inst.visible = true
	assert_false(inst._internet_warning_pending, "revealing the hosted menu consumes the pending warning")
	assert_true(inst._internet_warning_active, "revealing the hosted menu starts the warning")
	assert_true(inst._black.visible, "warning card becomes visible with the hosted menu")

func test_internet_warning_skip_shields_menu_buttons() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true

	var inst := scene.instantiate()
	add_child_autofree(inst)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	inst._input(click)

	assert_false(inst._internet_warning_active, "click skips the internet warning")
	assert_false(inst._loading, "the skip click must not click through into New Game / Continue")
	assert_true(inst._buttons.visible, "menu is revealed after skipping the warning")
	assert_true(inst._menu_input_locked, "menu input stays locked during the reveal shield")
	assert_true(inst._menu_input_shield.visible, "transparent shield catches mouse events over the fresh menu")
	# The SHIELD is the input block, not the disabled flag: buttons wear their final (enabled) look from the
	# first visible frame — the old disabled-until-release approach painted them grey and then popped them to
	# normal at release, the exact flash reveal_hosted_menu's comment records removing. Input is still fully
	# blocked: the shield's full-rect STOP filter eats the mouse, _menu_input_locked swallows key events in
	# _input (asserted behaviourally below), and nothing holds focus yet so focus navigation is inert.
	for child in inst._buttons.get_children():
		if child is BaseButton:
			assert_false((child as BaseButton).disabled, "buttons wear their final enabled look under the shield (no disabled-grey flash)")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	inst._input(key)
	assert_false(inst._loading, "a key press during the reveal shield must not activate a menu button")

	inst._release_menu_input_shield()
	assert_false(inst._menu_input_locked, "shield release unlocks menu input")
	assert_false(inst._menu_input_shield.visible, "shield hides after release")
	for child in inst._buttons.get_children():
		if child is BaseButton:
			assert_false((child as BaseButton).disabled, "buttons stay enabled after the shield releases")
	# MOUSE-FIRST: release must leave NOTHING focused — an auto-focused button read as pre-highlighted and its
	# focus ring fought the mouse hover. Keyboard users opt in: the first ui_down with nothing focused seeds
	# focus on the first button (_seed_focus_on_keyboard_intent), and only navigation keys seed — a bare
	# confirm press at an unfocused menu activates nothing.
	assert_null(inst.get_viewport().gui_get_focus_owner(), "release leaves nothing focused (mouse-first; no pre-highlighted button)")
	var nav := InputEventAction.new()
	nav.action = &"ui_down"
	nav.pressed = true
	inst._input(nav)
	assert_true((inst._buttons.get_child(0) as Control).has_focus(), "the first keyboard navigation press seeds focus on demand")

func test_intro_quote_skips_on_click_or_key_press() -> void:
	var scene := load("res://scenes/start_menu.tscn") as PackedScene
	assert_not_null(scene, "start_menu.tscn should load")
	var prev_skip: bool = Settings.debug_skip_menu
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	var inst := scene.instantiate()
	add_child_autofree(inst)
	if inst._quote_tween != null and inst._quote_tween.is_valid():
		inst._quote_tween.kill()
	inst._internet_warning_active = false
	inst._internet_warning_pending = false
	inst._black.visible = false
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
	Settings.tos_accepted = true
	var inst := scene.instantiate()
	add_child_autofree(inst)
	if inst._quote_tween != null and inst._quote_tween.is_valid():
		inst._quote_tween.kill()
	inst._internet_warning_active = false
	inst._internet_warning_pending = false
	inst._black.visible = false
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
