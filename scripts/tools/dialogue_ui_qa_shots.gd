extends Node
## Dialogue-UI QA screenshot harness — boots the REAL game, starts a fabricated conversation against a
## live NPC, and photographs every state of the 08-24 box-less dialogue look (subtitle block, response
## column, recap clamp, pinned exit, scrim/veil, the camera's right-of-centre framing) so the layout can
## be judged BY EYE.
##
## WHY: "the dialogue UI covers the screen / the text is too small" is a LOOK bug and no unit test can
## see one — a green suite shipped the 77%-coverage box. This is the honest verification for any change
## to DialogueView / DialogueSettings / the dialogue camera framing.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/dialogue_ui_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://dialogue_ui_qa_shots. Prints one QA_SHOT per capture.
##
## The conversation content here is QA-ONLY copy (this file is in ScanText.SKIP_FILES, the debug-overlay
## rule): it exists to exercise one of each row species — plain, passing stat gate, failed non-stat gate,
## long-enough-to-wrap — plus the synthesized Goodbye, never to ship.
##
## Driver-copy pattern, copied from muzzle_smoke_qa_shots.gd: this scene is the boot scene, but the run
## switches current_scene to game.tscn (which frees the current scene), so _ready re-attaches a COPY of
## this script on a bare Node parented to root, which survives the change and drives the run.
##
## (*) NEVER call a Settings.set_* here — those setters call save_settings() and would rewrite the
## developer's real user://settings.cfg. The text-scale shot writes the FIELD directly (no persist) and
## restores it before quitting.

var _dir := "user://dialogue_ui_qa_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "DialogueUiQaDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1584, 888))  # 2x the 792x444 UI canvas, so type reads at true proportion
	await _frames(5)

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(150)  # level loads, ps1 applier walks, nav bakes, sky title fades

	var player := Groups.human_player(get_tree())
	if player == null:
		print("QA_FAIL no Player in the tree")
		get_tree().quit(1)
		return
	# Any live character works as the speaker — the conversation freezes them, keys the face light, and
	# gives the right-of-centre camera framing something real to frame.
	var speaker: Node3D = null
	for n in get_tree().get_nodes_in_group(Groups.NPC):
		if n is Node3D and is_instance_valid(n):
			speaker = n
			break
	if speaker == null:
		print("QA_FAIL no NPC to talk to")
		get_tree().quit(1)
		return
	# Stand the player in front of the speaker at conversational range, then swing the camera exactly the
	# way the talk interaction would (focus_camera_on carries the new dialogue_frame_offset_deg bias).
	var face := -speaker.global_transform.basis.z
	player.global_position = speaker.global_position + face * 2.4
	if player.has_method(&"focus_camera_on"):
		player.focus_camera_on(speaker.global_position + Vector3.UP * 1.6)
	await _frames(30)

	_hide_qa_noise()
	await _shot("00_scene_before")

	DialogueManager.start(_qa_dialogue(), speaker, null, "Old Man")
	await _wait(GameSettings.dialogue.dialogue_intro_delay + GameSettings.dialogue.letterbox_slide_in_duration + 0.3)
	await _shot("01_line_full")  # subtitle block: header row + 26px outlined line over scrim/veil, NO bars

	DialogueManager._on_advance_click()  # linear line -> next line
	await _wait(0.4)
	await _shot("02_line_two")

	DialogueManager._on_advance_click()  # -> decision line, shown listen-first (hint only)
	await _wait(0.3)
	DialogueManager._on_advance_click()  # the line's been heard -> NOW the response column reveals
	await _frames(10)
	await _shot("03_menu_open")  # numbered rows on beds, caret'd Goodbye pinned under the hairline, recap clamp

	# The digit path: select row 2 exactly as the 1-9 keys would (press_numbered_choice is what
	# DialogueManager._unhandled_input drives off the hotbar-slot actions).
	DialogueManager._view.press_numbered_choice(2)
	await _wait(0.4)
	await _shot("04_after_digit_pick")

	# The digit pick CONTINUEd past the last line, ending the conversation — restart for the second-menu shot.
	DialogueManager.start(_qa_dialogue(), speaker, null, "Old Man")
	await _wait(GameSettings.dialogue.dialogue_intro_delay + 0.6)
	for i in 3:  # line1 -> line2 -> decision(listen) -> menu
		if DialogueManager.is_active():
			DialogueManager._on_advance_click()
		await _wait(0.25)
	await _frames(10)
	await _shot("05_menu_again")

	# Accessibility text-scale, field write ONLY (see the (*) warning above) — the next open re-reads it.
	var prior_scale := Settings.dialogue_text_scale
	Settings.dialogue_text_scale = 1.3
	DialogueManager._view.press_exit_choice()  # Goodbye -> closes
	await _frames(10)
	DialogueManager.start(_qa_dialogue(), speaker, null, "Old Man")
	await _wait(GameSettings.dialogue.dialogue_intro_delay + 0.6)
	for i in 3:  # line1 -> line2 -> decision(listen) -> menu
		if DialogueManager.is_active():  # auto-advance may already have raced a step ahead
			DialogueManager._on_advance_click()
		await _wait(0.25)
	await _frames(10)
	await _shot("06_menu_text_scale_130")
	Settings.dialogue_text_scale = prior_scale
	DialogueManager.abort()
	await _frames(5)
	await _shot("07_scene_after_close")

	print("QA_DONE ", _dir)
	get_tree().quit(0)


