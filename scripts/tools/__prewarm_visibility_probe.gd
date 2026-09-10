extends Node
## Prewarm-visibility probe (the `__perf_probe` idiom): boots the REAL game and asks, EVERY frame, one question —
## was any EffectPrewarmer warm instance drawn with NOTHING covering it? It reports the post-process `death_fade`
## (1 = fully black, 0 = clear) beside the prewarm's own cover, so a failure says WHICH cover was missing.
##
## Run WINDOWED from the project root (never --headless — headless skips the warm entirely and compiles nothing):
##   godot --path <abs project> res://scripts/tools/__prewarm_visibility_probe.tscn
## ~6 s, quits itself; read the `[load]` / `[sample]` / `[verdict]` lines. `exposed=YES` on any row is the bug.
##
## WHAT IT FOUND (2026-09-03). effect_prewarmer.gd claimed "every hold is inside the fade-from-black". It is not:
## the holds are counted in FRAMES, the Player's spawn fade is a Tween with set_ignore_time_scale(true) and so runs
## on the WALL CLOCK, and the frame that loads game.tscn hands that tween a multi-second delta. Measured: the fade
## stepped 1.0 -> 0.998 -> 0.0 and FINISHED on the load frame — all 2.5 s of spawn_fade_in_time in one step, before
## the first warm instance was even instanced — after which the warm grid (22 instances, 2 m in front of the
## camera) drew at 100% screen brightness for 780-870 ms in plain sight. The fix was the pass raising its own
## cover; this probe is the acceptance instrument for it. ⭐It also documents a SECOND, independent bug it did not
## fix: with the fade consumed by the load frame, the load path HARD-CUTS into the world instead of emerging from
## black. Re-run this after any repair to that fade.
##
## Sibling instrument: scripts/tools/__first_kill_hitch_probe.gd measures whether the warm still WORKS (pipeline
## compile deltas). This one measures whether it is SEEN. A change to the pass wants both.

## Frames sampled after the swap — long enough to cover the whole pass (~15 frames) and the settle after it.
const SAMPLE_FRAMES: int = 400


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "PrewarmVisProbeDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(800, 480))
	await _frames(5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	var t_swap := Time.get_ticks_msec()
	await get_tree().process_frame  # the swap itself (the whole game.tscn load lands on this one frame)
	var t0 := Time.get_ticks_msec()  # t=0 is the first frame of the LIVE game, not the load stall
	# The load STALL, and the frame delta the engine hands the very next _process — which is what the spawn
	# fade-in tween steps by on its first step.
	print("[load] game.tscn swap frame took %d ms; next process delta reported = %.3f s (spawn_fade_in_time=%.2f s)" % [
			t0 - t_swap, get_process_delta_time(), GameSettings.player_feedback.spawn_fade_in_time])

	var rows: Array[String] = []
	var first_visible_ms := -1
	var last_visible_ms := -1
	var fade_at_first := -1.0
	var fade_at_last := -1.0
	var worst_brightness := 0.0
	var worst_ms := -1
	var frame := 0
	while frame < SAMPLE_FRAMES:
		await get_tree().process_frame
		frame += 1
		var ms := Time.get_ticks_msec() - t0
		var fade := _death_fade()
		var vis := _warm_visible()
		var covered := _covered()
		if vis > 0 and not covered:
			if first_visible_ms < 0:
				first_visible_ms = ms
				fade_at_first = fade
			last_visible_ms = ms
			fade_at_last = fade
			var brightness := 1.0 - clampf(fade, 0.0, 1.0)  # the shader multiplies the frame by this
			if brightness > worst_brightness:
				worst_brightness = brightness
				worst_ms = ms
		if vis > 0 or frame <= 16:
			rows.append("[sample] f=%d ms=%d death_fade=%.3f cover=%s warm_nodes_visible=%d exposed=%s" % [
					frame, ms, fade, "UP" if covered else "-- ", vis, "YES" if (vis > 0 and not covered) else "no"])
	for r in rows:
		print(r)
	print("[verdict] warm instances EXPOSED (drawn with no cover) from ms=", first_visible_ms, " to ms=", last_visible_ms,
			" (", (last_visible_ms - first_visible_ms) if first_visible_ms >= 0 else 0, " ms on screen)")
	print("[verdict] death_fade at first visible frame=", fade_at_first, " at last=", fade_at_last)
	print("[verdict] WORST leak: the warm grid drew at %.1f%% screen brightness at ms=%d (0%% = invisible)" % [
			worst_brightness * 100.0, worst_ms])
	print("[verdict] spawn_fade_in_time=", GameSettings.player_feedback.spawn_fade_in_time)
	get_tree().quit(0)


## death_fade on the player's post-process rect (the spawn fade-up reuses it; 1 = black).
func _death_fade() -> float:
	var player := Groups.human_player(get_tree())
	if player == null:
		return -1.0
	var rect := player.get_node_or_null("UI/ColorRect") as ColorRect
	if rect == null:
		return -1.0
	var mat := rect.material as ShaderMaterial
	if mat == null:
		return -1.0
	var v: Variant = mat.get_shader_parameter("death_fade")
	if v == null:
		return -2.0  # never set on the material at all -> the spawn fade never ran
	return float(v)


## Is the prewarm's own black cover up this frame?
func _covered() -> bool:
	var root := get_tree().current_scene
	if root == null:
		return false
	var warmer := root.get_node_or_null("EffectPrewarmer")
	if warmer == null:
		return false
	var cover := warmer.get_node_or_null("WarmCover") as CanvasLayer
	return cover != null and cover.visible


## How many of the EffectPrewarmer's children are currently visible in the world (0 = nothing on screen).
func _warm_visible() -> int:
	var root := get_tree().current_scene
	if root == null:
		return 0
	var warmer := root.get_node_or_null("EffectPrewarmer")
	if warmer == null:
		return 0
	if warmer is Node3D and not (warmer as Node3D).visible:
		return 0
	var n := 0
	for c in warmer.get_children():
		if c is Node3D and (c as Node3D).visible and c.name != &"DecalAtlasKeeper":
			n += 1
	return n


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
