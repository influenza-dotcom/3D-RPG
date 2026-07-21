extends GutTest
## Contract: the ComputerRoom intro (project main_scene) hosts the StartMenu at runtime — the menu is
## instanced under the CanvasLayer, drawn ABOVE the CRT post-process rect, with its skin backdrop off so
## the 3D room shows behind the buttons. Pins the boot seam without actually loading the game.

func test_project_boots_computer_room() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/run/main_scene")), "res://computerroom.tscn",
		"the computer-room intro is the project main scene")

func test_computer_room_hosts_start_menu() -> void:
	var scene := load("res://computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	# Same isolation as test_start_menu: force startup gates into the normal accepted-install path.
	var prev_skip: bool = Settings.debug_skip_menu
	var prev_tos: bool = Settings.tos_accepted
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
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

func test_computer_room_reveals_menu_on_click_or_key_press() -> void:
	var scene := load("res://computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	var prev_skip: bool = Settings.debug_skip_menu
	var prev_tos: bool = Settings.tos_accepted
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true

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

func test_computer_room_audio_routes_to_sfx_bus() -> void:
	var scene := load("res://computerroom.tscn") as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return
	var inst := scene.instantiate()
	add_child_autofree(inst)
	for path in [^"computer/TurnOn", ^"computer/Buzz", ^"computer/Fan"]:
		var player := inst.get_node(path) as AudioStreamPlayer3D
		assert_eq(player.bus, &"sfx",
			"computer-room SFX players must route to the SFX bus so stop_sfx() cuts them on Continue/Begin")
