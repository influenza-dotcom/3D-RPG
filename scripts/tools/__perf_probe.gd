extends Node

## THROWAWAY perf probe (the `__` prefix marks it disposable, like `__shirt_qa.gd`). It boots the REAL
## game.tscn as `current_scene` — autoloads and all — parks a measurement node beside it, sweeps the player's
## yaw so every view direction in the level gets sampled, and dumps a frame-time breakdown per VIEWPORT.
##
##   godot --path "<abs project path>" res://scripts/tools/__perf_probe.tscn -- <variant>
##
## WINDOWED on purpose (the preview_fists_frame.gd idiom): render timings need a real renderer. The window is
## forced small, which does NOT change the measurement — `window/stretch/mode="viewport"` pins the internal
## viewport at 792x444 and `scaling_3d/scale=2.0` pins the 3D buffer at 1584x888 regardless of window size.
##
## The load-bearing numbers are RenderingServer.viewport_get_measured_render_time_{cpu,gpu} per viewport: that
## is the same instrumentation the editor's own frame profiler uses, and it is the ONLY way to answer
## "CPU-bound or GPU-bound?" without guessing. Everything else (Performance monitors) is context.
##
## `Engine.max_fps` is forced to 0 and vsync off, so the report measures HEADROOM, not the 144 cap.

const GAME := "res://scenes/game.tscn"
## The player's real settings file. Snapshotted at boot and restored at exit — see _snapshot_settings.
const SETTINGS_PATH := "user://settings.cfg"

## Must outlast EVERY boot-time transient or the report prices the level load instead of gameplay. The two
## that bit here: game.tscn's SkyTitle ("CYBERSUNDAY", 2.5 s hold + 3.5 s fade = ~6 s of a screen-filling
## alpha quad), and nav_link.gd's auto_project settle (project_settle_frames = 120 physics frames of navmesh
## queries x 113 links). Measured symptom of getting this wrong: adding 10 NPCs made the game look TWICE AS
## FAST, because spawning them burned enough wall-clock to push the sample past the transients.
const BOOT_SETTLE_SEC := 8.0
const WARMUP_SEC := 2.5        ## shader compiles / first-draw of each material land here, not in the sample
const SAMPLE_SEC := 6.0
const YAW_TURNS := 1.5         ## full turns swept across the sample window (samples every view direction)

var _variant := "baseline"
var _game: Node = null
var _player: Node3D = null
var _t := 0.0
var _phase := 0  # 0 = settle, 1 = warmup, 2 = sample, 3 = done
var _yaw0 := 0.0
var _origin := Vector3.ZERO
## Tour waypoints (the level's own lights, which are spread across the playable space) + which one each
## sampled frame was taken at, so the report can name the worst location instead of averaging it away.
var _waypoints: Array[Vector3] = []
var _wp_index := -1
var _wp_of_frame: Array[int] = []
var _drawn := 0
var _settle_sec := BOOT_SETTLE_SEC
## Verbatim contents of user://settings.cfg as it was at boot — see _snapshot_settings / _restore_settings.
var _settings_backup: String = ""

## rid -> {name, cpu[], gpu[]}
var _viewports := {}
## The AUTHORITATIVE frame-time series: raw per-frame `delta`. Performance.TIME_PROCESS /
## TIME_PHYSICS_PROCESS are NOT averages — Godot's Main::iteration publishes the per-second MAXIMUM
## (process_max / physics_process_max, reset each second), which is why they read HIGHER than the median
## frame. Keep them, but read them as "worst step in the last second" = a hitch gauge, never as a mean.
var _dt: Array[float] = []
var _fps: Array[float] = []
var _proc_max: Array[float] = []
var _phys_max: Array[float] = []
var _nav_max: Array[float] = []
var _draws: Array[float] = []
var _objs: Array[float] = []
var _prims: Array[float] = []
var _frames := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_variant = String(args[0])
	# "settle<N>" overrides the pre-sample wait. The control experiment for any "adding work made it FASTER"
	# result: if plain waiting longer reproduces the speed-up, the difference was a boot transient, not the work.
	for part in _variant.split("+"):
		if part.begins_with("settle") and part.substr(6).is_valid_int():
			_settle_sec = float(part.substr(6).to_int())
	process_mode = Node.PROCESS_MODE_ALWAYS
	# `asplayed` leaves the user's OWN saved video settings alone (exclusive fullscreen, their max_fps, their
	# vsync) so the number it prints is the number they actually see. Every other variant forces a small
	# uncapped window, which measures HEADROOM instead of the cap.
	if not _variant.contains("asplayed"):
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(960, 540))
		DisplayServer.window_set_position(Vector2i(40, 40))
	_snapshot_settings()
	_boot.call_deferred()


