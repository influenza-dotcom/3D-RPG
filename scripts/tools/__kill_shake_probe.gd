extends Node
## Kill-shake runtime probe — boots the REAL game, kills a REAL NPC through the REAL damage path
## (Character.take_damage credited to the player) and MEASURES the camera afterwards.
##
## WHY: the kick added to Player.on_scored_kill can only be pinned as source TEXT in a unit test —
## Player cannot be built in-tree in a GUT run (see test_player_core.gd's construction note). This
## harness closes that gap end to end: seam -> autoload read -> ScreenShake.trauma -> actual camera
## rotation, plus the accessibility opt-out.
##
## Run windowed from the project root (the GPU need not draw, but the game must be live):
##   godot --path . res://scripts/tools/__kill_shake_probe.tscn
##
## Driver-copy pattern, copied from flashlight_qa_shots.gd: this scene is the boot scene, but the run
## switches current_scene to game.tscn (which frees it), so _ready re-attaches a COPY of this script on
## a bare Node parented to root, which survives the scene change and drives.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "KillShakeProbeDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(800, 480))
	await _frames(5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(150)

	var player: Node3D = Groups.human_player(get_tree())
	if player == null:
		print("PROBE_FAIL no Player"); get_tree().quit(1); return
	var ss = player.get("screen_shake")
	if ss == null:
		print("PROBE_FAIL player.screen_shake is null"); get_tree().quit(1); return

	print("PROBE_KNOB kill_shake_amount=", GameSettings.screen_shake.kill_shake_amount,
			" intensity_multiplier=", GameSettings.screen_shake.intensity_multiplier,
			" decay_rate=", GameSettings.screen_shake.decay_rate)

	# --- CASE 1: a REAL kill, far away, through the real damage path ------------------------------
	var npc := _nearest_npc(player)
	if npc == null:
		print("PROBE_FAIL no NPC in the level"); get_tree().quit(1); return

	# Teleport the victim FAR past death_shake_range so on_nearby_death cannot account for any shake we
	# see. This is the case that had no camera answer at all before: a kill you score at distance.
	var far := player.global_position + Vector3(0, 0, 60)
	npc.global_position = far
	await _frames(4)
	var dist: float = player.global_position.distance_to(npc.global_position)

	ss.trauma = 0.0
	await _frames(2)
	print("PROBE_REST trauma=", ss.trauma, " rot=", ss.rotation)

	# The real chain: take_damage -> _resolve_killer -> killer.on_scored_kill() -> screen_shake.shake()
	npc.take_damage(99999.0, false, player)
	print("PROBE_KILL dist=", dist, " death_shake_range=", GameSettings.screen_shake.death_shake_range,
			" trauma_after=", ss.trauma)

	var peak := 0.0
	for i in 30:
		await get_tree().process_frame
		peak = maxf(peak, absf(ss.rotation.x) + absf(ss.rotation.y))
	print("PROBE_CAMERA peak_abs_rotation=", peak, " trauma_now=", ss.trauma)

	# --- CASE 2: the accessibility opt-out (Options -> Accessibility -> Screen Shake at 0) ---------
	# Drive intensity_multiplier DIRECTLY rather than through Settings.set_screen_shake_scale(): that setter
	# calls save_settings(), which would write the probe's throwaway 0 into the player's REAL user://settings.cfg
	# and silently turn their screen shake off for good. This is the exact value the slider ends up applying
	# (Settings.apply_accessibility does `intensity_multiplier = _base_shake_intensity * screen_shake_scale`),
	# so the assertion is the same one — without the side effect. Restored below.
	var base: float = GameSettings.screen_shake.intensity_multiplier
	GameSettings.screen_shake.intensity_multiplier = 0.0
	await _frames(2)
	ss.trauma = 0.0
	var npc2 := _nearest_npc(player)
	if npc2 != null:
		npc2.global_position = far
		await _frames(2)
		npc2.take_damage(99999.0, false, player)
	else:
		ss.shake(GameSettings.screen_shake.kill_shake_amount)
	var peak_off := 0.0
	for i in 30:
		await get_tree().process_frame
		peak_off = maxf(peak_off, absf(ss.rotation.x) + absf(ss.rotation.y))
	print("PROBE_ACCESSIBILITY slider0 intensity=", GameSettings.screen_shake.intensity_multiplier,
			" peak_abs_rotation=", peak_off, " (was ", base, ")")
	GameSettings.screen_shake.intensity_multiplier = base  # leave the live tuning as we found it

	print("PROBE_DONE")
	get_tree().quit(0)


func _nearest_npc(player: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is NPC and (n as Node3D).is_inside_tree() and not n.get("_dead"):
			var d: float = (n as Node3D).global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
		stack.append_array(n.get_children())
	return best


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
