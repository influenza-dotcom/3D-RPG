extends SceneTree
## View-model TONEMAP QA probe — photographs the first-person gun against the world twice from an IDENTICAL pose:
## once with the view-model pass's AgX curve left at the engine defaults (what the gun was graded at BEFORE this
## fix) and once with the world's authored curve copied onto it (AFTER). Judged by eye from the PNGs, and
## MEASURED off the gun pass's own render target so the answer is not purely a matter of taste.
##
## ⭐WHY THIS EXISTS: ViewModelCamera.build_default_environment() copies the world's tonemap onto the gun pass so
## the weapon "reads like the world". It copied tonemap_mode / tonemap_exposure / tonemap_white — but under AgX
## (tonemap_mode 4, what every shipped level uses) tonemap_white is IGNORED, and the curve is shaped by
## tonemap_agx_contrast / tonemap_agx_white, which were NOT copied. trenchboom_test_level authors contrast 2.0,
## so the gun graded at the AgX default 1.25: its shadows sat LIFTED against the world composited directly behind
## it. A tonemap is a rendered-pixel fact — no headless test in this suite can see it, which is why the fix is not
## done until this probe has run.
##
## ⭐AND WHAT IT ACTUALLY CAUGHT (2026-08-24): none of that copy was reaching the game at all. game.tscn's GameRoot
## loads the level with `load_level.call_deferred` from its _ready, while head.setup() queues _build_pass from the
## Player's _enter_tree — which lands FIRST, so at build time there is no WorldEnvironment in the tree, world_env
## comes back null and the whole block is skipped. The shipped gun was on tonemap_mode 0 (LINEAR) against an AgX
## world. Hence ViewModelCamera._follow_world_tonemap, and hence the three-way A/B below: LINEAR (what shipped) ->
## AgX at the engine default curve (the bug as originally described) -> AgX at the world's authored curve (now).
##
## Run from the project root as a REAL WINDOWED RUN — NOT --headless, the GPU must actually tonemap:
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/view_model_tonemap_qa_shots.gd -- --shots-dir=<dir>
## Omit --shots-dir to write user://view_model_tonemap_qa_shots. Expect a ~30 s windowed run.
##
## ⭐THE PLAYER SPAWNS HOLDING FISTS. A pass that skips the pistol equip photographs empty hands and proves
## nothing — and the view model is only re-instantiated on Attack.swap_finished, which a direct inventory.equip()
## never emits, so the gun rig must be asked to re-equip its model by hand (the muzzle_smoke_qa_shots lesson).
## ⭐A `-s` script COMPILES BEFORE AUTOLOADS REGISTER, so WorldClock is resolved from /root at runtime — naming it
## as an identifier here is a hard compile fail (the house harness gotcha).
## ⭐Overlays are NOT stripped wholesale here. The gun composite (SubViewportContainer "ViewModelComposite") lives
## ON the HUD CanvasLayer, so the flashlight probe's _strip_overlays() would hide the very thing being shot. Only
## the boot title and the debug layers go.

const GAME := "res://scenes/game.tscn"
const WEAPON := "res://resources/weapons/pistol.tres"

## Noon. The mismatch is a SHADOW-END divergence and it is worst when the world is bright — which is exactly the
## state the level sits in now that the day/night arc drives it, and 0.5 is the top of that arc.
const TIME_OF_DAY := 0.5

## Extra FOV pushed onto the gun pass ALONE for the trailing diagnostic pair. The shipped first-person rig parks
## the pistol half off the bottom-right corner at ~0.6% of the frame — an honest photograph of the game and a
## useless one for judging a grade. Widening the gun camera's FOV pulls the whole weapon into frame; it changes
## PERSPECTIVE only, never shading, so the tone being judged is still the shipped tone.
const DIAG_FOV_OFFSET := 45.0

## Godot 4.7.1's Environment defaults for the AgX curve pair — i.e. the values the gun pass was ACTUALLY graded
## at before this fix, because build_default_environment never copied them. Hard-coded (rather than read off a
## fresh Environment) so the BEFORE shot stays pinned to the real regression even if the engine defaults move.
const AGX_DEFAULT_CONTRAST := 1.25
const AGX_DEFAULT_WHITE := 16.29