## ⭐ HARD GUARD: copy the player's real user://settings.cfg aside at boot and put it back on the way out.
##
## This exists because a probe variant once called `Settings.set_ink_outline_intensity(0.0)` to A/B the ink
## pass — and every `Settings.set_*` ends in `save_settings()`. The measurement finished, the process exited,
## and the player's ink outline stayed switched OFF in their game with no trace of why. Belt and braces on top
## of the "set the field, never the setter" rule in _kill_ink: even a future variant that forgets the rule
## cannot now leak, because _restore_settings runs before quit either way.
func _snapshot_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f != null:
		_settings_backup = f.get_as_text()
		f = null


## Put the snapshot back if anything changed it. No-op when the file is untouched, so a clean run never
## rewrites the player's config either.
func _restore_settings() -> void:
	if _settings_backup == "":
		return
	var cur := ""
	if FileAccess.file_exists(SETTINGS_PATH):
		var r := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if r != null:
			cur = r.get_as_text()
			r = null
	if cur == _settings_backup:
		return
	var w := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if w != null:
		w.store_string(_settings_backup)
		w = null
		print("[probe] RESTORED user://settings.cfg — a variant had modified it")


func _boot() -> void:
	var packed := load(GAME) as PackedScene
	_game = packed.instantiate()
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game  # so anything reading current_scene sees the game, not this probe
	print("[probe] variant=", _variant, " booted ", GAME)


func _process(delta: float) -> void:
	# EVERY frame, not just in _ready: the Settings autoload re-applies the user's saved `max_fps` (355) on
	# various events, and a capped run measures the cap instead of the headroom. Same for vsync.
	if not _variant.contains("asplayed"):
		Engine.max_fps = 0
	if _game == null:
		return
	_t += delta
	match _phase:
		0:
			if _t >= _settle_sec:
				_apply_variant()
				_arm_measurement()
				_t = 0.0
				_phase = 1
		1:
			if _t >= WARMUP_SEC:
				_t = 0.0
				_phase = 2
		2:
			# `shot` mode: this probe already boots the REAL game.tscn with the player's real settings, so it
			# is also the fastest honest answer to "is the ink outline actually drawing?" — save the frame and
			# LOOK, instead of reasoning about it.
			if _variant.contains("shot"):
				var img := get_viewport().get_texture().get_image()
				var shot_path := "user://__ink_shot_%s.png" % _variant.replace("+", "_")
				img.save_png(shot_path)
				# ⭐ AND a NEAREST-magnified crop. Judging a 1-px ink line on a 792x444 frame BY EYE is how a
				# doubled outline got called "verified" once already — at this buffer size the artifact is
				# smaller than the reviewer's ability to see it. Crop tight and blow it up with NEAREST (the
				# preview_fists_frame.gd rule: never judge pixel-scale line work at native size).
				var c := Vector2i(img.get_size()) / 2
				var half := Vector2i(160, 90)
				var crop := img.get_region(Rect2i(c - half, half * 2))
				crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
				crop.save_png("user://__ink_zoom_%s.png" % _variant.replace("+", "_"))
				print("[probe] wrote ", shot_path, " ", img.get_size(), " + 4x zoom crop")
				_report_mask_bits()
				_restore_settings()
				get_tree().quit(0)
				return
			_sweep_yaw(_t / SAMPLE_SEC)
			_collect(delta)
			if _t >= SAMPLE_SEC:
				_phase = 3
				_report()
				_restore_settings()  # before quit, always — the probe must leave no trace in user://
				get_tree().quit(0)


