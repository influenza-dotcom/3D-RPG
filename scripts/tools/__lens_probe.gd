extends Node
## THROWAWAY QA probe for the new `dof` / `sway` debug commands (2026-08-20). Delete when done.
##
## WHY IT EXISTS. GUT deliberately never executes DebugActionsWorld.run() -- those commands write real autoload
## state -- so tests/test_debug_commands.gd proves the registry is consistent and the module COMPILES, and
## nothing more. Whether `dof near` actually reaches the GPU is not a question a headless run can ask: headless
## runs a dummy rasterizer and never compiles a shader. So this boots the REAL game windowed, drives the
## commands through the same entry point the console and the F1 menu use, and MEASURES the frame.
##
## THE MEASUREMENT. Blur removes high-frequency detail, so the mean absolute gradient of the frame
## (|p - right| + |p - down|, averaged) FALLS when a blur engages.
##
## ⭐ EVERY COMPARISON IS AN ADJACENT PAIR, NEVER AGAINST A STORED BASELINE. First attempt did the obvious thing
## -- one baseline, then compare every later shot to it -- and `dof reset` came back 32% ABOVE its own baseline,
## which reads as "reset is broken" and is not. Two things drift underneath a pixel measurement in this game:
## the DAY/NIGHT CYCLE moves the sun between shots (the HUD clock ran 13:02 -> 14:06 across one run), and the
## HUD RE-SHOWS ITSELF past any hide -- the Player's own per-frame pushers write visibility every physics tick,
## the exact trap `hud off` documents in debug_actions_world.gd. So: Engine.time_scale is frozen for the whole
## measurement, the overlays are re-stripped immediately before EVERY shot, and each A/B takes its OFF and ON
## frames back to back. `dof reset` is then verified where it is actually decidable -- by reading the seven
## properties back and comparing them to DOF_AUTHORED -- not by counting pixels.
##
## ⭐ FILM GRAIN AND DITHER ARE ZEROED FOR THE MEASUREMENT. Both are per-pixel high-frequency noise applied
## AFTER the 3D buffer the DoF blurs, so they would swamp the gradient delta. Both are restored at the end.
## ⭐ NEVER `Settings.set_*` HERE. Every setter calls save_settings(), which rewrites the player's real
## user://settings.cfg -- the documented __perf_probe trap. Everything below goes through `.set()`, in memory.
##
## Run windowed from the project root (NOT --headless, the GPU must render):
##   godot --path . res://scripts/tools/__lens_probe.tscn -- --shots-dir="C:/some/dir"

const WorldActions := preload("res://scripts/components/debug_actions_world.gd")
const GroupsScript := preload("res://scripts/world/groups.gd")