## The QA conversation: two spoken lines, then a decision line carrying one of each row species.
func _qa_dialogue() -> DialogueResource:
	var line1 := DialogueLine.new()
	line1.text = "You're the one been asking after the package. Relay Seven's still hot — but nothing moves through this block on a Sunday without somebody getting paid."
	var line2 := DialogueLine.new()
	line2.text = "Speak up, then."
	var decision := DialogueLine.new()
	decision.text = "So what'll it be? The bells ring in an hour and I don't hold packages past the bells."
	var plain := DialogueChoice.new()
	plain.text = "Hand over the package."
	plain.target = DialogueLine.CONTINUE
	var stat_gate := DialogueChoice.new()  # passes: required_value at the baseline every fresh sheet meets
	stat_gate.text = "Sunday's a bad day to be greedy."
	stat_gate.required_stat = &"streetwise"
	stat_gate.required_value = 0
	stat_gate.target = DialogueLine.CONTINUE
	var failed_gate := DialogueChoice.new()  # fails its flag gate: stays selectable, routes to target_on_fail
	failed_gate.text = "Tell him Vex sent you."
	failed_gate.required_flag = &"qa_no_such_flag"
	failed_gate.required_flag_value = "set"
	failed_gate.target = DialogueLine.CONTINUE
	failed_gate.target_on_fail = DialogueLine.CONTINUE
	var long_reply := DialogueChoice.new()
	long_reply.text = "Ask him why a relay that has supposedly been cold for two winters still needs somebody paid on a Sunday."
	long_reply.target = DialogueLine.CONTINUE
	var choices: Array[DialogueChoice] = [plain, stat_gate, failed_gate, long_reply]
	decision.choices = choices
	var res := DialogueResource.new()
	var lines: Array[DialogueLine] = [line1, line2, decision]
	res.lines = lines
	return res


## Hide QA-noise painted over the frame — the boot sky title and the debug event ticker — WITHOUT
## touching any gameplay CanvasLayer (the dialogue lives on one; muzzle_smoke's blanket
## _strip_overlays would blind these shots).
func _hide_qa_noise() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "SkyTitle" and n is Node3D:
			(n as Node3D).visible = false
		elif n is CanvasItem and n.get_script() != null and str((n.get_script() as Script).resource_path).contains("debug_event_ticker"):
			(n as CanvasItem).visible = false
		stack.append_array(n.get_children())


func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		left -= get_process_delta_time()
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