# --------------------------------------------------------------------------------------------------
# Variants — each one removes ONE suspected cost so the delta against `baseline` is that cost's price.
# --------------------------------------------------------------------------------------------------

func _apply_variant() -> void:
	_player = get_tree().get_first_node_in_group(Groups.PLAYER) as Node3D
	if _player != null:
		_yaw0 = _player.rotation.y
	var applied := PackedStringArray()
	var v := _variant
	if v == "min":
		v = "no_ink+scale1+no_fog+no_post+no_shadow"
	for part in v.split("+"):
		match part:
			"baseline":
				pass
			"no_ink":
				applied.append(_kill_ink())
			"scale1":
				get_viewport().scaling_3d_scale = 1.0
				applied.append("scaling_3d_scale=1.0")
			"scale05":
				get_viewport().scaling_3d_scale = 0.5
				applied.append("scaling_3d_scale=0.5")
			"no_fog":
				applied.append(_kill_fog())
			"no_post":
				applied.append(_kill_post())
			"no_shadow":
				applied.append(_kill_shadows())
			"no_hud":
				applied.append(_kill_canvas_layers())
			"no_ai":
				applied.append(_kill_ai())
			# --- CPU bisection. The GPU variants above answer "how expensive is this effect"; these answer
			# "where does the main thread actually go", which is the question that matters once the GPU
			# turns out to have headroom.
			"pause":
				# Everything PROCESS_MODE_PAUSABLE stops; what is left is ALWAYS-mode nodes + engine floor.
				get_tree().paused = true
				applied.append("tree paused")
			"noscript":
				applied.append(_kill_all_script_processing())
			# --- AI cost bisection. Each of these is ALSO a candidate fix, not just a probe: whichever one
			# recovers the frame is the thing the LOD has to throttle.
			"noavoid":
				applied.append(_npc_nav(func(nav: NavigationAgent3D) -> void: nav.avoidance_enabled = false,
						"avoidance_enabled=false"))
			"sight15":
				applied.append(_npc_set(&"sight_range", 15.0))
			"nowander":
				applied.append(_npc_set(&"wanders", false))
			# The decisive split. An NPC is ~91 nodes, and a dozen of its COMPONENTS carry their own
			# _process/_physics_process (BodyModelSwap, NpcHeadLookMount, LocomotionFx, NoiseSource,
			# Locomotor, ...). `no_ai` disabled the whole subtree at once, so it could never say whether the
			# cost is the BRAIN (npc.gd's own tick) or the ENTOURAGE. These two answer exactly that.
			"nocull":
				# Turn OFF InkOutline's actor-occlusion test, so the same frame can be shot with and without
				# it and diffed. A pixel diff is the only honest verdict here: the artifact is a person-shaped
				# GAP in ink lines, which is exactly the kind of thing that is invisible at 792x444 by eye.
				# (scripts/tools/__ink_occlusion_shots.gd does the same A/B on a purpose-built scene.)
				var ink := _find_ink_outline()
				if ink == null:
					applied.append("nocull: InkOutline NOT FOUND")
				else:
					ink.set(&"occlusion_aware_mask", false)
					applied.append("occlusion_aware_mask=false")
			"nolod":
				# The A/B for the AI level-of-detail: flip every NPC's AiLod off so it thinks every tick
				# again (the pre-LOD behaviour). Found by method, not class_name, so the probe never has to
				# name a class the editor may not have re-registered yet.
				var lods := 0
				for node in get_tree().get_nodes_in_group(Groups.NPC):
					for child in (node as Node).get_children():
						if child.has_method(&"think_delta"):
							child.set(&"enabled", false)
							lods += 1
				applied.append("AiLod disabled on %d npc(s)" % lods)
			"off_self":
				applied.append(_npc_self_processing(false))
			"off_children":
				applied.append(_npc_children_processing(false))
			"interp":
				# Global physics interpolation. Smooths 60 Hz physics motion across render frames — but it
				# also interpolates transforms written OUTSIDE _physics_process, which is where this project's
				# mouse look lives (mouse_input.gd -> player.rotate_y). Measure, don't assume.
				get_tree().physics_interpolation = true
				applied.append("SceneTree.physics_interpolation=true")
			"tour":
				applied.append(_build_tour())
			_:
				# "npc<N>" — spawn N REAL wandering NPCs around the player (the soak_harness.gd recipe:
				# stamp the exports BEFORE add_child so _ready reads them; `wanders` defaults false and a
				# standing NPC exercises nothing). This is the load the standing-at-spawn probe never sees.
				if part.begins_with("npcfar") and part.substr(6).is_valid_int():
					# The REALISTIC crowd: a populated map, most of the cast far away and unaware. `npc<N>`
					# rings them 12 m from the player, which is the worst case for AI LOD by construction
					# (everyone close and engaged) — it measures the cliff, not the fix.
					applied.append(_spawn_npcs(part.substr(6).to_int(), 30.0, 90.0))
				elif part.begins_with("npc") and part.substr(3).is_valid_int():
					applied.append(_spawn_npcs(part.substr(3).to_int()))
				elif part.begins_with("maxsteps") and part.substr(8).is_valid_int():
					# Engine default is 8. Under load that is a DEATH SPIRAL amplifier: a frame slow enough to
					# fall behind the physics clock runs up to 8 catch-up steps, each re-running every NPC's
					# _physics_process, which makes the frame slower still. Lowering it lets physics time
					# dilate (slow-mo) instead of tanking the frame rate.
					Engine.max_physics_steps_per_frame = part.substr(8).to_int()
					applied.append("max_physics_steps_per_frame=%d" % Engine.max_physics_steps_per_frame)
				elif part.begins_with("phys") and part.substr(4).is_valid_int():
					# "phys<N>" — retune the physics tick rate. Raising it is the interpolation-free way to
					# cut 60 Hz motion stepping; the question it answers is what that costs on the CPU.
					Engine.physics_ticks_per_second = part.substr(4).to_int()
					applied.append("physics_ticks_per_second=%d" % Engine.physics_ticks_per_second)
				else:
					applied.append("UNKNOWN:" + part)
	print("[probe] applied: ", ", ".join(applied))


