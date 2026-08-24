extends Node
## HUD-GHOST QA screenshot harness — boots the REAL game, turns the camera at a controlled rate, and saves one
## shot per ghosting variant so the effect can be judged by eye (plus a tight CROP of the reticle and of the
## bottom-left instrument cluster, because the shipped amplitude is deliberately subtle at 1280x720).
##
## WHY THIS EXISTS: ⭐ headless NEVER COMPILES SHADERS, so the two canvas shaders in hud_ghost.gd load clean and
## pass every GUT test even if they are wrong — and no unit test can see a trail regardless. tests/test_hud_ghost.gd
## pins the maths (decay curve, lag, clamp order, the capture/exclude masks); this pins what it LOOKS like.
##
## THE FOUR QUESTIONS IT ANSWERS, in this order:
##   1. Is the HUD unchanged when the effect is OFF? (01 vs the shipped build — must be pixel-identical.)
##   2. Is it invisible while standing still? (02 — "subtle" means the ghost hides exactly behind the live HUD.)
##      ⭐ THAT SHOT IS ALSO THE SEAT ALARM. The display rect must draw AFTER the HUD layer's post-process
##      ColorRect; below it (as `z_index -1` used to put it) the ghost is INPUT to that shader, and the barrel
##      lens in it bends the echo off its readout — 02 stops being clean and nothing else here changes.
##      scripts/tools/__ghost_align_probe.gd measures that seat directly; this shot is how it looks.
##   3. Does it show on the RETICLE, not just on the swaying corner panel? (03 / 05 — the crosshair is welded to
##      screen centre, so only the LATENCY half can put a tail on it. 05 isolates that half.)
##   4. Is the tail a COLOUR GRADIENT rather than a dimmer copy? (03 / 06 — the ramp is keyed on trail AGE,
##      so a decaying tail should shift hue across HudSkin.ghost_gradient regardless of what colour the HUD
##      element it came from is. Compare the red HP bar's trail with the gold money readout's: same hues.)
##   5. Is the VIEW MODEL untouched? (the _viewmodel crop — the gun composites onto the HUD layer, so it is
##      the one thing there that must be opted OUT of the capture; see ViewModelCamera._attach_container.)
##   6. Does the tail actually go to NOTHING? (07 — an 8-bit never-cleared buffer has a decay fixed point, and
##      without the display-side residue floor every place the HUD has been keeps a permanent faint smear.)
##   7. And the WORLD ghost (09-12, scripts/effects/world_ghost.gd — the same persistence applied to the
##      picture): is a still frame IDENTICAL with it on (09 vs 10, measured, with film grain switched off so
##      the numbers mean something), does the world trail on a turn (11), and does the weapon still stay
##      crisp under an overdriven world pass (12 + its _viewmodel crop)?
## 06 is the deliberately-overdriven shot: at the shipped values a CORRECT effect is meant to be hard to see, so
## the exaggerated frame is the one that proves the mechanism is running at all (the dither harness's lesson).
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   & "C:\Users\dalla\bin\godot.cmd" --path . res://scripts/tools/hud_ghost_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://hud_ghost_qa. Prints one QA_SHOT line per capture and quits.
##
## Driver-copy pattern (minimap_qa_shots / flashlight_qa_shots): this scene is the boot scene, but the run
## switches current_scene to game.tscn — which frees the current scene — so _ready re-attaches a COPY of this
## script on a bare Node parented to root, and that copy survives the change and drives the rest.
##
## ⭐ IT MUST NEVER CALL Settings.set_*(): every one of those setters calls save_settings(), and a QA probe has
## already clobbered the user's real settings.cfg once. Fields are written DIRECTLY here and restored at the end.

const TURN_RATE := 2.2      ## rad/s of yaw while "turning" — a brisk look, not a flick
const TURN_FRAMES := 26     ## frames of turning before a turning shot, so the lag has fully built
const SETTLE_FRAMES := 40   ## frames of standing still before a "still" shot, so any tail has expired

var _dir := "user://hud_ghost_qa"
var _player: Node3D = null
var _ghost: Node = null
var _saved: Dictionary = {}
var _world_saved: Dictionary = {}
var _grain_saved: float = 0.05