var _dir := "user://view_model_tonemap_qa_shots"
var _started := false
var _done := false
var _rows: Array[Dictionary] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--shots-dir="):
			_dir = String(a).trim_prefix("--shots-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	# Windowed and large: the project ships a 396x216 internal viewport and stretch mode "viewport", so this
	# scales the OUTPUT, not the render — the shots stay the shipped resolution, they are just visible while it runs.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)

	change_scene_to_file(GAME)
	await _frames(180)   # level loads, ps1 applier walks, nav bakes, the sky title runs its fade

	_hide_boot_and_debug_overlays()

	# Find the gun pass first and climb to its host: the ViewModelCamera is created in CODE by head.gd as a child
	# of the live camera, so walking down to it is more robust than guessing the player's node path.
	var vm: Node = root.find_child("ViewModelCamera", true, false)
	if vm == null:
		print("QA_FAIL no ViewModelCamera in the tree — the view-model pass never built")
		_finish(1)
		return
	var player: Node3D = _host_of(vm)
	var cam := vm.get_parent() as Camera3D
	if player == null or cam == null:
		print("QA_FAIL player=", player, " cam=", cam)
		_finish(1)
		return

	# Freeze the clock at daylight BEFORE settling, so the volumetric fog reprojects to one steady image and both
	# exposures below are lit identically (the day_night_shots lesson: a clock jump takes ~150 frames to settle).
	var clock: Node = root.get_node_or_null("/root/WorldClock")
	if clock != null:
		clock.set(&"day_length_seconds", 0.0)
		clock.call(&"set_time_of_day", TIME_OF_DAY)

	# ⭐EQUIP A GUN. Fists have no view model worth grading; without this every shot is of empty hands.
	var inv: Object = null
	var attack: Object = null
	if player.get("weapon_system") != null:
		attack = player.weapon_system.attack
		inv = player.weapon_system.inventory
	if attack != null:
		attack.set_holstered(false)
	await _frames(90)   # the draw is a tween behind a lock that can refuse — let it finish
	if inv != null:
		inv.equip(load(WEAPON))
		await _frames(90)
		# inventory.equip() only fires weapon_changed; the VIEW MODEL is re-instantiated on Attack.swap_finished,
		# which a direct equip never emits — so the rig would still be showing the fists. Ask it directly.
		var gm: Node = player.find_child("GunMesh", true, false)
		if gm != null and gm.has_method("_equip_view_model"):
			gm.call("_equip_view_model")
			await _frames(40)

	# Stand on the level's authored PlayerSpawn, then point at the street rather than at whatever wall happens to be
	# ahead: a grade change is invisible on one flat surface filling the frame — it needs depth and a range of world
	# values behind the gun. Teleporting first is what makes the run REPRODUCIBLE: booting through game.tscn honours
	# a saved position, so back-to-back runs otherwise start metres apart and the shots stop being comparable.
	var spawn := get_first_node_in_group(&"player_spawn") as Node3D
	if spawn != null:
		player.global_position = spawn.global_position + Vector3(0.0, 0.2, 0.0)
		await _frames(10)
	_face_the_open_view(player, cam)
	await _frames(150)   # fog settle after the clock jump + the turn

	var world_env := _world_environment()
	var gun_env := _gun_environment(vm)
	if gun_env == null:
		print("QA_FAIL the gun camera has no Environment — nothing to grade")
		_finish(1)
		return

	print("QA_MODE composited=", vm.get(&"_composited"), " gun_cull=", (vm.get(&"_gun_camera") as Camera3D).cull_mask,
			" main_cull=", cam.cull_mask, " viewport=", root.get_viewport().get_visible_rect().size)
	var wd: Object = (inv.equipped_weapon if inv != null else null)
	print("QA_WEAPON ", (wd.resource_path if wd != null else "NONE"),
			" holstered=", (attack.holstered if attack != null else "?"))
	if world_env == null:
		print("QA_FAIL no WorldEnvironment in group world_environment — the copy had no source")
		_finish(1)
		return
	print("QA_WORLD_ENV mode=", world_env.tonemap_mode, " exposure=", world_env.tonemap_exposure,
			" white=", world_env.tonemap_white, " agx_contrast=", world_env.tonemap_agx_contrast,
			" agx_white=", world_env.tonemap_agx_white)
	print("QA_GUN_ENV  mode=", gun_env.tonemap_mode, " exposure=", gun_env.tonemap_exposure,
			" white=", gun_env.tonemap_white, " agx_contrast=", gun_env.tonemap_agx_contrast,
			" agx_white=", gun_env.tonemap_agx_white)
	# THE CONTRACT, asserted inside the run so a silent revert of the fix can never pass as a clean set of
	# screenshots: after the fix the gun's curve pair must equal the world's.
	var matched := is_equal_approx(gun_env.tonemap_agx_contrast, world_env.tonemap_agx_contrast)
	matched = matched and is_equal_approx(gun_env.tonemap_agx_white, world_env.tonemap_agx_white)
	print("QA_MATCH agx_pair_copied=", matched)

	# --- THE A/B, three ways. Same pose, same clock, same frame budget; the ONLY thing that changes per shot is the
	# gun pass's tonemap. 00 = what the game actually shipped (no copy ever reached it, so LINEAR). 01 = the bug as
	# originally described (AgX, engine default curve). 02 = what ships now (AgX at the world's authored curve).
	await _capture("00_day_shipped_linear", vm, gun_env, Environment.TONE_MAPPER_LINEAR, AGX_DEFAULT_CONTRAST, AGX_DEFAULT_WHITE)
	await _capture("01_day_agx_default_curve", vm, gun_env, Environment.TONE_MAPPER_AGX, AGX_DEFAULT_CONTRAST, AGX_DEFAULT_WHITE)
	await _capture("02_day_agx_world_curve", vm, gun_env, world_env.tonemap_mode, world_env.tonemap_agx_contrast, world_env.tonemap_agx_white)

	# The other end of the arc: dusk, where the world's own shadows are long and the gun's lifted blacks had the
	# most to sit against. Same three, so the fix is shown to hold across the day/night range and not just at noon.
	if clock != null:
		clock.call(&"set_time_of_day", 0.72)
	await _frames(180)
	await _capture("03_dusk_shipped_linear", vm, gun_env, Environment.TONE_MAPPER_LINEAR, AGX_DEFAULT_CONTRAST, AGX_DEFAULT_WHITE)
	await _capture("04_dusk_agx_default_curve", vm, gun_env, Environment.TONE_MAPPER_AGX, AGX_DEFAULT_CONTRAST, AGX_DEFAULT_WHITE)
	await _capture("05_dusk_agx_world_curve", vm, gun_env, world_env.tonemap_mode, world_env.tonemap_agx_contrast, world_env.tonemap_agx_white)

	# --- THE DIAGNOSTIC PAIR. Back to noon, gun pass widened so the WHOLE weapon is inside the frame (the shipped
	# rig clips it at the corner). Perspective only — the shading under judgement is untouched — and this is the
	# pair to actually look at when deciding whether the world's curve flatters the gun or crushes it.
	if clock != null:
		clock.call(&"set_time_of_day", TIME_OF_DAY)
	vm.set(&"fov_offset", DIAG_FOV_OFFSET)
	await _frames(180)
	await _capture("06_diag_agx_default_curve", vm, gun_env, Environment.TONE_MAPPER_AGX, AGX_DEFAULT_CONTRAST, AGX_DEFAULT_WHITE)
	await _capture("07_diag_agx_world_curve", vm, gun_env, world_env.tonemap_mode, world_env.tonemap_agx_contrast, world_env.tonemap_agx_white)
	vm.set(&"fov_offset", 0.0)

	_report()
	_finish(0)


## One labelled shot: set the gun pass's tonemap, let it land on screen, then save BOTH the shipped composite (what
## the player sees) and the gun pass's own render target (the weapon alone, no world in the average), and measure
## the latter. Split across frames on purpose — a value written this frame is not on screen until the next one, and
## a probe that shoots in the same frame silently captures the PREVIOUS variant.
func _capture(name: String, vm: Node, gun_env: Environment, mode: int, contrast: float, white: float) -> void:
	gun_env.tonemap_mode = mode
	gun_env.tonemap_agx_contrast = contrast
	gun_env.tonemap_agx_white = white
	await _frames(6)
	await RenderingServer.frame_post_draw

	var composite := root.get_viewport().get_texture().get_image()
	_save(composite, name + "_composite")

	var stats := {}
	var tex: Texture2D = vm.call(&"coverage_texture")
	if tex != null:
		var gun := tex.get_image()
		_save(gun, name + "_gun_pass")
		stats = _gun_stats(gun)
		# The shot that is actually judged: the SAME composite pixels, cropped to where the weapon is and blown up
		# nearest-neighbour. No rendered value is altered — it is a magnifying glass, not a second render.
		var rect := _gun_rect(gun)
		if rect.size.x > 1 and rect.size.y > 1:
			_save(_blow_up(composite, rect, gun.get_size()), name + "_zoom")
	print("QA_SHOT ", name, " mode=", mode, " agx_contrast=", contrast, " agx_white=", white, "  ", stats)
	_rows.append({"name": name, "stats": stats})


## The weapon's bounding box in the gun pass's alpha, padded so a slice of the WORLD behind it comes along — the
## comparison being judged is gun-against-world, so a crop of the gun alone would answer the wrong question.
func _gun_rect(img: Image) -> Rect2i:
	var min_x := img.get_width()
	var min_y := img.get_height()
	var max_x := -1
	var max_y := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	const PAD := 40
	var r := Rect2i(min_x - PAD, min_y - PAD, (max_x - min_x) + PAD * 2, (max_y - min_y) + PAD * 2)
	return r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))