func _kill_ink() -> String:
	# Options -> Video -> Ink Outline -> 0% hides the quad AND parks the mask SubViewport at UPDATE_DISABLED,
	# so writing that one field isolates the whole ink pass (edge detect + second scene render).
	#
	# ⭐⭐ SET THE FIELD, NEVER CALL THE SETTER. Every `Settings.set_*` PERSISTS — `set_ink_outline_intensity`
	# ends in `save_settings()` (managers/Settings.gd). Calling it from this throwaway probe wrote
	# `ink_outline_intensity = 0.0` into the player's real user://settings.cfg and left the world's ink
	# outline switched OFF in their game, long after the probe exited. A measurement tool must not have side
	# effects that outlive the process. The same rule binds every future variant: touch the live field, never
	# the persisting setter.
	var s: Object = get_node_or_null(^"/root/Settings")
	if s == null:
		return "ink: Settings autoload NOT FOUND"
	s.set(&"ink_outline_intensity", 0.0)
	return "ink_outline_intensity=0 (in-memory only)"


func _kill_fog() -> String:
	var n := 0
	for node in _all_nodes(get_tree().root):
		if node is WorldEnvironment:
			var env: Environment = (node as WorldEnvironment).environment
			if env != null:
				env.volumetric_fog_enabled = false
				env.fog_enabled = false
				n += 1
	return "fog off on %d WorldEnvironment(s)" % n


func _kill_post() -> String:
	# Any CanvasItem wearing a ShaderMaterial whose shader lives in resources/shaders/ and is full-screen-ish.
	var n := 0
	for node in _all_nodes(get_tree().root):
		if node is ColorRect or node is TextureRect:
			var ci := node as CanvasItem
			var m := ci.material as ShaderMaterial
			if m != null and m.shader != null and m.shader.resource_path.contains("post_process"):
				ci.visible = false
				n += 1
	return "post_process quads hidden: %d" % n


