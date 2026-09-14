extends Node
## "There's always a transparent X on my crosshair" (2026-09-08) — the acceptance instrument for it.
##
## THE SUSPECT (as it stood BEFORE the 2026-09-08 fix — kept as the record the BEFORE row below measured).
## EffectPrewarmer._warm_2d handed Hitmarker.warm_draw(0.01) one near-invisible paint on the black fade-in so the
## 2D pipeline compiled before the first real hit, and its doc claimed the target restored itself after one drawn
## frame — true of the hurt flash (it writes color.a back) and of the splatter blob (it tweens itself out and
## frees), but a CanvasItem KEEPS ITS DRAW LIST until something calls queue_redraw() again. The hitmarker painted
## its four ticks once and never redrew (_process early-outed while _t <= 0), so the warm X sat on the canvas at
## the crosshair from load until the first landed hit. And the hitmarker IS captured by the HUD ghost
## (hud_ghost.gd's ghost rule — the aim cluster is excluded, the hitmarker is not), so a static source fed the
## accumulator every frame and came back amplified by the phosphor buffer.
## SHIPPED FIX: the warm paint now happens behind the prewarm's own WarmCover, and Hitmarker._draw arms
## _warm_painted so the next processed frame spends it on one clearing redraw — the AFTER row is that state.
##
## WINDOWED ONLY — headless never draws the canvas at all, and the ghost's shaders never compile there.
##   godot --path <abs project> res://scripts/tools/probes/__hitmarker_warm_probe.tscn -- --shots-dir="C:/some/dir"
## ~25 s, quits itself. Read the QA_MEASURE lines and LOOK at 08/09 (the diffs, amplified 8x): an X there is
## the bug, a field of noise is not.
##
## WHAT IT FOUND, AND THE ACCEPTANCE NUMBERS (2026-09-08, 1280x720, the dev's own settings.cfg —
## hud_ghost_scale 1.0). The measurement that matters is `rearmed_ghost_off`: an ADJACENT-frame pair with the
## phosphor out of the way, so world drift cannot get into it.
##   BEFORE  footprint_px=126  rearmed_ghost_off mean=0.00648 peak=0.00784   (09_diff_ghost_off_x8.png is an X)
##           prewarm_X_vs_clean mean=0.05444 — the ghost multiplying that static source by ~8
##   AFTER   footprint_px=0    rearmed_ghost_off mean=0.00000 peak=0.00000   (09_diff_ghost_off_x8.png is black)
## The other rows are 150 frames apart and so carry world drift; `control_world_drift` is their yardstick, and
## once the footprint is empty they fall back to a geometric annulus mask and stop meaning anything on their own.
##
## HOW IT MEASURES (the __stamina_ring_probe lessons, all of them apply here):
##  * Film grain OFF and the world frozen (Engine.time_scale = 0) for every A/B pair — per-frame noise over
##    the crop otherwise swamps four 2 px ticks.
##  * On the ticks' OWN FOOTPRINT (the pixels the X actually changed, derived from the render), never a mean
##    over the whole crop — that divides the signal by ~50 and lands in the noise.
##  * The GHOST decay is eased off `delta`, so it cannot settle under the freeze: every "let the ghost catch
##    up / bleed off" wait below runs UNFROZEN, and the freeze goes back on just for the shot.
##  * Never Settings.set_*() — those setters rewrite the developer's real user://settings.cfg.

const QaShots := preload("res://scripts/tools/probes/qa_shot_helpers.gd")

const CROP := Vector2i(80, 60)   ## the annulus crop: the ticks live ~6-11 px off centre
const SETTLE_FRAMES := 180       ## the whole warm pass (~15 frames) plus the spawn settle
const GHOST_FRAMES := 150        ## unfrozen frames for the phosphor buffer to saturate / bleed off (~2.5 s)