## Every EffectsSettings knob the world half of this run scribbles on (stashed and restored as a set).
const WORLD_KEYS: Array[StringName] = [&"world_ghost_strength", &"world_ghost_tau", &"world_ghost_dead_zone",
		&"world_ghost_chroma_px", &"world_ghost_chroma_gain"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "HudGhostQaDriver"
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
	await _frames(150)   # level loads, the ps1 applier walks, nav bakes, the sky title fades

	_player = Groups.human_player(get_tree())
	if _player == null:
		print("QA_FAIL no Player in the tree")
		get_tree().quit(1)
		return
	_ghost = _player.find_child("HudGhostDriver", true, false)
	print("QA_GHOST node=", _ghost, " display=", _find_display())
	if _ghost == null:
		print("QA_FAIL the HUD ghost never built — check UI._build_ghost")
		get_tree().quit(1)
		return
	# Draw the weapon so the reticle is actually up (it hides while holstered), and stash every knob this
	# harness is about to scribble on.
	if _player.get("weapon_system") != null and _player.weapon_system.attack != null:
		_player.weapon_system.attack.set_holstered(false)
	_stash()
	await _frames(20)

	# 1. THE CONTROL. Effect fully off: the accumulation pass stops rendering and the display rect hides, so
	#    this frame must be indistinguishable from a build that never had the feature.
	_apply(0.0, {})
	await _still()
	await _shot("01_off_still")

	# 2. SHIPPED, STANDING STILL. The whole "subtle" promise: at rest the lag offset is zero, so the ghost sits
	#    exactly behind the live HUD and 02 should be hard to tell from 01. If the HUD looks BOLDER here, the
	#    display strength is too high (semi-transparent elements build up in the buffer and read through).
	_apply(1.0, {})
	await _still()
	await _shot("02_shipped_still")

	# 3. SHIPPED, MID-TURN. The money shot: corner panel trailing on the sway spring AND the reticle carrying a
	#    tail off the latency offset.
	_apply(1.0, {})
	await _turn(TURN_FRAMES)
	await _shot("03_shipped_turning")

	# 4. PERSISTENCE ONLY (no latency offset). Everything that MOVES still trails; the screen-locked reticle
	#    goes clean. This is the shot that proves the reticle's tail in 03 comes from the lag and nothing else.
	_apply(1.0, {&"hud_ghost_drag_max": 0.0})
	await _turn(TURN_FRAMES)
	await _shot("04_persistence_only_reticle_clean")

	# 5. LATENCY ONLY (persistence collapsed to one frame). A single hard offset copy, no tail — the other half
	#    isolated. Use this pair to re-balance the two if the shipped mix ever reads as double vision.
	_apply(1.0, {&"hud_ghost_tau": 0.008})
	await _turn(TURN_FRAMES)
	await _shot("05_latency_only_hard_offset")

	# 6. OVERDRIVEN. Not a strawman: at the shipped amplitude a CORRECT effect is meant to be nearly invisible,
	#    so this is the frame that proves the pass is running, the capture masks are right, and the excluded
	#    overlays (flashes, arcs, the state post-process rect) really are staying out of the buffer.
	_apply(1.0, {
		&"hud_ghost_strength": 0.85,
		&"hud_ghost_tau": 0.32,
		&"hud_ghost_drag_max": 11.0,
		&"hud_ghost_drag_gain": Vector2(5.0, 4.0),
	})
	await _turn(TURN_FRAMES + 14)
	await _shot("06_overdriven_mechanism_visible")

	# 7. THE RESIDUE CHECK. Straight off the overdriven turn at shipped values, stand still and let it expire.
	#    Any smear still visible here is the 8-bit decay fixed point leaking past residue_floor.
	_apply(1.0, {})
	await _still()
	await _still()
	await _shot("07_after_stop_must_be_clean")

	# 8. SCOPED. The inverting reticle samples the screen, which inside the capture is the HUD-only buffer, so
	#    ui.set_scoped drops the crosshair out of the ghost for the duration. A white/blown disc here means that
	#    opt-out is not firing; a normal scoped reticle with a still-ghosting corner panel is the pass.
	var ui := _find_ui()
	if ui != null and ui.has_method(&"set_scoped"):
		ui.call(&"set_scoped", true)
		await _turn(TURN_FRAMES)
		await _shot("08_scoped_reticle_left_the_capture")
		ui.call(&"set_scoped", false)
	else:
		print("QA_SKIP no UI.set_scoped found")

	# ---- THE WORLD GHOST -----------------------------------------------------------------------------
	# Grain OFF for the whole world phase: it is per-frame noise, and the central claim here ("a still frame
	# is unchanged") is only checkable if two captures of a still scene can match at all.
	_apply(0.0, {})
	_grain_saved = _set_grain(0.0)
	await _still()

	# 9 / 10. THE MEASURED PAIR. Same still scene, world pass off then on. The dead zone exists precisely so
	#    the composite is `now + 0` at rest, so the diff printed after 10 should be a fraction of one 8-bit
	#    step — anything above ~1/255 means the dead zone is too small and a permanent haze is being added.
	_apply_world(1.0, {})
	await _still()
	await _shot("10_world_on_still")
	# THE GAP IS THE MEASUREMENT'S RESOLUTION. This level is ALIVE — animated signage, NPCs, a moving sun — so
	# two captures of "the same" still scene never match, and a 40-frame gap buries a 12% effect under the
	# world's own change. So the pair is taken THREE FRAMES apart (one poll to switch the pass off, two to
	# settle) and the CONTROL below uses the identical gap with the effect off both times. The claim is not
	# "the diff is zero", it is "the diff is the same as the world's own churn over the same three frames".
	_apply_world(0.0, {})
	await _frames(3)
	await _shot("09_world_off_still")
	_diff("10_world_on_still", "09_world_off_still", "world ghost at rest (3-frame gap, on vs off)")
	await _frames(3)
	await _shot("09b_world_off_still_again")
	_diff("09_world_off_still", "09b_world_off_still_again", "CONTROL  same gap, effect off both times ")

	# 11. SHIPPED, MID-TURN. The world drags a short memory of where it was; the weapon does not.
	_apply_world(1.0, {})
	await _turn(TURN_FRAMES)
	await _shot("11_world_shipped_turning")

	# 12. OVERDRIVEN. Same reason as 06: at 12% strength a correct world ghost is meant to be hard to see, so
	#    this is the frame that proves the pass runs at all — and, in its _viewmodel crop, that the gun mask
	#    holds even when the trail is loud enough to smear the whole picture.
	_apply_world(1.0, {
		&"world_ghost_strength": 0.75,
		&"world_ghost_tau": 0.30,
		&"world_ghost_chroma_px": 4.0,
	})
	await _turn(TURN_FRAMES + 14)
	await _shot("12_world_overdriven_weapon_must_stay_crisp")

	_restore()
	print("QA_DONE")
	get_tree().quit(0)


## Snapshot every knob this harness writes, so the run leaves the resource exactly as it found it. (The
## Settings field is written directly and never through its setter — see the header's settings.cfg warning.)
func _stash() -> void:
	var hud: Resource = GameSettings.hud
	for k: StringName in [&"hud_ghost_strength", &"hud_ghost_tau", &"hud_ghost_drag_max",
			&"hud_ghost_drag_gain", &"hud_ghost_drag_response", &"hud_ghost_residue_floor"]:
		_saved[k] = hud.get(k)
	_saved[&"scale"] = Settings.hud_ghost_scale
	var fx: Resource = GameSettings.effects
	for k: StringName in WORLD_KEYS:
		_world_saved[k] = fx.get(k)
	_world_saved[&"scale"] = Settings.world_ghost_scale


func _restore() -> void:
	var hud: Resource = GameSettings.hud
	for k: StringName in _saved.keys():
		if k != &"scale":
			hud.set(k, _saved[k])
	Settings.hud_ghost_scale = _saved[&"scale"]
	var fx: Resource = GameSettings.effects
	for k: StringName in WORLD_KEYS:
		fx.set(k, _world_saved[k])
	Settings.world_ghost_scale = _world_saved[&"scale"]
	_set_grain(_grain_saved)


## Reset the WORLD ghost to its authored values, apply `overrides`, and set its dial — the _apply twin for
## the second half of the run. Kept separate from _apply so the HUD shots (01-08) can hold the world pass at
## zero and be judged on the HUD alone.
func _apply_world(scale: float, overrides: Dictionary) -> void:
	var fx: Resource = GameSettings.effects
	for k: StringName in WORLD_KEYS:
		fx.set(k, _world_saved[k])
	for k: StringName in overrides.keys():
		fx.set(k, overrides[k])
	Settings.world_ghost_scale = scale


## Film grain is per-frame NOISE, so two captures of the same still scene never match pixel for pixel and any
## measured "is it identical at rest" claim is worthless with it on. Walk the post-process material and set
## grain_amount; returns the previous value so _restore can put it back. Found by shader name, not node path,
## so a HUD reshuffle cannot silently turn the control off.
func _set_grain(amount: float) -> float:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var mat := (n as CanvasItem).material as ShaderMaterial
			if mat != null and mat.shader != null and String(mat.shader.resource_path).contains("post_process"):
				var was: Variant = mat.get_shader_parameter(&"grain_amount")
				mat.set_shader_parameter(&"grain_amount", amount)
				return float(was) if was != null else 0.05
		stack.append_array(n.get_children())
	return 0.05


## Mean and max absolute channel difference between two saved shots — the measured half of "identical at
## rest". Eyeballing a 12%-strength full-screen effect on a dithered frame is not evidence.
func _diff(a_name: String, b_name: String, label: String) -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path(_dir.path_join(a_name + ".png")))
	var b := Image.load_from_file(ProjectSettings.globalize_path(_dir.path_join(b_name + ".png")))
	if a == null or b == null:
		print("QA_DIFF_FAIL ", label)
		return
	var total := 0.0
	var worst := 0.0
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var d: Color = a.get_pixel(x, y) - b.get_pixel(x, y)
			var m: float = maxf(maxf(absf(d.r), absf(d.g)), absf(d.b))
			total += m
			worst = maxf(worst, m)
			n += 1
	print("QA_DIFF %s  mean=%.5f (%.2f/255)  max=%.5f (%.1f/255)  over %d px"
			% [label, total / maxf(float(n), 1.0), 255.0 * total / maxf(float(n), 1.0), worst, worst * 255.0, n])