func _kill_shadows() -> String:
	var n := 0
	for node in _all_nodes(get_tree().root):
		if node is Light3D and (node as Light3D).shadow_enabled:
			(node as Light3D).shadow_enabled = false
			n += 1
	return "shadows off on %d light(s)" % n


func _kill_canvas_layers() -> String:
	var n := 0
	for node in _all_nodes(get_tree().root):
		if node is CanvasLayer and (node as CanvasLayer).visible:
			(node as CanvasLayer).visible = false
			n += 1
	return "CanvasLayers hidden: %d" % n


## Spawn `n` real wandering NPCs scattered around the player, as siblings of the level — the same recipe
## soak_harness.gd uses. Deliberately runs each NPC's full `_ready` (nav agent, weapon, perception): the whole
## point is to price the AI, and a hollow NPC would price nothing.
func _spawn_npcs(n: int, min_radius: float = -1.0, max_radius: float = -1.0) -> String:
	if _player == null:
		return "npc%d: NO PLAYER" % n
	var scene := load("res://scenes/characters/NPC.tscn") as PackedScene
	if scene == null:
		return "npc%d: NPC.tscn MISSING" % n
	var parent := _game
	var anchor := _player.global_position
	for i in n:
		var npc := scene.instantiate()
		npc.set(&"display_name", "Perf%d" % i)
		npc.set(&"wanders", true)
		npc.set(&"wander_radius", 12.0)
		parent.add_child(npc)
		if npc is Node3D:
			# Ring them around the player so they are ON SCREEN for part of the yaw sweep (rendering +
			# the outline tint pass + AI all priced), not hiding behind the spawn wall. The radius grows with the
			# count to hold ~2 m spacing: a fixed radius stacks 40 NPCs inside each other, and the resulting
			# contact storm would price a bug, not the AI.
			var a := TAU * float(i) / maxf(float(n), 1.0)
			var radius := maxf(6.0, float(n) * 2.0 / TAU)
			if min_radius > 0.0:
				# Spread across an annulus so the cast lands in every LOD band, not all in one. The golden-ratio
				# step keeps successive NPCs from landing at the same radius as their angular neighbours.
				radius = min_radius + (max_radius - min_radius) * fmod(float(i) * 0.6180339887, 1.0)
			(npc as Node3D).global_position = anchor + Vector3(cos(a) * radius, 1.0, sin(a) * radius)
	return "spawned %d wandering NPC(s)" % n


## Stamp a property on every NPC in the tree (the authored cast AND anything `npc<N>` spawned).
func _npc_set(prop: StringName, value: Variant) -> String:
	var n := 0
	for node in get_tree().get_nodes_in_group(Groups.NPC):
		node.set(prop, value)
		n += 1
	return "%s=%s on %d npc(s)" % [prop, str(value), n]


## Silence the NPC's OWN tick (npc.gd _physics_process: perception, GOAP, retarget, and the
## super -> gravity/move_and_slide chain) while every component child keeps running.
func _npc_self_processing(on: bool) -> String:
	var n := 0
	for node in get_tree().get_nodes_in_group(Groups.NPC):
		(node as Node).set_physics_process(on)
		(node as Node).set_process(on)
		n += 1
	return "self tick %s on %d npc(s)" % ["on" if on else "OFF", n]


## Silence every DESCENDANT of each NPC, leaving npc.gd's own tick running. The complement of _npc_self_processing.
func _npc_children_processing(on: bool) -> String:
	var n := 0
	for node in get_tree().get_nodes_in_group(Groups.NPC):
		for child in _all_nodes(node as Node):
			if child == node:
				continue
			if child.is_processing() or child.is_physics_processing():
				child.set_process(on)
				child.set_physics_process(on)
				n += 1
	return "child ticks %s on %d node(s)" % ["on" if on else "OFF", n]


## Reach every NPC's NavigationAgent3D. npc.gd builds it in code (_build_nav) and the Locomotor is handed the
## SAME agent, so finding it by type is the only handle a probe has.
func _npc_nav(fn: Callable, label: String) -> String:
	var n := 0
	for node in get_tree().get_nodes_in_group(Groups.NPC):
		for child in (node as Node).get_children():
			if child is NavigationAgent3D:
				fn.call(child as NavigationAgent3D)
				n += 1
	return "%s on %d agent(s)" % [label, n]


