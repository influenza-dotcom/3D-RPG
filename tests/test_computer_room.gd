extends GutTest
## Contract: the ComputerRoom intro (project main_scene) hosts the StartMenu at runtime — the menu is
## instanced under the CanvasLayer, drawn ABOVE the CRT post-process rect, with its skin backdrop off so
## the 3D room shows behind the buttons. Pins the boot seam without actually loading the game.

func test_project_boots_computer_room() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/run/main_scene")), "res://scenes/computerroom.tscn",
		"the computer-room intro is the project main scene")

func test_computer_room_hosts_start_menu() -> void:
	var scene := load("res://scenes/computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	# Same isolation as test_start_menu: force startup gates into the normal accepted-install path.
	var prev_skip: bool = Settings.debug_skip_menu
	var prev_tos: bool = Settings.tos_accepted
	var prev_debug_always_show_tos: bool = Settings.debug_always_show_tos
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	Settings.debug_always_show_tos = false
	var inst := scene.instantiate()
	add_child_autofree(inst)
	var menu := inst.get_node_or_null("CanvasLayer/StartMenu") as Control
	assert_not_null(menu, "StartMenu instanced under the CanvasLayer at runtime")
	if menu != null:
		assert_true("show_background" in menu,
			"StartMenu exposes show_background (the duck-typed .set target in computerroom.gd)")
		assert_false(bool(menu.get(&"show_background")), "hosted menu suppresses the skin backdrop")
		# The menu must be the LAST canvas child: add_child appends it after the post-process ColorRect,
		# which is what keeps the buttons crisp (above the shader) and clickable (first in mouse order).
		var canvas: Node = inst.get_node("CanvasLayer")
		assert_eq(canvas.get_child(canvas.get_child_count() - 1), menu,
			"menu draws above the CRT post-process rect (last CanvasLayer child)")
		assert_true((canvas as CanvasLayer).visible, "CanvasLayer is visible immediately for the startup warning")
		assert_true(menu.visible, "StartMenu is visible immediately so its black warning is the first frame")
		assert_true("wait_for_host_boot" in menu,
			"hosted StartMenu exposes wait_for_host_boot (the duck-typed .set target in computerroom.gd)")
		assert_true(bool(menu.get(&"wait_for_host_boot")), "hosted menu waits for the computer-room boot after gates")
		assert_false(inst._startup_gate_done, "computer-room timer/audio stay gated while the warning is active")
		assert_true(inst.startup_timer.is_stopped(), "room startup timer is stopped until the menu gate clears")
		assert_false(inst.turn_on.playing, "turn-on sound is silent behind the startup warning")
		assert_false(inst.fan.playing, "fan hum is silent behind the startup warning")
		assert_false(inst.buzz.playing, "buzz is silent until the monitor actually powers on")
		inst._on_timer_timeout()
		assert_false(inst.turn_on.playing, "timer timeout before the gate cannot start room audio")
		assert_false(inst.fan.playing, "timer timeout before the gate cannot start fan audio")
	Settings.debug_skip_menu = prev_skip
	Settings.tos_accepted = prev_tos
	Settings.debug_always_show_tos = prev_debug_always_show_tos

func test_computer_room_reveals_menu_on_click_or_key_press() -> void:
	var scene := load("res://scenes/computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	var prev_skip: bool = Settings.debug_skip_menu
	var prev_tos: bool = Settings.tos_accepted
	var prev_debug_always_show_tos: bool = Settings.debug_always_show_tos
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	Settings.debug_always_show_tos = false

	var click_inst := scene.instantiate()
	add_child_autofree(click_inst)
	var click_menu = click_inst.get_node("CanvasLayer/StartMenu")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click_inst._input(click)
	assert_false(click_inst.monitor_glow.visible, "clicks during the startup warning do not power the monitor")
	click_menu._skip_internet_warning()
	click_inst._input(click)
	assert_false(click_inst.monitor_glow.visible, "the warning-dismiss click cannot also skip the room intro")
	click_inst._release_startup_input_lock()
	click_inst._input(click)
	assert_true(click_inst.monitor_glow.visible, "left-click powers on the computer-room monitor after the gate")
	assert_true((click_inst.get_node("CanvasLayer/StartMenu") as Control).visible,
		"left-click reveals the hosted StartMenu")

	var key_inst := scene.instantiate()
	add_child_autofree(key_inst)
	var key_menu = key_inst.get_node("CanvasLayer/StartMenu")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	key_menu._skip_internet_warning()
	key_inst._release_startup_input_lock()
	key_inst._input(key)
	assert_true(key_inst.monitor_glow.visible, "any key press powers on the computer-room monitor after the gate")
	assert_true((key_inst.get_node("CanvasLayer/StartMenu") as Control).visible,
		"any key press reveals the hosted StartMenu")

	var echo := InputEventKey.new()
	echo.keycode = KEY_SPACE
	echo.pressed = true
	echo.echo = true
	assert_false(key_inst._is_boot_skip_event(echo), "key-repeat echo should not retrigger the title intro")
	Settings.debug_skip_menu = prev_skip
	Settings.tos_accepted = prev_tos
	Settings.debug_always_show_tos = prev_debug_always_show_tos

## Regression: skipping the boot while the ~7s turn-on sound is mid-play used to leave the sound running, and its
## later natural "finished" signal (wired to _on_turn_on_finished in computerroom.tscn) ran the reveal a SECOND
## time — resetting the visible menu's modulate.a to 0 and re-fading it (a split-second menu blackout). The skip
## now stops the sound and the handler latches on the lit monitor, so a stray finished must leave the menu alone.
func test_turn_on_finished_after_skip_does_not_reblink_menu() -> void:
	var scene := load("res://scenes/computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	var prev_skip: bool = Settings.debug_skip_menu
	var prev_tos: bool = Settings.tos_accepted
	var prev_debug_always_show_tos: bool = Settings.debug_always_show_tos
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	Settings.debug_always_show_tos = false

	var inst := scene.instantiate()
	add_child_autofree(inst)
	var menu = inst.get_node("CanvasLayer/StartMenu")
	# Drive the real boot order: warning skipped -> shield released -> timer fired (turn-on sound now playing) ->
	# the player skips mid-sound. This is the exact window that produced the double reveal.
	menu._skip_internet_warning()
	inst._release_startup_input_lock()
	inst._on_timer_timeout()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	inst._input(click)
	assert_true(inst.monitor_glow.visible, "a mid-sound skip powers the monitor immediately")
	assert_false(inst.turn_on.playing, "the skip stops the still-playing turn-on sound (stop() emits no finished)")
	# Simulate the fade having completed, then fire the stray late signal through the REAL scene connection: the
	# latched handler must leave the fully-visible menu untouched.
	(menu as Control).modulate.a = 1.0
	inst.turn_on.finished.emit()
	assert_eq((menu as Control).modulate.a, 1.0,
		"a late turn-on finished signal must not reset the visible menu's fade (the split-second menu blink)")
	assert_true(inst.buzz.playing,
		"the CRT whine keeps playing at the open menu — the stray signal must not stop (or restart) the bed")
	assert_true(inst.turn_on.finished.is_connected(Callable(inst, &"_on_turn_on_finished")),
		"scene wiring contract: TurnOn.finished feeds _on_turn_on_finished (the latch is what makes that safe)")
	Settings.debug_skip_menu = prev_skip
	Settings.tos_accepted = prev_tos
	Settings.debug_always_show_tos = prev_debug_always_show_tos

func test_computer_room_audio_routes_to_sfx_bus() -> void:
	var scene := load("res://scenes/computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	var inst := scene.instantiate()
	add_child_autofree(inst)
	for path in [^"computer/TurnOn", ^"computer/Buzz", ^"computer/Fan"]:
		var player := inst.get_node(path) as AudioStreamPlayer3D
		assert_eq(player.bus, &"sfx",
			"computer-room SFX players must route to the SFX bus so stop_sfx() cuts them on Continue/Begin")

## The boot soundscape contract (authored in each .mp3.import, so a careless reimport can silently break it):
## dark screen + ONE-SHOT pc-startup sfx -> monitor light + LOOPING CRT whine as the menu opens, whine playing for
## as long as the player sits there. The startup sound must NOT loop — its finished signal is what reveals the menu
## on the patient path, and a looping stream never emits finished (a soft-locked boot). The whine/fan bed MUST loop
## — non-looping streams would fall silent at the menu after one pass.
func test_boot_soundscape_loop_contract() -> void:
	var scene := load("res://scenes/computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	var inst := scene.instantiate()
	add_child_autofree(inst)
	assert_false((inst.turn_on.stream as AudioStreamMP3).loop,
		"the pc-startup sfx is one-shot: finished must fire, or the menu never reveals without a skip")
	assert_true((inst.buzz.stream as AudioStreamMP3).loop,
		"the CRT whine loops: it keeps playing the whole time the player sits at the menu")
	assert_true((inst.fan.stream as AudioStreamMP3).loop,
		"the fan hum loops: the room bed never falls silent at the menu")

## Regression: Options -> Main Menu used to change_scene to the BARE start_menu.tscn, whose only backdrop is the
## skin's flat near-black colour — the buttons sat on a permanently black screen. The button now returns to THIS
## room with MenuStyle's warm-return mark set, and a warm boot comes up already powered on: monitor lit, whine +
## fan beds running, no timer, no turn-on whine, the menu's internet-warning cards skipped and the buttons revealed
## at once. The mark is one-shot, so a later real launch is cold again.
func test_warm_return_from_in_game_boots_the_room_already_lit() -> void:
	var scene := load("res://scenes/computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	var prev_skip: bool = Settings.debug_skip_menu
	var prev_tos: bool = Settings.tos_accepted
	var prev_debug_always_show_tos: bool = Settings.debug_always_show_tos
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	Settings.debug_always_show_tos = false

	MenuStyle.mark_warm_menu_return()
	var inst := scene.instantiate()
	add_child_autofree(inst)
	var menu = inst.get_node("CanvasLayer/StartMenu")
	assert_true(inst._warm_return, "the room consumed the warm-return mark in _ready")
	assert_false(MenuStyle.take_warm_menu_return(), "the mark is one-shot: consumed by this boot, a relaunch is cold")
	assert_true(bool(menu.get(&"warm_return")), "the hosted menu is told this is a warm return")
	assert_true(inst.monitor_glow.visible, "a warm room is lit before the menu is even built")
	assert_true(inst.ambient_dust.visible, "the dust is up with the lit monitor")
	assert_true(inst.buzz.playing, "the CRT whine bed runs from the first frame of a warm return")
	assert_true(inst.fan.playing, "the fan hums like a room that went through the timer")
	assert_true(inst.startup_timer.is_stopped(), "no turn-on timer on a warm return")
	assert_false(inst.turn_on.playing, "no ~7s turn-on whine on a warm return")
	assert_true(inst._startup_gate_done, "the menu released the gate synchronously (no internet-warning cards to wait out)")
	assert_false(menu._internet_warning_active, "the internet-warning cards are a per-launch ritual, skipped on a return")
	assert_false(menu._black.visible, "no black warning cover over a warm return")
	assert_true(menu._buttons.visible, "the menu buttons are revealed at once on a warm return")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "the mouse is free over the returned menu")
	Settings.debug_skip_menu = prev_skip
	Settings.tos_accepted = prev_tos
	Settings.debug_always_show_tos = prev_debug_always_show_tos

## A cold launch must be untouched by the warm-return seam: no mark -> the room boots gated and dark exactly as before.
func test_cold_launch_is_not_warm() -> void:
	var scene := load("res://scenes/computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	var prev_skip: bool = Settings.debug_skip_menu
	var prev_tos: bool = Settings.tos_accepted
	var prev_debug_always_show_tos: bool = Settings.debug_always_show_tos
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	Settings.debug_always_show_tos = false
	MenuStyle.take_warm_menu_return()  # drain any stray mark
	var inst := scene.instantiate()
	add_child_autofree(inst)
	var menu = inst.get_node("CanvasLayer/StartMenu")
	assert_false(inst._warm_return, "no mark -> a cold boot")
	assert_false(bool(menu.get(&"warm_return")), "the hosted menu boots cold")
	assert_false(inst.monitor_glow.visible, "a cold room starts dark")
	assert_false(inst.buzz.playing, "no whine bed before the monitor powers on")
	assert_true(menu._internet_warning_active, "the internet-warning cards play on a cold launch")
	Settings.debug_skip_menu = prev_skip
	Settings.tos_accepted = prev_tos
	Settings.debug_always_show_tos = prev_debug_always_show_tos

## Source pin: the Options "Main Menu" button must target the ROOM (with the warm mark), never the bare menu scene —
## that bare scene's flat skin backdrop is the permanently-black main menu this seam exists to prevent.
func test_options_main_menu_returns_to_the_computer_room() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/options_menu.gd")
	var start := src.find("func _on_main_menu()")
	assert_true(start >= 0, "options_menu.gd defines _on_main_menu")
	if start < 0:
		return
	var end := src.find("
func ", start + 1)
	var body := src.substr(start, (end - start) if end > start else -1)
	assert_true(body.contains('change_scene_faded("res://scenes/computerroom.tscn")'),
		"Main Menu changes scene to the computer room (the lit 3D backdrop), not the bare start_menu.tscn — and through the fade, never as a hard cut")
	assert_false(body.contains("start_menu.tscn"),
		"Main Menu must not load start_menu.tscn standalone — its flat skin backdrop is a black screen")
	assert_true(body.contains("MenuStyle.mark_warm_menu_return()"),
		"Main Menu marks the boot warm so the room skips the turn-on ritual and the warning cards")