## Reset every knob to its authored value, apply `overrides`, and set the player dial. One entry point so a
## variant can never inherit a leftover from the variant before it (the failure mode where every image in the
## set looks plausible but two of them are the same experiment).
func _apply(scale: float, overrides: Dictionary) -> void:
	var hud: Resource = GameSettings.hud
	for k: StringName in _saved.keys():
		if k != &"scale":
			hud.set(k, _saved[k])
	for k: StringName in overrides.keys():
		hud.set(k, overrides[k])
	Settings.hud_ghost_scale = scale
	Settings.world_ghost_scale = 0.0  # the HUD shots are judged on the HUD alone


## Turn the camera at a fixed rate for `n` frames. Yaw on the body is what the HUD sway spring measures off the
## camera's GLOBAL basis, and the ghost rides that same sample — so this drives both channels honestly rather
## than poking either one's state directly.
func _turn(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(_player):
			_player.rotation.y += TURN_RATE * get_process_delta_time()
	_report()


## Stand still long enough for any tail to expire.
func _still() -> void:
	await _frames(SETTLE_FRAMES)
	_report()


func _report() -> void:
	if _ghost == null:
		return
	var hud: Resource = GameSettings.hud
	print("QA_STATE scale=", Settings.hud_ghost_scale,
			" strength=", hud.get(&"hud_ghost_strength"), " tau=", hud.get(&"hud_ghost_tau"),
			" drag_max=", hud.get(&"hud_ghost_drag_max"),
			" | drag_now=", _ghost.get(&"_drag"), " running=", _ghost.get(&"_running"))


func _find_ui() -> Node:
	if not is_instance_valid(_player):
		return null
	var n: Variant = _player.get(&"ui")
	return n as Node


func _find_display() -> Node:
	var ui := _find_ui()
	return ui.get_node_or_null(^"HudGhost") if ui != null else null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Save the full frame plus two 4x nearest-neighbour crops — the reticle (centre) and the bottom-left
## instrument cluster. At 1280x720 a 3 px canvas offset is ~5 screen px, which is exactly the scale at which a
## full-frame thumbnail hides the entire effect and a crop makes it obvious.
func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	_save(img, shot_name)
	var size := img.get_size()
	var centre := Rect2i(size.x / 2 - 60, size.y / 2 - 45, 120, 90)
	_save(_zoom(img.get_region(centre)), shot_name + "_reticle")
	var corner := Rect2i(8, size.y - 130, 200, 122)
	_save(_zoom(img.get_region(corner)), shot_name + "_cluster")
	# THE VIEW MODEL. The gun pass is composited back through a full-rect SubViewportContainer that lives on
	# the HUD CanvasLayer, so it is the one thing on that layer which LOOKS like HUD to the capture and must
	# not be (ViewModelCamera._attach_container opts it out). Any smear on the weapon in an overdriven,
	# mid-turn frame means that opt-out stopped firing — which no other crop in this set would show.
	var weapon := Rect2i(size.x / 2 - 130, size.y - 200, 260, 195)
	_save(_zoom(img.get_region(weapon).duplicate() as Image), shot_name + "_viewmodel")


func _zoom(region: Image) -> Image:
	var out := region.duplicate() as Image
	out.resize(out.get_width() * 4, out.get_height() * 4, Image.INTERPOLATE_NEAREST)
	return out


func _save(img: Image, shot_name: String) -> void:
	var path := _dir.path_join(shot_name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