## Waypoints for `tour`: every Light3D in the loaded level. They are hand-placed where the designer expects
## the player to be, so they double as a free, authored sampling route across the map.
func _build_tour() -> String:
	for node in _all_nodes(get_tree().root):
		if node is Light3D and node is not DirectionalLight3D:
			var l := node as Light3D
			if l.is_inside_tree() and l.visible:
				_waypoints.append(l.global_position)
	_waypoints.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	return "tour over %d waypoint(s)" % _waypoints.size()


## Silence every _process / _physics_process in the tree except this probe's own. What remains is the ENGINE
## floor: scene-tree walk, physics step, render submission, audio mix. baseline - noscript = the GDScript bill.
func _kill_all_script_processing() -> String:
	var n := 0
	for node in _all_nodes(get_tree().root):
		if node == self or node == get_tree().root:
			continue
		if node.is_processing() or node.is_physics_processing():
			node.set_process(false)
			node.set_physics_process(false)
			n += 1
	return "script processing silenced on %d node(s)" % n


func _kill_ai() -> String:
	var n := 0
	for node in get_tree().get_nodes_in_group(Groups.NPC):
		if node is Node:
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
			n += 1
	return "npcs disabled: %d" % n


# --------------------------------------------------------------------------------------------------
# Measurement
# --------------------------------------------------------------------------------------------------

## Count frames the renderer ACTUALLY drew. Godot's main loop can run `_process` without calling
## RenderingServer::draw() (occluded/unfocused window, low-processor mode), which produces sub-millisecond
## `delta`s that look like a spectacular framerate and are in fact the game not rendering at all. Without
## this counter every number in the report is uninterpretable.
func _on_frame_drawn() -> void:
	if _phase == 2:
		_drawn += 1


func _arm_measurement() -> void:
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_drawn):
		RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	for node in _all_nodes(get_tree().root):
		if node is Viewport:
			var vp := node as Viewport
			var rid := vp.get_viewport_rid()
			if _viewports.has(rid):
				continue
			RenderingServer.viewport_set_measure_render_time(rid, true)
			var label := vp.get_class() + ":" + String(vp.name)
			if vp is SubViewport:
				label += " " + str((vp as SubViewport).size)
			else:
				label += " " + str(vp.get_visible_rect().size)
			_viewports[rid] = {"name": label, "cpu": [] as Array[float], "gpu": [] as Array[float]}
	print("[probe] measuring ", _viewports.size(), " viewport(s): ",
			", ".join(_viewports.values().map(func(d: Dictionary) -> String: return d["name"])))


func _sweep_yaw(t01: float) -> void:
	if _player == null:
		return
	_player.rotation.y = _yaw0 + TAU * YAW_TURNS * clampf(t01, 0.0, 1.0)
	# TOUR mode: standing at spawn only ever measures ONE view of the map. Hop the player between waypoints
	# so the report covers the whole level and can name the WORST spot — which is where "kinda laggy" lives.
	if _waypoints.is_empty():
		return
	var idx := clampi(int(t01 * _waypoints.size()), 0, _waypoints.size() - 1)
	if idx != _wp_index:
		_wp_index = idx
		_player.global_position = _waypoints[idx] + Vector3(0.0, 1.0, 0.0)
	_wp_of_frame.append(_wp_index)


func _collect(delta: float) -> void:
	_frames += 1
	_dt.append(delta * 1000.0)
	_fps.append(Performance.get_monitor(Performance.TIME_FPS))
	_proc_max.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_phys_max.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_nav_max.append(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)
	_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	for rid: RID in _viewports:
		var d: Dictionary = _viewports[rid]
		(d["cpu"] as Array).append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		(d["gpu"] as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(rid))


