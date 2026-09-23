extends GutTest
## Contract: the ComputerRoom intro (project main_scene) hosts the StartMenu at runtime — the menu is
## instanced under the CanvasLayer, drawn ABOVE the CRT post-process rect, with its skin backdrop off so
## the 3D room shows behind the buttons. Pins the boot seam without actually loading the game.

const ROOM_SCENE := "res://scenes/computerroom.tscn"

var _prev_skip: bool
var _prev_tos: bool
var _prev_debug_always_show_tos: bool
var _prev_mouse_mode: Input.MouseMode
var _prev_scene_fade_running: bool
var _prev_quiet_backs: int
## The runner's own current scene: null under `-s gut_cmdln.gd`, the GUT runner scene in the editor's GUT panel. The
## driven Main Menu swap parks it (so the swap has nothing to free) and after_each puts it back.
var _prev_current_scene: Node = null
## The driven swap's recorder on SceneTree.scene_changed. after_each disconnects it, so a failed or timed-out swap test
## can never leave a lambda listening to a later suite's scene changes.
var _swap_recorder: Callable = Callable()

func before_each() -> void:
	# Same isolation as test_start_menu: force the startup gates into the normal accepted-install path. Restored in
	# after_each so a failing assert can never leak a skipped ToS / skipped menu into a later suite.
	_prev_skip = Settings.debug_skip_menu
	_prev_tos = Settings.tos_accepted
	_prev_debug_always_show_tos = Settings.debug_always_show_tos
	_prev_mouse_mode = Input.mouse_mode
	_prev_scene_fade_running = MenuStyle._scene_fade_running
	_prev_quiet_backs = MenuStyle._quiet_backs
	_prev_current_scene = get_tree().current_scene
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	Settings.debug_always_show_tos = false
	MenuStyle.take_warm_menu_return()  # drain any stray mark so every boot below starts from a known cold state

func after_each() -> void:
	Settings.debug_skip_menu = _prev_skip
	Settings.tos_accepted = _prev_tos
	Settings.debug_always_show_tos = _prev_debug_always_show_tos
	Input.mouse_mode = _prev_mouse_mode
	MenuStyle._scene_fade_running = _prev_scene_fade_running
	MenuStyle._quiet_backs = _prev_quiet_backs
	MenuStyle.take_warm_menu_return()
	# A room the driven Main Menu swap landed as the current scene is freed here, and the runner's value restored, so
	# the swapped-in room (menus, audio beds and all) never outlives its test even when an assert above failed.
	var landed := get_tree().current_scene
	if landed != _prev_current_scene:
		get_tree().current_scene = _prev_current_scene if is_instance_valid(_prev_current_scene) else null
		if is_instance_valid(landed):
			landed.free()
	_prev_current_scene = null
	if _swap_recorder.is_valid() and get_tree().scene_changed.is_connected(_swap_recorder):
		get_tree().scene_changed.disconnect(_swap_recorder)
	_swap_recorder = Callable()
	# MenuStyle's cover (the autoload keeps it for the whole session) goes back to its resting state: hidden and fully
	# transparent. A transition that failed or timed out mid-way must not leave a STOP-filter rect at layer 200 eating
	# input over later suites, or a half-black alpha that test_menu_style's cover-colour check would trip on.
	if is_instance_valid(MenuStyle._fade_rect):
		MenuStyle._fade_rect.visible = false
		MenuStyle._fade_rect.color.a = 0.0

## Instance the real room scene into the test tree (its _ready runs the boot), or null when the scene won't load.
func _boot_room() -> Node:
	var scene := load(ROOM_SCENE) as PackedScene
	assert_not_null(scene, "computerroom.tscn should load")
	if scene == null:
		return null
	var inst := scene.instantiate()
	add_child_autofree(inst)
	return inst

func test_project_boots_computer_room() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/run/main_scene")), ROOM_SCENE,
		"the computer-room intro is the project main scene")

func test_computer_room_hosts_start_menu() -> void:
	var inst := _boot_room()
	if inst == null:
		return
	var menu := inst.get_node_or_null("CanvasLayer/StartMenu") as Control
	assert_not_null(menu, "StartMenu instanced under the CanvasLayer at runtime")
	if menu == null:
		return
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

func test_computer_room_reveals_menu_on_click_or_key_press() -> void:
	var click_inst := _boot_room()
	if click_inst == null:
		return
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

	var key_inst := _boot_room()
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

## Regression: skipping the boot while the ~7s turn-on sound is mid-play used to leave the sound running, and its
## later natural "finished" signal (wired to _on_turn_on_finished in computerroom.tscn) ran the reveal a SECOND
## time — resetting the visible menu's modulate.a to 0 and re-fading it (a split-second menu blackout). The skip
## now stops the sound and the handler latches on the lit monitor, so a stray finished must leave the menu alone.
func test_turn_on_finished_after_skip_does_not_reblink_menu() -> void:
	var inst := _boot_room()
	if inst == null:
		return
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

func test_computer_room_audio_routes_to_sfx_bus() -> void:
	var inst := _boot_room()
	if inst == null:
		return
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
	var inst := _boot_room()
	if inst == null:
		return
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
	MenuStyle.mark_warm_menu_return()
	var inst := _boot_room()
	if inst == null:
		return
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