var _dir := "user://qa_shots/hitmarker_warm"
var _player: Node = null
var _hm: CanvasItem = null
var _saved_ghost: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Driver-copy pattern: this scene is the boot scene and the run frees it by switching to game.tscn.
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "HitmarkerWarmProbeDriver"
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
	await _frames(SETTLE_FRAMES)

	_player = Groups.human_player(get_tree())
	if _player == null:
		print("QA_FAIL no Player in the tree")
		get_tree().quit(1)
		return
	_hm = _find_hitmarker()
	if _hm == null:
		print("QA_FAIL no Hitmarker under player.ui")
		get_tree().quit(1)
		return
	_saved_ghost = Settings.hud_ghost_scale
	print("QA_STATE hitmarker visible=", _hm.visible, " visibility_layer=", _hm.visibility_layer,
			" (1 = captured by the HUD ghost, 2 = window only)  hud_ghost_scale=", _saved_ghost,
			"  warm_alpha_left=", _hm.get(&"_warm_alpha"), "  _t=", _hm.get(&"_t"))

	var grain := _set_grain(0.0)
	await _frames(10)

	# ---- 1. AS THE PREWARM LEFT IT, ~3 s after the level loaded ---------------------------------------
	Engine.time_scale = 0.0
	await _frames(4)
	var a := await _shot("01_as_the_prewarm_left_it")
	# The fix, by hand: one redraw with nothing to paint clears the retained draw list.
	_hm.queue_redraw()
	await _frames(3)
	var b := await _shot("02_after_one_forced_redraw")
	# The ghost still holds what it accumulated (its decay is off `delta` and delta is 0 under the freeze),
	# so bleed it off UNFROZEN before the clean reference shot.
	Engine.time_scale = 1.0
	await _frames(GHOST_FRAMES)
	Engine.time_scale = 0.0
	await _frames(4)
	var clean := await _shot("03_clean_reference")
	# World-drift control: the same statistic over the same wait with no X involved at all.
	Engine.time_scale = 1.0
	await _frames(GHOST_FRAMES)
	Engine.time_scale = 0.0
	await _frames(4)
	var ctl := await _shot("04_clean_control")

	# ---- 2. RE-ARM IT: the same one-shot warm, ghost live ---------------------------------------------
	Engine.time_scale = 1.0
	_hm.call(&"warm_draw", 0.01)  # exactly what EffectPrewarmer._warm_2d does (WARM_2D_ALPHA)
	await _frames(GHOST_FRAMES)
	Engine.time_scale = 0.0
	await _frames(4)
	var rearmed := await _shot("05_rearmed_warm_draw_ghost_on")

	# ---- 3. THE SAME THING WITH THE HUD GHOST OFF (how much of it is the phosphor) --------------------
	Engine.time_scale = 1.0
	Settings.hud_ghost_scale = 0.0
	await _frames(30)
	Engine.time_scale = 0.0
	await _frames(4)
	var no_ghost := await _shot("06_rearmed_warm_draw_ghost_off")
	_hm.queue_redraw()
	await _frames(3)
	var no_ghost_clean := await _shot("07_ghost_off_cleared")

	# ---- MEASURE --------------------------------------------------------------------------------------
	# The footprint comes from the ghost-off pair: that one is a pure live-draw difference on adjacent
	# frames, so it can only contain pixels the ticks themselves painted.
	var mask := _footprint(no_ghost_clean, no_ghost, 0.004)
	print("QA_MEASURE footprint_px=%d  (four 2 px ticks ~= 40-130 px; ZERO = the live warm paint never reached a second frame, which is the FIX)" % mask.size())
	if mask.is_empty():
		# Nothing to derive a mask from is the pass condition, not a failure — fall back to the geometry the
		# ticks WOULD occupy so the run still prints a number comparable with the broken one's.
		mask = _annulus(no_ghost_clean, 2.0, 13.0)
		print("QA_MEASURE (empty footprint -> measuring the annulus the ticks would occupy: %d px)" % mask.size())
	print("QA_MEASURE prewarm_X_vs_clean   mean=%.5f peak=%.5f   <- what shipped, ghost live" % _stats(clean, a, mask))
	print("QA_MEASURE after_one_redraw     mean=%.5f peak=%.5f   <- live draw gone, ghost still holding" % _stats(clean, b, mask))
	print("QA_MEASURE rearmed_ghost_on     mean=%.5f peak=%.5f   <- reproduced from a fresh warm_draw" % _stats(clean, rearmed, mask))
	print("QA_MEASURE rearmed_ghost_off    mean=%.5f peak=%.5f   <- the live 0.01 paint alone" % _stats(no_ghost_clean, no_ghost, mask))
	print("QA_MEASURE control_world_drift  mean=%.5f peak=%.5f   <- the noise floor of this instrument" % _stats(clean, ctl, mask))
	_save(_zoom(_amplify(clean, a)), "08_diff_prewarm_x8")
	_save(_zoom(_amplify(no_ghost_clean, no_ghost)), "09_diff_ghost_off_x8")
	_save(_zoom(_amplify(clean, ctl)), "10_diff_control_x8")

	Settings.hud_ghost_scale = _saved_ghost
	Engine.time_scale = 1.0
	_set_grain(grain)
	await _frames(4)
	print("QA_DONE")
	get_tree().quit(0)