func _report() -> void:
	var frame := _stats(_dt)
	# A "hitch" = a frame more than 2x the median. This is what "kinda laggy" usually means when the average
	# fps is fine: the eye reads variance, not the mean.
	var hitch_floor: float = frame["p50"] * 2.0
	var hitches := 0
	var worst := 0.0
	for ms in _dt:
		if ms > hitch_floor:
			hitches += 1
		worst = maxf(worst, ms)
	var out := {
		"variant": _variant,
		"frames": _frames,
		"frames_drawn": _drawn,
		"drawn_pct": 100.0 * _drawn / maxi(_frames, 1),
		# If the player died mid-sample the run measured a death screen, not gameplay — say so loudly.
		"player_alive": is_instance_valid(_player),
		"player_hp": (_player.get(&"health") if is_instance_valid(_player) else null),
		"npcs_in_tree": get_tree().get_nodes_in_group(Groups.NPC).size(),
		"frame_ms": frame,
		"fps_from_delta": 1000.0 / maxf(frame["p50"], 0.001),
		"fps_monitor": _stats(_fps),
		"hitches_over_2x_median": hitches,
		"hitch_rate_pct": 100.0 * hitches / maxi(_frames, 1),
		"worst_frame_ms": worst,
		# Per-second MAXIMA (see the _dt comment) — a hitch gauge, not a mean.
		"worst_process_step_ms": _stats(_proc_max),
		"worst_physics_step_ms": _stats(_phys_max),
		# The NavigationServer runs its own step (path queries + RVO avoidance). RVO is O(agents x neighbours),
		# so with a crowd this is a prime super-linear suspect and it does NOT show up in _physics_process.
		"worst_navigation_step_ms": _stats(_nav_max),
		"draw_calls": _stats(_draws),
		"objects": _stats(_objs),
		"primitives": _stats(_prims),
		"viewports": [],
		"engine": {
			"max_fps": Engine.max_fps,
			"physics_ticks_per_second": Engine.physics_ticks_per_second,
			"vsync": DisplayServer.window_get_vsync_mode(),
			"scaling_3d_scale": get_viewport().scaling_3d_scale,
			"scaling_3d_mode": get_viewport().scaling_3d_mode,
			"viewport_size": str(get_viewport().get_visible_rect().size),
			"debug_build": OS.is_debug_build(),
			"gpu": RenderingServer.get_video_adapter_name(),
			# The window's own state. `window/size/no_focus=true` in project.godot is unusual for a game —
			# an unfocused window is descheduled by Windows, which reads as low fps + input lag + judder.
			"window_mode": DisplayServer.window_get_mode(),
			"window_size": str(DisplayServer.window_get_size()),
			"no_focus_flag": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS),
			"is_focused": DisplayServer.window_is_focused(),
			"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		},
		"physics_3d": {
			"active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			"collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
			"island_count": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		},
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}
	for rid: RID in _viewports:
		var d: Dictionary = _viewports[rid]
		(out["viewports"] as Array).append({
			"name": d["name"],
			"cpu_ms": _stats(d["cpu"]),
			"gpu_ms": _stats(d["gpu"]),
		})
	# Per-waypoint frame time: an average over a tour hides the one corner of the map that tanks.
	if not _waypoints.is_empty() and _wp_of_frame.size() == _dt.size():
		var by_wp := {}
		for i in _dt.size():
			var w: int = _wp_of_frame[i]
			if not by_wp.has(w):
				by_wp[w] = [] as Array[float]
			(by_wp[w] as Array).append(_dt[i])
		var wp_rows := []
		for w: int in by_wp:
			var s := _stats(by_wp[w])
			wp_rows.append({"waypoint": w, "pos": str(_waypoints[w]), "frame_ms_p50": s["p50"],
					"frame_ms_p95": s["p95"], "fps": 1000.0 / maxf(s["p50"], 0.001), "frames": (by_wp[w] as Array).size()})
		wp_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["frame_ms_p50"] > b["frame_ms_p50"])
		out["waypoints"] = wp_rows
	print("[probe-json] ", JSON.stringify(out))
	# Human-readable, because the JSON line is for the harness and this is for a person reading the console.
	print("\n===== PERF PROBE: ", _variant, " (", _frames, " frames) =====")
	print("  FRAME      median %.2f ms  =  %.0f fps      p95 %.2f ms   worst %.2f ms"
			% [frame["p50"], out["fps_from_delta"], frame["p95"], worst])
	print("  hitches    %d / %d frames over 2x median (%.1f%%)" % [hitches, _frames, out["hitch_rate_pct"]])
	var gpu_total := 0.0
	for vp: Dictionary in out["viewports"]:
		gpu_total += vp["gpu_ms"]["p50"]
		print("  viewport %-34s render cpu %.2f ms   GPU %.2f ms (p95 %.2f)"
				% [vp["name"], vp["cpu_ms"]["p50"], vp["gpu_ms"]["p50"], vp["gpu_ms"]["p95"]])
	print("  GPU total  %.2f ms  ->  headroom: GPU could sustain %.0f fps" % [gpu_total, 1000.0 / maxf(gpu_total, 0.001)])
	print("  CPU-only   %.2f ms of the frame is NOT GPU work" % [frame["p50"] - gpu_total])
	print("  worst step in last second:  _process %.2f ms   _physics %.2f ms"
			% [out["worst_process_step_ms"]["p50"], out["worst_physics_step_ms"]["p50"]])
	print("  draw calls median %.0f   objects %.0f   primitives %.0f"
			% [out["draw_calls"]["p50"], out["objects"]["p50"], out["primitives"]["p50"]])
	print("  physics3d  active %.0f   collision pairs %.0f   islands %.0f"
			% [out["physics_3d"]["active_objects"], out["physics_3d"]["collision_pairs"], out["physics_3d"]["island_count"]])
	print("  vram %.0f MB (textures %.0f MB)   static mem %.0f MB   nodes %.0f   orphans %.0f"
			% [out["video_mem_mb"], out["texture_mem_mb"], out["static_mem_mb"], out["node_count"], out["orphans"]])
	print("  engine: max_fps=%d physics_hz=%d scale3d=%.2f viewport=%s debug=%s gpu=%s"
			% [Engine.max_fps, Engine.physics_ticks_per_second, get_viewport().scaling_3d_scale,
			out["engine"]["viewport_size"], str(OS.is_debug_build()), out["engine"]["gpu"]])
	print("=====================================\n")
	var f := FileAccess.open("user://perf_probe_%s.json" % _variant, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "\t"))
		f = null


