extends Node
## THROWAWAY first-shot / first-hit / first-kill HITCH probe (the __perf_probe idiom — disposable, `__` prefix).
## Boots the REAL game.tscn in a small window, drives the in-game DebugConsole through run_line(), and logs
## WALL-CLOCK frame spikes per phase plus every shader-cache file written since launch. Run:
##   godot --path "<abs project>" res://scripts/tools/__first_kill_hitch_probe.tscn -- --run=<tag>
## Output: user://first_kill_hitch_<tag>.json + `[phase]` / `[phase-cmd]` / `[hitch]` lines in user://logs/godot.log.
##
## Why wall clock: every hit calls FreezeFrame (Engine.time_scale dips), so `delta` would read a hitstop as a
## tiny frame; Time.get_ticks_usec between _process calls is immune. Performance.TIME_PROCESS is a per-second
## MAXIMUM, logged only as a gauge. Phases ending in `_control` repeat the same beat warm in the same process:
## first_* minus *_control = the one-time cost we are hunting.
##
## Safety: `sandbox on` FIRST — a credited kill queues an autosave (player.gd add_xp -> _queue_autosave, one
## end-of-frame write) and that write must land in user://sandbox/, not the dev's gamestate.cfg. `god on` keeps the raider's SMG from ending the run
## (the hit flash + hurt feedback still fire on a soaked hit). Never calls Settings.set_* (those persist).

const GAME := "res://scenes/game.tscn"
const SETTLE_SEC := 10.0      # > the SkyTitle intro (~6 s) + nav-link auto_project settle
const SPIKE_FLOOR_MS := 25.0  # absolute floor for a logged spike...
const SPIKE_MULT := 3.0       # ...or 3x the rolling median of the last 120 frames
const CACHE_DIR := "user://shader_cache"

var _run_tag := "run"
var _phase := "boot"
var _last_usec := 0
var _drawn := 0
var _dt: PackedFloat32Array = PackedFloat32Array()
var _phase_of: PackedStringArray = PackedStringArray()
var _events: PackedStringArray = PackedStringArray()
var _pipe_prev: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _added: PackedStringArray = PackedStringArray()  # nodes that entered the tree since the last _process
var _root_rid: RID
var _run_start_unix := 0.0

const PIPE_MONITORS := [
	Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
	Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
	Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
]
const PIPE_NAMES := ["canvas", "mesh", "surface", "draw", "spec"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		# Driver-copy pattern (npc_hold_qa_shots.gd): the boot scene re-attaches a bare Node with this script
		# directly under root so it survives change_scene_to_file.
		var d := Node.new()
		d.name = "FirstKillHitchDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--run="):
			_run_tag = String(a).trim_prefix("--run=")
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(960, 540))
	DisplayServer.window_set_position(Vector2i(40, 40))
	_root_rid = get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_root_rid, true)
	RenderingServer.frame_post_draw.connect(func() -> void: _drawn += 1)
	# Name what entered the tree on a compile frame: a pipeline delta with a fresh node list beside it says
	# WHICH spawn is still paying first-use (the list is cleared every _process, so it is the last frame's births).
	get_tree().node_added.connect(func(n: Node) -> void:
		if _added.size() < 12:
			_added.append("%s:%s" % [n.get_class(), n.name]))
	_run_start_unix = Time.get_unix_time_from_system()
	_last_usec = Time.get_ticks_usec()
	_run()


func _process(_delta: float) -> void:
	Engine.max_fps = 0  # Settings re-applies the saved cap each apply_video
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	_dt.append(ms)
	_phase_of.append(_phase)
	var pipe_delta := _pipeline_deltas()
	var med := _median_of_last(120)
	if ms > maxf(SPIKE_FLOOR_MS, SPIKE_MULT * med) or pipe_delta != "":
		var line := "[hitch] run=%s phase=%s frame=%d drawn=%d unix=%.3f dt_ms=%.1f median_ms=%.1f cpu_ms=%.2f gpu_ms=%.2f proc_max_ms=%.1f phys_max_ms=%.1f nodes=%d pipelines=%s born=%s" % [
			_run_tag, _phase, Engine.get_process_frames(), _drawn, Time.get_unix_time_from_system(), ms, med,
			RenderingServer.viewport_get_measured_render_time_cpu(_root_rid),
			RenderingServer.viewport_get_measured_render_time_gpu(_root_rid),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			pipe_delta if pipe_delta != "" else "-",
			",".join(_added) if _added.size() > 0 else "-"]
		print(line)
		_events.append(line)
	_added.clear()


## Per-frame deltas of the 4.4+ pipeline-compilation monitors as "canvas+N,draw+M" (empty when none moved).
## DRAW / CANVAS increments are synchronous compiles = the stutter; SPEC is background (never a stall).
func _pipeline_deltas() -> String:
	var parts := PackedStringArray()
	for i in PIPE_MONITORS.size():
		var v := Performance.get_monitor(PIPE_MONITORS[i])
		var d := v - _pipe_prev[i]
		_pipe_prev[i] = v
		if d > 0.0:
			parts.append("%s+%d" % [PIPE_NAMES[i], int(d)])
	return ",".join(parts)