var _dir := "user://qa_shots/lens"
var _post: ShaderMaterial = null
var _post_layer: CanvasLayer = null   ## the ONE CanvasLayer that must stay visible -- it carries the shipped look
var _ctx: Dictionary = {}
var _fail := 0
var _grain_authored: Variant = null
var _dither_authored := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Driver-copy pattern (flashlight_qa_shots.gd): this scene is the boot scene, but the run switches
	# current_scene to game.tscn, which frees it. Re-attach a copy on a bare Node under root and drive from there.
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "LensQaDriver"
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
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(200)   # level load, ps1 applier walk, nav bake, sky title fade, the player settling on the floor

	var player := GroupsScript.human_player(get_tree())
	if not is_instance_valid(player):
		print("QA_FAIL no human player after 200 frames (Groups.human_player)")
		get_tree().quit(1)
		return
	_ctx = {&"tree": get_tree(), &"player": player, &"host": self, &"state": {}}
	print("QA_SETUP player=", player.name, "  canvas=", get_viewport().get_texture().get_size())

	var attrs := _attrs(player)
	if attrs == null:
		print("QA_FAIL the player camera has no CameraAttributesPractical")
		get_tree().quit(1)
		return
	# The authored state, read off the LIVE object -- this is the ground truth DOF_AUTHORED claims to mirror,
	# including the three engine defaults for fields camera_rig.tscn never writes.
	print("QA_AUTHORED near_enabled=%s near_distance=%.3f near_transition=%.3f far_enabled=%s far_distance=%.3f far_transition=%.3f amount=%.3f" % [
		str(attrs.dof_blur_near_enabled), attrs.dof_blur_near_distance, attrs.dof_blur_near_transition,
		str(attrs.dof_blur_far_enabled), attrs.dof_blur_far_distance, attrs.dof_blur_far_transition,
		attrs.dof_blur_amount])
	_check_authored_const(attrs)

	# --- the reports read correctly before anything is touched --------------------------------------------
	_say("dof (no args)", WorldActions.run("dof", _ctx, PackedStringArray()))
	_say("sway (no args)", WorldActions.run("sway", _ctx, PackedStringArray()))

	if not _restore_post_process():
		print("QA_FAIL no post-process CanvasLayer found -- shots would not be the shipped look")
		_fail += 1
	_neutralise_noise()
	# Freeze the world for the pixel work: the day/night cycle and every animation ride delta, and a sun that
	# moves between two shots is indistinguishable from a blur that did not engage.
	Engine.time_scale = 0.0
	await _frames(8)

	# --- does near DoF reach the GPU at all? --------------------------------------------------------------
	var slam := await _ab("01_near_slammed", ["near", "8", "6"], "0.35")
	print("QA_AB near 8 m @ amount 0.35 softened the frame by %.1f%%" % slam)
	if slam < 5.0:
		print("QA_FAIL the near blur did not soften the frame -- the switch flipped but nothing reached the GPU")
		_fail += 1
	else:
		print("QA_PASS near DoF reaches the GPU: enabling it measurably softens the frame")

	# --- how far the near cue has to reach to be FELT from where the player is standing --------------------
	# The honest question this answers: `near 1.0` is invisible in the open, because nothing is within a metre.
	# The sweep says how far out the ramp must go before it bites, which is how a value gets picked.
	for d in [1.0, 1.5, 2.0, 3.0, 5.0]:
		var soft := await _ab("02_near_%.1fm" % d, ["near", str(d), str(d * 0.75)], "0.18")
		print("QA_SWEEP near %.1f m @ amount 0.18 -> %.1f%% softer than the same frame with near off" % [d, soft])

	# --- amount alone, near off: the one-line change, measured ---------------------------------------------
	for amt in ["0.14", "0.18", "0.28"]:
		var soft := await _ab_amount("03_amount_%s" % amt, amt)
		print("QA_SWEEP amount %s (near off, far authored OFF since 2026-08-24 -> expect ~0%%) -> %.1f%% softer than amount 0.10" % [amt, soft])

	# --- `dof reset` is verified by PROPERTY, not by pixels ------------------------------------------------
	WorldActions.run("dof", _ctx, PackedStringArray(["near", "4", "3"]))
	WorldActions.run("dof", _ctx, PackedStringArray(["far", "12", "2"]))
	WorldActions.run("dof", _ctx, PackedStringArray(["amount", "0.5"]))
	_say("dof reset", WorldActions.run("dof", _ctx, PackedStringArray(["reset"])))
	if _check_authored_const(attrs, "after reset"):
		print("QA_PASS `dof reset` put all seven fields back to the authored state")

	# --- the far-half trap: does the ADS snapshot PAIR get updated? ----------------------------------------
	_say("dof far 24 8", WorldActions.run("dof", _ctx, PackedStringArray(["far", "24", "8"])))
	var cam: Variant = player.get(&"camera_effects")
	var snap: Variant = cam.get(&"_dof_default_far_distance") if cam != null else null
	var snap_on: Variant = cam.get(&"_dof_default_far_enabled") if cam != null else null
	if snap is float and is_equal_approx(float(snap), 24.0) and snap_on == true:
		print("QA_PASS CameraEffects' snapshot pair updated (enabled + 24.0 m) -- an unscope will NOT undo `dof far`")
	else:
		print("QA_FAIL snapshot pair is enabled=%s distance=%s, not true/24.0 -- the next unscope would restore the authored far state (off)" % [str(snap_on), str(snap)])
		_fail += 1

	# --- the resting state survives an aim cycle: unscope restores the AUTHORED far state (OFF) ------------
	# This is the exact regression path of the 2026-08-24 fix: set_scope_dof() used to force
	# dof_blur_far_enabled = true on every unscope, so the first aim resurrected the retired 30 m far blur
	# and the distance went back to mush. Drive a scope/unscope through the real method and read the flag.
	WorldActions.run("dof", _ctx, PackedStringArray(["reset"]))
	if cam != null and (cam as Object).has_method(&"set_scope_dof"):
		cam.call(&"set_scope_dof", true, false)
		cam.call(&"set_scope_dof", false, false)
		if attrs.dof_blur_far_enabled == bool(WorldActions.DOF_AUTHORED["far_enabled"]):
			print("QA_PASS an aim cycle leaves the far blur in the authored state (off) -- unscope no longer forces it on")
		else:
			print("QA_FAIL an aim cycle left dof_blur_far_enabled=%s -- unscope is still forcing the old far blur back on" % str(attrs.dof_blur_far_enabled))
			_fail += 1
	else:
		print("QA_FAIL no CameraEffects.set_scope_dof reachable to drive the aim cycle")
		_fail += 1

	# --- the near-ramp guard fires on the exact pair camera_rig.tscn ships --------------------------------
	var bad := WorldActions.run("dof", _ctx, PackedStringArray(["near", "0.5", "1.0"]))
	_say("dof near 0.5 1.0 (deliberately unlandable)", bad)
	if not _contains(bad, "BEHIND the lens"):
		print("QA_FAIL the transition >= distance guard did not fire on the shipped 0.5/1.0 pair")
		_fail += 1
	else:
		print("QA_PASS the unlandable-ramp guard fires on the shipped 0.5/1.0 pair")

	# --- sway: the writes land on the live GunPose, and reset puts them back -------------------------------
	var pose := _pose(player)
	if pose == null:
		print("QA_FAIL no GunPose reachable via player.gun_mesh._pose")
		_fail += 1
	else:
		_say("sway preset 1", WorldActions.run("sway", _ctx, PackedStringArray(["preset", "1"])))
		var ok := is_equal_approx(float(pose.get(&"mouse_sway_pos")), 0.085) \
			and is_equal_approx(float(pose.get(&"mouse_sway_max")), 0.45) \
			and is_equal_approx(float(pose.get(&"mouse_sway_roll_deg")), 1.6) \
			and is_equal_approx(float(pose.get(&"mouse_sway_pitch_deg")), 1.0) \
			and is_equal_approx(float(pose.get(&"mouse_sway_decay")), 9.0)
		print(("QA_PASS " if ok else "QA_FAIL ") + "sway preset 1 wrote all five channels onto the live GunPose")
		if not ok:
			_fail += 1
		_say("sway roll 3.5", WorldActions.run("sway", _ctx, PackedStringArray(["roll", "3.5"])))
		if not is_equal_approx(float(pose.get(&"mouse_sway_roll_deg")), 3.5):
			print("QA_FAIL a single-knob write did not land")
			_fail += 1
		_say("sway reset", WorldActions.run("sway", _ctx, PackedStringArray(["reset"])))
		var back := is_equal_approx(float(pose.get(&"mouse_sway_pos")), 0.04) \
			and is_equal_approx(float(pose.get(&"mouse_sway_max")), 0.35) \
			and is_equal_approx(float(pose.get(&"mouse_sway_roll_deg")), 0.0) \
			and is_equal_approx(float(pose.get(&"mouse_sway_pitch_deg")), 0.0) \
			and is_equal_approx(float(pose.get(&"mouse_sway_decay")), 12.0)
		print(("QA_PASS " if back else "QA_FAIL ") + "sway reset restored gun_pose.gd's shipped defaults")
		if not back:
			_fail += 1
		_say("sway preset 9 (out of range)", WorldActions.run("sway", _ctx, PackedStringArray(["preset", "9"])))
		_say("sway off", WorldActions.run("sway", _ctx, PackedStringArray(["off"])))
		_say("sway reset (final)", WorldActions.run("sway", _ctx, PackedStringArray(["reset"])))

	# --- EVERY REMAINING BRANCH, because a bad format string is a RUNTIME error in GDScript ----------------
	# The sweeps above only walk the happy paths. A `%` whose placeholder count misses its argument array does
	# not fail to compile -- it errors at the moment that line runs and returns a mangled string, so an
	# un-exercised error branch is exactly where one hides. `sway preset` with no value is the sharpest case:
	# it formats three placeholders against a typed Array[String]. Every branch below is walked once, and _say
	# fails the run if any of them returns nothing.
	for probe in [
		["dof", ["amount"]], ["dof", ["near"]], ["dof", ["far"]],
		["dof", ["near", "0"]], ["dof", ["far", "0"]],
		["dof", ["off"]], ["dof", ["on"]], ["dof", ["reset"]],
		["sway", ["preset"]], ["sway", ["pos"]], ["sway", ["max"]], ["sway", ["roll"]],
		["sway", ["pitch"]], ["sway", ["decay"]], ["sway", ["preset", "-1"]], ["sway", ["off"]],
	]:
		var cmd: String = probe[0]
		var argv := PackedStringArray()
		for a in probe[1]:
			argv.append(str(a))
		_say("%s %s" % [cmd, " ".join(argv)], WorldActions.run(cmd, _ctx, argv))

	# And the two "no player" degrades, driven with an empty ctx -- the console can be open on the main menu.
	_say("dof with an empty ctx", WorldActions.run("dof", {}, PackedStringArray()))
	_say("sway with an empty ctx", WorldActions.run("sway", {}, PackedStringArray()))

	WorldActions.run("dof", _ctx, PackedStringArray(["reset"]))
	Engine.time_scale = 1.0

	# --- REGRESSION: a mid-run FOV change must actually reach the live camera ------------------------------
	# `CameraEffects.base_fov` used to be a cached copy of GameSettings.camera.default_fov, so CameraEffects
	# composed `_target_fov` against the OLD angle while ScopeIn's un-scoped branch eased the SAME `fov` toward
	# the NEW one -- `fov` settled between two targets. tests/test_camera_input_ui.gd pins the property; this
	# pins the thing the player actually sees, which no off-tree test can reach: two writers converging in a
	# live tree. Time scale is back to 1 above because both writers ease on a SCALED delta.
	# ⭐ The FIELD only, never Settings.set_fov() -- every setter calls save_settings() and would rewrite the
	# developer's real user://settings.cfg (the documented __perf_probe trap).
	var fov_authored: float = GameSettings.camera.default_fov
	await _frames(60)
	var fov_before: float = (cam as Camera3D).fov
	var fov_target: float = fov_authored - 25.0
	GameSettings.camera.default_fov = fov_target
	await _frames(180)
	var fov_after: float = (cam as Camera3D).fov
	GameSettings.camera.default_fov = fov_authored
	print("QA_FOV resting %.2f -> asked for %.2f -> settled at %.2f" % [fov_before, fov_target, fov_after])
	if absf(fov_after - fov_target) <= 1.0:
		print("QA_PASS a mid-run FOV change reaches the live camera -- it settled ON the new rest angle, not between two")
	else:
		print("QA_FAIL fov settled at %.2f, not the requested %.2f -- CameraEffects and ScopeIn are aiming at different targets" % [fov_after, fov_target])
		_fail += 1
	await _frames(180)   # let it ease back to the authored angle before the process quits

	# --- BARREL LENS: does it compile, and does the whole chain reach the GPU? -----------------------------
	# ⭐ Headless never compiles a .gdshader, so a syntax error in post_process.gdshader loads clean and passes
	# every test in the suite while the game silently draws a FALLBACK material. This section is the only thing
	# that can tell the difference.
	#
	# ⭐ IT DRIVES GameSettings, NOT THE MATERIAL. player.gd re-pushes `lens_barrel` onto the material every
	# frame from `GameSettings.camera.lens_barrel_amount * Settings.lens_curve`, so a direct
	# set_shader_parameter here would be overwritten on the next frame and measure nothing. Writing the source
	# also means this exercises the REAL chain end to end: tuning resource -> player.gd -> uniform -> pixels.
	Engine.time_scale = 0.0
	await _frames(6)
	var cam_set: Resource = GameSettings.camera
	var authored_barrel := _f(cam_set.get(&"lens_barrel_amount"))
	var lens_scale := _f(Settings.get(&"lens_curve"), 1.0)
	print("QA_LENS authored barrel %.3f x Lens Curve %.2f -> %.3f should be reaching the shader" % [
		authored_barrel, lens_scale, authored_barrel * lens_scale])
	if _post == null:
		print("QA_FAIL no post-process material -- cannot read the lens back")
		_fail += 1
	else:
		await _frames(4)
		var pushed := _f(_post.get_shader_parameter("lens_barrel"), -1.0)
		if is_equal_approx(pushed, authored_barrel * lens_scale):
			print("QA_PASS player.gd is pushing the resolved lens value (%.3f) onto the material every frame" % pushed)
		else:
			print("QA_FAIL the material carries lens_barrel %.3f, not the resolved %.3f -- the push site is not running" % [pushed, authored_barrel * lens_scale])
			_fail += 1

		# ⭐ THE SIGNATURE OF A BARREL WARP IS NOT "everything moves". Displacement is
		# |c| * k * (1 - r2n) / (1 + k), which is ZERO at the centre (|c| = 0) AND ZERO at the corner (r2n = 1,
		# where the corner-pinning divisor cancels the bend exactly), peaking at r2n = 1/3. A first version of
		# this gate asserted "centre moves, corner does not" and failed all four strengths on a CORRECT shader --
		# the centre patch was sitting exactly where a lens moves nothing. Measure the PEAK band instead
		# (r2n = 1/3 lies at uv.x ~ 0.83 on the horizontal midline for this 16:9 frame) and require it to beat
		# the centre by a wide margin and to grow with k. Both probes read the same bright region, so this
		# cannot be passed by a dark patch pretending to hold still.
		cam_set.set(&"lens_barrel_amount", 0.0)
		await _frames(6)
		var flat: Image = await _shot("05_lens_0.00")
		var last_peak := 0.0
		for k in [0.04, 0.08, 0.12, 0.20, 0.30]:
			cam_set.set(&"lens_barrel_amount", k)
			await _frames(6)
			var bent: Image = await _shot("05_lens_%.2f" % k)
			var d_peak := _patch_diff(flat, bent, 0.76, 0.44, 0.10)
			var d_centre := _patch_diff(flat, bent, 0.47, 0.46, 0.06)
			print("QA_LENS barrel %.2f -> peak band moved %.4f, centre %.4f" % [k, d_peak, d_centre])
			if k >= 0.08 and d_peak < 0.003:
				print("QA_FAIL barrel %.2f moved nothing -- the shader is not compiling (headless would never have told us) or the chain is broken" % k)
				_fail += 1
			elif d_peak < d_centre * 2.5:
				print("QA_FAIL barrel %.2f is not a LENS: the mid-radius band (%.4f) should move far more than the centre (%.4f)" % [k, d_peak, d_centre])
				_fail += 1
			elif d_peak < last_peak:
				print("QA_FAIL barrel %.2f moved LESS than the weaker setting before it -- the bend is not monotonic in k" % k)
				_fail += 1
			else:
				print("QA_PASS barrel %.2f bends the mid-radius band, leaves the centre and the pinned corner alone" % k)
			last_peak = d_peak

		# The fringe, for the eye.
		cam_set.set(&"lens_barrel_amount", 0.20)
		cam_set.set(&"lens_chroma_amount", 1.0)
		await _frames(6)
		var _c: Image = await _shot("06_lens_0.20_chroma_1.0")
		cam_set.set(&"lens_chroma_amount", _f(WorldActions.LENS_AUTHORED["chroma"]))

		# And the command itself, through the same entry point the console uses.
		_say("lens 0.18 0.5", WorldActions.run("lens", _ctx, PackedStringArray(["0.18", "0.5"])))
		if not is_equal_approx(_f(cam_set.get(&"lens_barrel_amount")), 0.18):
			print("QA_FAIL `lens 0.18` did not reach GameSettings.camera.lens_barrel_amount")
			_fail += 1
		else:
			print("QA_PASS `lens` writes the authored amount, which is the value player.gd multiplies")
		_say("lens 0 (flat)", WorldActions.run("lens", _ctx, PackedStringArray(["0"])))
		_say("lens (report)", WorldActions.run("lens", _ctx, PackedStringArray()))
		cam_set.set(&"lens_barrel_amount", authored_barrel)
	Engine.time_scale = 1.0

	_restore_noise()
	print("QA_DONE failures=%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# --- measurement ----------------------------------------------------------------------------------------------

## One ADJACENT A/B: near OFF then the given `near` args, both at the same blur `amount`, two shots a few frames
## apart with the overlays re-stripped before each. Returns how much softer the ON frame is, in percent.
## Adjacent because the world moves: see the drift note in the header.
func _ab(name: String, near_args: Array, amount: String) -> float:
	WorldActions.run("dof", _ctx, PackedStringArray(["amount", amount]))
	WorldActions.run("dof", _ctx, PackedStringArray(["near", "0"]))
	await _frames(6)
	var off_g := _gradient(await _shot(name + "_a_off"))
	var on_args := PackedStringArray()
	for a in near_args:
		on_args.append(str(a))
	WorldActions.run("dof", _ctx, on_args)
	await _frames(6)
	var on_g := _gradient(await _shot(name + "_b_on"))
	return (off_g - on_g) / maxf(off_g, 0.00001) * 100.0


## The same adjacent A/B for `dof amount` alone, near OFF, against the authored 0.10 -- this is the one-line
## change measured on its own, with nothing else moved.
func _ab_amount(name: String, amount: String) -> float:
	WorldActions.run("dof", _ctx, PackedStringArray(["near", "0"]))
	WorldActions.run("dof", _ctx, PackedStringArray(["amount", "0.1"]))
	await _frames(6)
	var base_g := _gradient(await _shot(name + "_a_0.10"))
	WorldActions.run("dof", _ctx, PackedStringArray(["amount", amount]))
	await _frames(6)
	var amt_g := _gradient(await _shot(name + "_b_" + amount))
	return (base_g - amt_g) / maxf(base_g, 0.00001) * 100.0


## Mean absolute first difference over the frame, right and down. Blur removes high-frequency detail, so this
## FALLS when a blur engages. RGB8 raw bytes rather than get_pixel(), for the same reason
## color_depth_qa_shots.gd does it: 792x444 per-pixel Color allocations in a loop are not free.
func _gradient(img: Image) -> float:
	if img == null:
		return 0.0
	var rgb: Image = img.duplicate()
	rgb.convert(Image.FORMAT_RGB8)
	var w := rgb.get_width()
	var h := rgb.get_height()
	var d := rgb.get_data()
	var total := 0.0
	var n := 0
	for y in range(h - 1):
		for x in range(w - 1):
			var i := (y * w + x) * 3
			var r := (y * w + x + 1) * 3
			var b := ((y + 1) * w + x) * 3
			total += absf(float(d[i]) - float(d[r])) + absf(float(d[i]) - float(d[b]))
			n += 1
	return (total / maxf(float(n), 1.0)) / 255.0


## Compare the live attributes against the const the command's `reset` restores from. Called once at boot (does
## DOF_AUTHORED actually mirror camera_rig.tscn plus the engine defaults?) and once after `dof reset`.
func _check_authored_const(attrs: CameraAttributesPractical, when: String = "as shipped") -> bool:
	var want: Dictionary = WorldActions.DOF_AUTHORED
	var bad := PackedStringArray()
	if attrs.dof_blur_near_enabled != bool(want["near_enabled"]):
		bad.append("near_enabled")
	if not is_equal_approx(attrs.dof_blur_near_distance, float(want["near_distance"])):
		bad.append("near_distance %.3f vs %.3f" % [attrs.dof_blur_near_distance, float(want["near_distance"])])
	if not is_equal_approx(attrs.dof_blur_near_transition, float(want["near_transition"])):
		bad.append("near_transition %.3f vs %.3f" % [attrs.dof_blur_near_transition, float(want["near_transition"])])
	if attrs.dof_blur_far_enabled != bool(want["far_enabled"]):
		bad.append("far_enabled")
	if not is_equal_approx(attrs.dof_blur_far_distance, float(want["far_distance"])):
		bad.append("far_distance %.3f vs %.3f" % [attrs.dof_blur_far_distance, float(want["far_distance"])])
	if not is_equal_approx(attrs.dof_blur_far_transition, float(want["far_transition"])):
		bad.append("far_transition %.3f vs %.3f" % [attrs.dof_blur_far_transition, float(want["far_transition"])])
	if not is_equal_approx(attrs.dof_blur_amount, float(want["amount"])):
		bad.append("amount %.3f vs %.3f" % [attrs.dof_blur_amount, float(want["amount"])])
	if bad.is_empty():
		print("QA_PASS DOF_AUTHORED matches the live attributes %s" % when)
		return true
	print("QA_FAIL DOF_AUTHORED does NOT match the live attributes %s: %s" % [when, ", ".join(bad)])
	_fail += 1
	return false


# --- plumbing -------------------------------------------------------------------------------------------------

func _say(label: String, lines: PackedStringArray) -> void:
	print("QA_CMD --- ", label)
	if lines.is_empty():
		print("QA_CMD     (no output -- suspicious: every path is supposed to end with the live report)")
		_fail += 1
		return
	for l in lines:
		print("QA_CMD     ", l)


func _contains(lines: PackedStringArray, needle: String) -> bool:
	for l in lines:
		if l.contains(needle):
			return true
	return false


func _attrs(player: Node) -> CameraAttributesPractical:
	var cam: Variant = player.get(&"camera_effects")
	if cam == null or not is_instance_valid(cam):
		return null
	return (cam as Camera3D).attributes as CameraAttributesPractical


func _pose(player: Node) -> Node:
	var mesh: Variant = player.get(&"gun_mesh")
	if mesh == null or not is_instance_valid(mesh):
		return null
	var p: Variant = (mesh as Node).get(&"_pose")
	if p == null or not is_instance_valid(p):
		return null
	return p as Node


## Hide everything painted OVER the 3D frame, using the GAME'S OWN `hud off` command.
##
## ⭐ THE OBVIOUS APPROACH IS WRONG HERE, and it cost a whole run to find out. color_depth_qa_shots.gd hides
## every CanvasLayer and then re-shows the one carrying the post-process shader. That works there because it only
## needs the shader back. It does NOT work for this probe: the post-process ColorRect is a CHILD of the player's
## UI CanvasLayer (player.gd caches it as `_nv_rect` at "UI/ColorRect"), so the HUD and the shipped look live on
## ONE layer -- re-showing it brings the minimap, clock, ammo and hotbar straight back, sharp, into every shot.
## `hud off` is the seam that already knows this: it hides the layer's visible CanvasItem CHILDREN and explicitly
## KEEPS the post-process ColorRect. Re-run before every shot -- a second call re-sweeps non-clobbering, which is
## exactly how it catches the Player's per-frame pushers writing their labels back.
func _strip_overlays() -> void:
	WorldActions.run("hud", _ctx, PackedStringArray(["off"]))
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		# ⭐ BY CLASS, NOT BY NODE NAME. color_depth_qa_shots.gd and flashlight_qa_shots.gd both test
		# `n.name == "SkyTitle"`, and that silently misses game.tscn's actual title node -- it sat on screen
		# through a whole run of this probe. It cannot time itself out either: its 2.5 s hold + 3.5 s fade ride
		# delta, and this probe freezes Engine.time_scale for the measurement.
		if n is SkyTitle:
			(n as Node3D).visible = false
		elif n is CanvasLayer and n != _post_layer:
			# Every OTHER CanvasLayer -- the debug event ticker, any overlay. The player's own UI layer is
			# spared here because it carries the post-process ColorRect; `hud off` above hides its HUD children
			# individually and keeps that one.
			(n as CanvasLayer).visible = false
		stack.append_array(n.get_children())


## Turn the POST-PROCESS layer back on and nothing else, and remember its material. Found by walking for the
## shader rather than by node name, so renaming the HUD cannot silently drop the shipped look out of the shots.
func _restore_post_process() -> bool:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var mat := (n as CanvasItem).material as ShaderMaterial
			if mat != null and mat.shader != null and String(mat.shader.resource_path).contains("post_process"):
				_post = mat
				var layer: Node = n
				while layer != null and not (layer is CanvasLayer):
					layer = layer.get_parent()
				if layer != null:
					_post_layer = layer as CanvasLayer
					_post_layer.visible = true
					return true
		stack.append_array(n.get_children())
	return false


## Zero the two post-process noise sources for the measurement. GRAIN goes on the material (nothing polls it);
## DITHER has to go on the Settings FIELD because player.gd pushes Settings.dither_strength onto the uniform
## every frame and a material write would be stomped on the next one -- the coupling _cmd_dither documents.
## The FIELD, never set_dither_strength(): that setter would persist 0.0 into the player's real settings.cfg.
func _neutralise_noise() -> void:
	if _post != null:
		_grain_authored = _post.get_shader_parameter("grain_amount")
		_post.set_shader_parameter("grain_amount", 0.0)
	_dither_authored = float(Settings.get(&"dither_strength"))
	Settings.set(&"dither_strength", 0.0)
	print("QA_SETUP grain %s -> 0, dither %.2f -> 0 (in memory only), Engine.time_scale -> 0 for the measurement" % [
		str(_grain_authored), _dither_authored])


func _restore_noise() -> void:
	if _post != null and _grain_authored != null:
		_post.set_shader_parameter("grain_amount", _grain_authored)
	Settings.set(&"dither_strength", _dither_authored)


## Mean absolute RGB difference between two frames over a square patch, given as fractions of the frame
## (origin + side). Used to ask a question a whole-frame number cannot: did the CENTRE move while the CORNER
## stayed put — i.e. is this actually a lens, or just a global resample?
func _patch_diff(a: Image, b: Image, fx: float, fy: float, side: float) -> float:
	if a == null or b == null:
		return 0.0
	var ia: Image = a.duplicate()
	var ib: Image = b.duplicate()
	ia.convert(Image.FORMAT_RGB8)
	ib.convert(Image.FORMAT_RGB8)
	var w := ia.get_width()
	var h := ia.get_height()
	var x0 := int(fx * float(w))
	var y0 := int(fy * float(h))
	var x1 := mini(int((fx + side) * float(w)), w)
	var y1 := mini(int((fy + side) * float(h)), h)
	var da := ia.get_data()
	var db := ib.get_data()
	var total := 0.0
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := (y * w + x) * 3
			total += absf(float(da[i]) - float(db[i])) + absf(float(da[i + 1]) - float(db[i + 1])) + absf(float(da[i + 2]) - float(db[i + 2]))
			n += 3
	return (total / maxf(float(n), 1.0)) / 255.0


## float() of a Variant that may be null or junk. Local because DebugActionsWorld._float_of is a private static
## on that module, not something this probe should reach into.
func _f(v: Variant, fallback: float = 0.0) -> float:
	if v is float or v is int or v is bool:
		return float(v)
	return fallback


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> Image:
	_strip_overlays()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("QA_SHOT_FAIL ", name, " -- no viewport image")
		return null
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		print("QA_SHOT_FAIL ", path)
	return img