## Crop `rect` out of `img` and scale it up nearest-neighbour, so the magnification introduces no new colours —
## an interpolated blow-up would invent intermediate tones and quietly soften the very shadow end under review.
## `rect` is expressed in the gun pass's pixels; rescaled here in case that target is not the main viewport's size.
func _blow_up(img: Image, rect: Rect2i, gun_size: Vector2i = Vector2i.ZERO) -> Image:
	var r := rect
	if gun_size != Vector2i.ZERO and gun_size != img.get_size():
		var sx := float(img.get_width()) / float(gun_size.x)
		var sy := float(img.get_height()) / float(gun_size.y)
		r = Rect2i(int(r.position.x * sx), int(r.position.y * sy), int(r.size.x * sx), int(r.size.y * sy))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var out := img.get_region(r)
	out.resize(out.get_width() * 4, out.get_height() * 4, Image.INTERPOLATE_NEAREST)
	return out


## Mean and percentile luminance of the GUN's own pixels. The view-model SubViewport clears TRANSPARENT and only
## the view-model layer draws into it, so its ALPHA is exactly the weapon's screen coverage — that is
## ViewModelCamera.coverage_texture's documented contract, the same signal WorldGhost masks with. Measuring there,
## not on the composite, is the only way to read the gun without the world in the average.
## p10/p25 are the numbers that matter: a contrast change moves the SHADOW end, and that is the whole complaint.
func _gun_stats(img: Image) -> Dictionary:
	var lums := PackedFloat32Array()
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				lums.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	if lums.is_empty():
		return {"n": 0}
	lums.sort()
	var total := 0.0
	for v in lums:
		total += v
	var n := lums.size()
	return {
		"n": n,
		"mean": snappedf(total / float(n), 0.0001),
		"p10": snappedf(lums[int(n * 0.10)], 0.0001),
		"p25": snappedf(lums[int(n * 0.25)], 0.0001),
		"p50": snappedf(lums[int(n * 0.50)], 0.0001),
		"p90": snappedf(lums[int(n * 0.90)], 0.0001),
	}