func _run() -> void:
	await _frames(5)
	get_tree().change_scene_to_file(GAME)
	await _seconds(SETTLE_SEC)
	get_tree().root.move_child(self, -1)  # process LAST each frame
	if _console() == null:
		print("[probe] FAIL no DebugConsole under current_scene (release build?)")
		get_tree().quit(2)
		return
	_pipeline_deltas()  # zero the counters after the boot burst
	_mark("baseline")
	await _seconds(3.0)
	_cmd("sandbox on")
	_cmd("god on")
	_mark("spawn")
	_cmd("spawn raider 1")
	await _seconds(2.0)
	_mark("first_npc_shot_hit")
	await _seconds(6.0)
	_mark("first_kill")
	_cmd("killall 8")
	await _seconds(4.0)
	_mark("hurt_direct")
	_cmd("god off")
	_cmd("hurt 5")
	await _seconds(2.0)
	_cmd("god on")
	_mark("spawn2_control")
	_cmd("spawn raider 1")
	await _seconds(2.0)
	_mark("shot_hit2_control")
	await _seconds(6.0)
	_mark("kill2_control")
	_cmd("killall 8")
	await _seconds(4.0)
	_mark("done")
	_dump()
	get_tree().quit(0)


## Re-resolved on EVERY call: reload/load/death rebuild the console.
func _console() -> Node:
	var cs := get_tree().current_scene
	return cs.get_node_or_null("DebugConsole") if cs != null else null


func _cmd(line: String) -> void:
	print("[phase-cmd] run=%s phase=%s frame=%d unix=%.3f line=%s" % [
		_run_tag, _phase, Engine.get_process_frames(), Time.get_unix_time_from_system(), line])
	var c := _console()
	if c != null:
		c.call("run_line", line)


## Phase boundaries are CHEAP on purpose: the shader-cache walk (DirAccess + get_modified_time over ~300
## files) costs hundreds of ms and would itself be the biggest spike in every phase — it runs once, at `done`.
func _mark(p: String) -> void:
	_phase = p
	print("[phase] run=%s phase=%s frame=%d drawn=%d unix=%.3f" % [
		_run_tag, p, Engine.get_process_frames(), _drawn, Time.get_unix_time_from_system()])
	if p == "done":
		var fresh := _cache_files_newer_than(_run_start_unix)
		print("[cache] run=%s cache_files=%d new_since_start=%d %s" % [_run_tag, _cache_count(), fresh.size(), ",".join(fresh)])


func _cache_count() -> int:
	return _walk(CACHE_DIR).size()


func _cache_files_newer_than(t: float) -> PackedStringArray:
	var out := PackedStringArray()
	for p in _walk(CACHE_DIR):
		if float(FileAccess.get_modified_time(p)) >= t:
			out.append(p.trim_prefix(CACHE_DIR + "/"))
	return out


## DirAccess recursion over ~300 files: a few ms, only at phase boundaries — never per frame.
func _walk(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		out.append(dir.path_join(f))
	for s in d.get_directories():
		out.append_array(_walk(dir.path_join(s)))
	return out


func _dump() -> void:
	var report := {
		"run": _run_tag, "phases": _phase_stats(), "hitches": _events, "dt_ms": _dt, "phase_of": _phase_of,
		"engine": {
			"gpu": RenderingServer.get_video_adapter_name(), "debug_build": OS.is_debug_build(),
			"viewport": str(get_viewport().get_visible_rect().size), "scale3d": get_viewport().scaling_3d_scale,
		},
	}
	var f := FileAccess.open("user://first_kill_hitch_%s.json" % _run_tag, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
		f = null
	print("[probe-json] ", JSON.stringify({"run": _run_tag, "phases": report["phases"], "hitches": _events.size()}))


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## ignore_time_scale = true: FreezeFrame must not stretch a phase window.
func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _median_of_last(n: int) -> float:
	var count := mini(n, _dt.size())
	if count == 0:
		return 16.7
	var tail: Array[float] = []
	for i in range(_dt.size() - count, _dt.size()):
		tail.append(_dt[i])
	tail.sort()
	return tail[count / 2]


func _phase_stats() -> Dictionary:
	var buckets: Dictionary = {}
	for i in _dt.size():
		var p: String = _phase_of[i]
		if not buckets.has(p):
			buckets[p] = []
		(buckets[p] as Array).append(_dt[i])
	var stats: Dictionary = {}
	for p in buckets:
		var arr: Array = buckets[p]
		arr.sort()
		var n := arr.size()
		var over := 0
		for v in arr:
			if float(v) > SPIKE_FLOOR_MS:
				over += 1
		stats[p] = {
			"frames": n, "p50": arr[n / 2], "p95": arr[mini(n - 1, int(n * 0.95))], "max": arr[n - 1],
			"over_25ms": over,
		}
	return stats
