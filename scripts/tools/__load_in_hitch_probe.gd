extends Node
## THROWAWAY load-in HITCH probe (the __perf_probe idiom — disposable, `__` prefix). Boots the REAL game.tscn the
## way StartMenu does (threaded load, then change_scene_to_packed) in a small window and records EVERY frame's
## WALL-CLOCK duration for the first WINDOW_SEC seconds after the swap, with the pipeline-compile deltas, the nodes
## born that frame, the physics steps the frame ran, how many NavLinks are still auto-projecting and whether the
## EffectPrewarmer's black cover is up. Run:
##   godot --path "<abs project>" res://scripts/tools/__load_in_hitch_probe.tscn -- --run=<tag> [--no-navlinks]
##        [--no-prewarm] [--no-skytitle] [--no-ps1] [--no-npcs]
## Output: user://load_in_hitch_<tag>.json + `[loadin]` lines on stdout.

const GAME := "res://scenes/game.tscn"
const WINDOW_SEC := 12.0
const PRINT_FLOOR_MS := 20.0

const PIPE_MONITORS := [
	Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
	Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
	Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
]
const PIPE_NAMES := ["canvas", "mesh", "surface", "draw", "spec"]

var _run_tag := "run"
var _flags: PackedStringArray = PackedStringArray()
var _last_usec := 0
var _drawn := 0
var _last_phys := 0
var _pipe_prev: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _added: PackedStringArray = PackedStringArray()
var _added_count := 0
var _root_rid: RID
var _recording := false
var _t0_usec := 0
var _frames: Array = []
var _links: Array = []
var _links_collected := false
var _loading := false
var _swapped := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "LoadInHitchDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--run="):
			_run_tag = s.trim_prefix("--run=")
		elif s.begins_with("--no-"):
			_flags.append(s.trim_prefix("--no-"))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(960, 540))
	DisplayServer.window_set_position(Vector2i(40, 40))
	_root_rid = get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_root_rid, true)
	RenderingServer.frame_post_draw.connect(func() -> void: _drawn += 1)
	get_tree().node_added.connect(_on_node_added)
	if "prewarm" in _flags:
		EffectPrewarmer._warmed = true  # process-lifetime latch: warm() returns before raising the cover
	_last_usec = Time.get_ticks_usec()
	_last_phys = Engine.get_physics_frames()
	_run()


func _on_node_added(n: Node) -> void:
	_added_count += 1
	if _added.size() < 16:
		_added.append("%s:%s" % [n.get_class(), n.name])
	if "navlinks" in _flags and n is NavigationLink3D and "auto_project" in n:
		n.set("auto_project", false)
	if "skytitle" in _flags and n.name == &"SkyTitle":
		n.set("test_show_immediately", false)
	if "ps1" in _flags and n.name == &"Ps1Warp" and "enabled" in n:
		n.set("enabled", false)
	if "npcs" in _flags and n is NPC:
		n.process_mode = Node.PROCESS_MODE_DISABLED


func _process(_delta: float) -> void:
	Engine.max_fps = 0
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	var phys := Engine.get_physics_frames()
	var phys_steps := phys - _last_phys
	_last_phys = phys
	var pipe_delta := _pipeline_deltas()
	if _loading and not _swapped:
		if ResourceLoader.load_threaded_get_status(GAME) == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(GAME) as PackedScene
			_swapped = true
			_recording = true
			_t0_usec = now
			print("[loadin] run=%s swap frame=%d unix=%.3f" % [_run_tag, Engine.get_process_frames(), Time.get_unix_time_from_system()])
			get_tree().change_scene_to_packed(packed)
			_added.clear()
			_added_count = 0
			return
	if not _recording:
		_added.clear()
		_added_count = 0
		return
	var t := float(now - _t0_usec) / 1_000_000.0
	var cs := get_tree().current_scene
	var cover := false
	var active_links := 0
	if cs != null and cs.name != &"LoadInHitchProbe":
		cover = cs.get_node_or_null(^"EffectPrewarmer/WarmCover") != null
		if not _links_collected:
			var lvl := cs.get_node_or_null(^"Level")
			if lvl != null:
				var w0 := Time.get_ticks_usec()
				_collect_links(lvl)
				_links_collected = true
				print("[loadin] collected %d NavLinks in %.2f ms at t=%.3f" % [_links.size(), float(Time.get_ticks_usec() - w0) / 1000.0, t])
		for l in _links:
			if is_instance_valid(l) and l.is_physics_processing():
				active_links += 1
	var rec := {
		"t": t, "dt": ms, "frame": Engine.get_process_frames(), "drawn": _drawn, "phys": phys_steps,
		"pipes": pipe_delta, "born": _added_count, "born_names": ",".join(_added), "cover": cover,
		"links": active_links, "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"cpu": RenderingServer.viewport_get_measured_render_time_cpu(_root_rid),
		"gpu": RenderingServer.viewport_get_measured_render_time_gpu(_root_rid),
		"proc_max": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"phys_max": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"nav_max": Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
	}
	_frames.append(rec)
	if ms > PRINT_FLOOR_MS or pipe_delta != "":
		print("[loadin] t=%.3f dt=%.1f phys=%d cover=%s links=%d pipes=%s cpu=%.1f gpu=%.1f nav_max=%.1f born=%d:%s" % [
			t, ms, phys_steps, str(cover), active_links, pipe_delta if pipe_delta != "" else "-",
			rec["cpu"], rec["gpu"], rec["nav_max"], _added_count, ",".join(_added)])
	_added.clear()
	_added_count = 0
	if t >= WINDOW_SEC:
		_recording = false
		_dump()
		get_tree().quit(0)