## The six rows side by side, so the DIRECTION of each change is readable without opening a single PNG. Copying the
## MODE (LINEAR -> AgX) is the large move; copying the CURVE on top of it darkens the gun's shadow end further
## (AgX contrast 1.25 -> the world's 2.0), which is the specific mismatch this fix was raised for.
func _report() -> void:
	print("QA_TABLE name | coverage_px | mean | p10 | p25 | p50 | p90")
	for r in _rows:
		var s: Dictionary = r["stats"]
		if int(s.get("n", 0)) == 0:
			print("QA_ROW ", r["name"], " | NO GUN PIXELS — the weapon was not on screen")
			continue
		print("QA_ROW ", r["name"], " | ", s["n"], " | ", s["mean"], " | ", s["p10"], " | ",
				s["p25"], " | ", s["p50"], " | ", s["p90"])
	_delta("day  linear->agx", 0, 1)
	_delta("day  agx-default->agx-world", 1, 2)
	_delta("dusk linear->agx", 3, 4)
	_delta("dusk agx-default->agx-world", 4, 5)
	_delta("diag agx-default->agx-world", 6, 7)


func _delta(label: String, before: int, after: int) -> void:
	if _rows.size() <= after:
		return
	var a: Dictionary = _rows[before]["stats"]
	var b: Dictionary = _rows[after]["stats"]
	if int(a.get("n", 0)) == 0 or int(b.get("n", 0)) == 0:
		return
	for k in ["p10", "p25", "p50", "p90"]:
		print("QA_DELTA ", label, " ", k, " ", a[k], " -> ", b[k], "  (", snappedf(float(b[k]) - float(a[k]), 0.0001), ")")