## A cold launch must be untouched by the warm-return seam: no mark -> the room boots gated and dark exactly as before.
func test_cold_launch_is_not_warm() -> void:
	var inst := _boot_room()
	if inst == null:
		return
	var menu = inst.get_node("CanvasLayer/StartMenu")
	assert_false(inst._warm_return, "no mark -> a cold boot")
	assert_false(bool(menu.get(&"warm_return")), "the hosted menu boots cold")
	assert_false(inst.monitor_glow.visible, "a cold room starts dark")
	assert_false(inst.buzz.playing, "no whine bed before the monitor powers on")
	assert_true(menu._internet_warning_active, "the internet-warning cards play on a cold launch")

## Options -> Main Menu, DRIVEN: pressing the button arms the warm-return mark, and the room the player lands in
## boots already lit on it. The scene swap itself is held back here by MenuStyle's own re-entrancy latch (a fade
## "already running" makes change_scene_faded a no-op), so this isolates the mark from the swap; the next test lets
## the swap run for real and frees the room it lands.
func test_options_main_menu_lands_the_player_in_a_lit_room() -> void:
	assert_false(OptionsMenu.is_open(), "precondition: Options is closed, so its close() inside the handler is a no-op")
	assert_false(MenuStyle.take_warm_menu_return(), "control: before the press nothing has marked the next boot warm")
	MenuStyle._scene_fade_running = true  # hold the real scene swap (see the doc above); restored in after_each
	OptionsMenu._on_main_menu()
	var inst := _boot_room()
	if inst == null:
		return
	assert_true(inst._warm_return,
		"the room reached from Options -> Main Menu must boot WARM — a cold boot replays the black warning cards and the turn-on whine mid-session")
	assert_true(inst.monitor_glow.visible, "...so the monitor is lit the moment the player arrives, never a black screen")

## Options -> Main Menu, the swap itself DRIVEN end to end. Regressions this catches: the button once swapped to the
## BARE start_menu.tscn, whose only backdrop is the skin's flat near-black colour (a permanently black main menu), and
## a hard cut straight onto the next scene instead of MenuStyle.change_scene_faded (09-14: the black cover lives on
## the autoload because it is the only node that survives the swap). The press must raise the cover while it is still
## see-through, swap only once the cover has faded all the way to black, land the computer room UNDER it already lit,
## and then lift the cover.
## The swap's ordering is read AT the swap: a one-shot recorder on SceneTree.scene_changed (emitted by the engine's
## scene flush, right after the new scene is added) snapshots the cover. Counting frames or polling afterwards would
## depend on frame timing, because the tweens step by real frame delta and a slow frame can finish a whole fade in one
## step. The runner's current scene is parked to null for the swap so there is nothing for it to free; after_each frees
## the room it lands, restores the runner's value, disconnects the recorder and rests the cover.
func test_options_main_menu_fades_to_black_and_lands_in_the_computer_room() -> void:
	assert_false(OptionsMenu.is_open(), "precondition: Options is closed, so its close() inside the handler is a no-op")
	assert_false(MenuStyle._scene_fade_running,
		"precondition: no transition is running, so MenuStyle's re-entrancy latch cannot swallow the press")
	# Let a frame or two pass before the press. A tween steps by real frame delta, and the frame the runner starts a
	# test on can be slow (script load, the previous test's room boot); a fade-out starting on that frame can finish in
	# one step, which would hide a swap that no longer waits for the fade. The green path does not depend on this wait.
	await wait_process_frames(2)
	get_tree().current_scene = null  # restored in after_each
	var at_swap := {}
	_swap_recorder = func() -> void:
		if not at_swap.is_empty():
			return
		var rect := MenuStyle._fade_rect
		at_swap["cover_up"] = is_instance_valid(rect) and rect.visible
		at_swap["alpha"] = rect.color.a if is_instance_valid(rect) else -1.0
	get_tree().scene_changed.connect(_swap_recorder)
	OptionsMenu._on_main_menu()
	var cover := MenuStyle._fade_rect
	assert_true(cover != null and cover.visible, "the press raises MenuStyle's black cover before anything swaps")
	assert_true(cover != null and cover.color.a < 1.0,
		"control: right after the press the cover is still see-through, so reaching full black at the swap takes a real fade-out")
	var landed: bool = await wait_until(func() -> bool: return get_tree().current_scene != null, 5.0)
	if get_tree().scene_changed.is_connected(_swap_recorder):
		get_tree().scene_changed.disconnect(_swap_recorder)
	assert_true(landed, "the swap lands once the fade to black has finished")
	assert_false(at_swap.is_empty(), "the swap was observed as it landed (SceneTree.scene_changed fired for it)")
	assert_true(bool(at_swap.get("cover_up", false)),
		"the room arrives UNDER the black cover, never as a bare cut (change_scene_to_file straight from the button)")
	assert_almost_eq(float(at_swap.get("alpha", -1.0)), 1.0, 0.001,
		"the swap waits for the cover to reach full black; swapping mid-fade shows the old scene half-dark")
	var room := get_tree().current_scene
	if room != null:
		assert_eq(room.scene_file_path, ROOM_SCENE,
			"Main Menu lands in the computer room (the lit 3D backdrop), not the bare start_menu.tscn and its black skin backdrop")
		if room.scene_file_path == ROOM_SCENE:
			assert_true(room._warm_return, "the room consumed the warm-return mark the press set, so it boots warm")
			assert_true(room.monitor_glow.visible,
				"the monitor is lit the moment the room arrives — no black warning cards or turn-on whine mid-session")
	var finished: bool = await wait_until(func() -> bool: return not MenuStyle._scene_fade_running, 5.0)
	assert_true(finished, "the transition runs to completion")
	assert_false(is_instance_valid(cover) and cover.visible,
		"the cover lifts off the arrived room — a STOP-filter rect left parked over the menu would eat every click")