var _authored: Array = []  # [start, end] per link at collection time — to measure how far projection moved them


func _collect_links(n: Node) -> void:
	if n is NavigationLink3D:
		_links.append(n)
		_authored.append([n.start_position, n.end_position])
	for c in n.get_children():
		_collect_links(c)


## How far auto_project actually MOVED each endpoint (authored vs now): if generated links already sit on the mesh
## the answer is ~0 and every endpoint write (each one dirties the nav map) was avoidable.
func _drift_report() -> void:
	var moved := 0
	var maxd := 0.0
	var sum := 0.0
	var buckets := {"<1mm": 0, "<1cm": 0, "<10cm": 0, "<1m": 0, ">=1m": 0}
	for i in _links.size():
		var l: Node = _links[i]
		if not is_instance_valid(l):
			continue
		for j in 2:
			var a: Vector3 = _authored[i][j]
			var b: Vector3 = l.start_position if j == 0 else l.end_position
			var d := a.distance_to(b)
			sum += d
			maxd = maxf(maxd, d)
			if d > 0.001:
				moved += 1
			var k := "<1mm" if d < 0.001 else ("<1cm" if d < 0.01 else ("<10cm" if d < 0.1 else ("<1m" if d < 1.0 else ">=1m")))
			buckets[k] += 1
	print("[loadin] drift: endpoints=%d moved(>1mm)=%d max=%.4f mean=%.5f buckets=%s" % [_links.size() * 2, moved, maxd, sum / maxf(1.0, _links.size() * 2), str(buckets)])


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
	for _i in 10:
		await get_tree().process_frame
	print("[loadin] run=%s flags=%s gpu=%s debug=%s" % [_run_tag, ",".join(_flags), RenderingServer.get_video_adapter_name(), str(OS.is_debug_build())])
	_pipeline_deltas()
	ResourceLoader.load_threaded_request(GAME)
	_loading = true


func _dump() -> void:
	var buckets: Dictionary = {}
	for r in _frames:
		var b := int(floor(float(r["t"]) * 2.0))
		if not buckets.has(b):
			buckets[b] = []
		(buckets[b] as Array).append(float(r["dt"]))
	var keys := buckets.keys()
	keys.sort()
	_drift_report()
	print("[loadin] ---- per 0.5 s bucket: frames / p50 / max / sum of frames > 20 ms")
	for k in keys:
		var arr: Array = buckets[k]
		arr.sort()
		var over := 0.0
		for v in arr:
			if float(v) > PRINT_FLOOR_MS:
				over += float(v)
		print("[loadin] bucket %4.1f-%4.1f s: %4d frames  p50=%6.2f  max=%7.1f  over20=%7.1f ms" % [k * 0.5, (k + 1) * 0.5, arr.size(), arr[arr.size() / 2], arr[arr.size() - 1], over])
	var f := FileAccess.open("user://load_in_hitch_%s.json" % _run_tag, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"run": _run_tag, "flags": _flags, "frames": _frames}, "\t"))
		f = null
	print("[loadin] done run=%s frames=%d" % [_run_tag, _frames.size()])