func _save(img: Image, name: String) -> void:
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		print("QA_SHOT_FAIL ", path, " err=", err)


## The level's WorldEnvironment Environment — the same group lookup ViewModelCamera itself copies from, so this
## probe reads the exact source the fix reads and cannot drift from it.
func _world_environment() -> Environment:
	var we := get_first_node_in_group(&"world_environment") as WorldEnvironment
	return we.environment if we != null else null


## The live Environment on the gun camera. Null when a designer authored view_model_environment (used verbatim,
## so there would be nothing for the copy to do) or when the pass never built.
func _gun_environment(vm: Node) -> Environment:
	var gun_cam := vm.get(&"_gun_camera") as Camera3D
	return gun_cam.environment if gun_cam != null else null


## Climb from the ViewModelCamera to the actor that owns it (head.gd parents it under the live camera, several
## levels below the Player). Identified by the weapon_system property rather than by a node name or a group, so a
## rig rename cannot quietly turn this probe into a shot of nothing.
func _host_of(vm: Node) -> Node3D:
	var n: Node = vm
	while n != null:
		if n is Node3D and n.get("weapon_system") != null:
			return n as Node3D
		n = n.get_parent()
	return null


## Hide the boot title and the debug layers ONLY. The HUD CanvasLayer stays visible on purpose: it carries both
## the post-process ColorRect the player actually looks through AND the gun's own composite container, so hiding
## it would delete the subject of the photograph.
func _hide_boot_and_debug_overlays() -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer and (String(n.name).begins_with("Debug") or String(n.name) == "AiEventLog"):
			(n as CanvasLayer).visible = false
		elif String(n.name) == "SkyTitle" and n is Node3D:
			# FREED, not hidden: sky_title.gd drives its own `visible` through the fade, so a hide here is undone
			# on the next frame and the word CYBERSUNDAY sits across the middle of every shot (measured).
			n.queue_free()
			continue
		stack.append_array(n.get_children())


## Turn the player toward the longest clear line of sight — the street, not the wall he happens to spawn facing.
func _face_the_open_view(player: Node3D, cam: Camera3D) -> void:
	var space := player.get_world_3d().direct_space_state
	var eye := cam.global_position
	var best_dir := -player.global_transform.basis.z
	var best_d := -1.0
	for i in 24:
		var yaw := TAU * float(i) / 24.0
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 60.0)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		var d: float = (eye.distance_to(hit["position"] as Vector3) if not hit.is_empty() else 60.0)
		if d > best_d:
			best_d = d
			best_dir = dir
	player.look_at(player.global_position + best_dir, Vector3.UP)
	print("QA_POSE at ", player.global_position, " facing ", best_dir, " clear=", best_d, " m")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish(code: int) -> void:
	print("QA_DONE dir=", ProjectSettings.globalize_path(_dir))
	_done = true
	quit(code)