## The live InkOutline (a MeshInstance3D parked on the camera rig). Found by its exports rather than by
## class_name so the probe never names a class the editor may not have re-registered.
func _find_ink_outline() -> Node:
	for n in _all_nodes(get_tree().root):
		if n.get(&"occlusion_aware_mask") != null and n.get(&"mask_resolution") != null:
			return n
	return null


## Annotate the shot with the ink pass's live occlusion settings. Actors are ALWAYS on the mask layer now —
## occlusion is decided per-pixel in the shader from the mask's depth channel, not by stripping the layer
## bit off hidden actors (that CPU cull was tried and removed; see InkOutline's header). So counting mask
## bits, as this used to, would report the same number every run and prove nothing.
func _report_mask_bits() -> void:
	var ink := _find_ink_outline()
	if ink == null:
		print("[probe] ink outline: NOT FOUND")
		return
	print("[probe] ink outline: occlusion_aware_mask=%s bias=%.3f rim_search_px=%.1f mask_resolution=%.2f"
			% [ink.get(&"occlusion_aware_mask"), ink.get(&"mask_occlusion_bias"),
			ink.get(&"mask_rim_search_px"), ink.get(&"mask_resolution")])


func _stats(a: Array) -> Dictionary:
	var v: Array[float] = []
	for x in a:
		v.append(float(x))
	if v.is_empty():
		return {"p5": 0.0, "p50": 0.0, "p95": 0.0, "min": 0.0, "max": 0.0, "mean": 0.0}
	v.sort()
	var sum := 0.0
	for x in v:
		sum += x
	return {
		"p5": v[int(v.size() * 0.05)],
		"p50": v[int(v.size() * 0.5)],
		"p95": v[mini(int(v.size() * 0.95), v.size() - 1)],
		"min": v[0],
		"max": v[v.size() - 1],
		"mean": sum / v.size(),
	}


func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children(true):
			stack.append(c)
	return out