func _find_hitmarker() -> CanvasItem:
	var ui: Node = _player.get(&"ui") as Node
	if ui == null:
		return null
	for c in ui.get_children():
		var s: Script = c.get_script() as Script
		if s != null and s.resource_path.ends_with("hitmarker.gd"):
			return c as CanvasItem
	return null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## Full frame + a 6x zoom of the annulus crop; returns the RAW crop for differencing.
func _shot(shot_name: String) -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	_save(img, shot_name)
	@warning_ignore("integer_division")  # a crop is whole pixels
	var region := img.get_region(Rect2i(img.get_size() / 2 - CROP / 2, CROP))
	_save(_zoom(region), shot_name + "_crop")
	return region


## Mean AND peak per-pixel RGB distance over `mask`. The peak is what decides whether a human sees it; the
## mean over four thin ticks understates by design.
func _stats(a: Image, b: Image, mask: Array[Vector2i]) -> Array:
	var total := 0.0
	var peak := 0.0
	for p in mask:
		var ca := a.get_pixel(p.x, p.y)
		var cb := b.get_pixel(p.x, p.y)
		var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
		total += d
		peak = maxf(peak, d)
	return [total / maxf(float(mask.size()), 1.0), peak]


## The ring of pixels the four ticks live in (crop centre, radii in px) — the fallback mask for a run where the
## X is GONE and there is no rendered footprint left to derive one from.
func _annulus(ref: Image, r_min: float, r_max: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := Vector2(ref.get_width(), ref.get_height()) * 0.5
	for y in ref.get_height():
		for x in ref.get_width():
			var d := (Vector2(x, y) + Vector2(0.5, 0.5) - c).length()
			if d >= r_min and d <= r_max:
				out.append(Vector2i(x, y))
	return out


func _footprint(base: Image, lit: Image, threshold: float) -> Array[Vector2i]:
	return QaShots.footprint(base, lit, threshold)


func _amplify(a: Image, b: Image, gain: float = 8.0) -> Image:
	return QaShots.amplify(a, b, gain)


## Film grain is per-frame noise and it is the difference between measuring the ticks and measuring the
## dither. Walks the post-process material by SHADER NAME; returns the previous value for the restore.
func _set_grain(amount: float) -> float:
	return QaShots.set_grain(get_tree().root, amount)


func _zoom(region: Image) -> Image:
	var out := region.duplicate() as Image
	out.resize(out.get_width() * 6, out.get_height() * 6, Image.INTERPOLATE_NEAREST)
	return out


func _save(img: Image, shot_name: String) -> void:
	var path := _dir.path_join(shot_name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
