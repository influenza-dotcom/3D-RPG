extends Node
## QA probe (2026-08-24) for "remove the ghosting on the cursor/stamina bar, make the stamina bar more
## transparent". WINDOWED ONLY — headless never compiles the ghost's canvas shaders, so a headless run would
## photograph a HUD with no effect on it at all and call every shot below a pass.
##
## hud_ghost_qa_shots.gd already covers the CROSSHAIR half of that ask (its 03/05/06 reticle crops go from a
## doubled dot to one crisp dot once the aim cluster is excluded). It cannot cover the RING half: the shipped
## ring is INVISIBLE while the pool is full (stamina_ring_idle_alpha 0) and a QA run that never sprints never
## draws it. So this file pins the pool part-drained and shoots the annulus itself.
##
## WHAT IT ANSWERS
##   1. Does the ring still trail? (shot 01 — the ghost OVERDRIVEN and mid-turn, the only condition under
##      which a still-captured ring would be unmistakable. A clean half-ring there is the pass.)
##   2. Is the ring actually more transparent? (shots 02/03 plus the measured block — the SAME frozen frame
##      at the old 0.6 and the shipped 0.4, differenced against a ring-alpha-0 baseline taken on an adjacent
##      frame. The ratio of those two deltas is the alpha change as a NUMBER, ~0.67, so "looks fainter" does
##      not have to be taken on trust.)
##
## ⭐ THE BASELINE IS `stamina_ring_alpha = 0`, NOT "let the pool refill". A full pool hides the ring through
## the idle FADE, and that fade is eased in _process off `delta` — under the `Engine.time_scale = 0` freeze
## these A/B pairs need, delta is 0 and the ease never runs, so refilling would have left the ring lit.
## Zeroing the knob is the only way to take the ring out of a FROZEN frame.
##
## ⭐ NEVER `Settings.set_*()` — every setter calls save_settings() and rewrites the developer's real
## user://settings.cfg (the documented __perf_probe trap). Fields are written directly and restored at the end.
##
## Run windowed from the project root:
##   godot --path . res://scripts/tools/__stamina_ring_probe.tscn -- --shots-dir="C:/some/dir"

const TURN_RATE := 2.2
const FILL := 0.55  ## pool fraction to pin: a half-ring is the most legible amount of arc to judge

var _dir := "user://qa_shots/stamina_ring"
var _player: Node3D = null
var _hud: Resource = null
var _saved: Dictionary = {}
var _saved_scale: float = 1.0
var _saved_world: float = 1.0

const KEYS: Array[StringName] = [&"stamina_ring_alpha", &"hud_ghost_strength", &"hud_ghost_tau",
		&"hud_ghost_drag_max"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Driver-copy pattern (hud_ghost_qa_shots / minimap_qa_shots): this scene is the boot scene and the run
	# frees it by switching to game.tscn, so a COPY of this script on a bare root child drives the rest.
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "StaminaRingProbeDriver"
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
	await _frames(150)

	_player = Groups.human_player(get_tree())
	if _player == null:
		print("QA_FAIL no Player in the tree")
		get_tree().quit(1)
		return
	_hud = GameSettings.hud
	for k in KEYS:
		_saved[k] = _hud.get(k)
	_saved_scale = Settings.hud_ghost_scale
	_saved_world = Settings.world_ghost_scale
	Settings.world_ghost_scale = 0.0  # judged on the HUD alone
	# The reticle — and therefore the ring's per-frame centre stamp — only exists with a weapon drawn.
	if _player.get("weapon_system") != null and _player.weapon_system.attack != null:
		_player.weapon_system.attack.set_holstered(false)
	await _frames(20)
	var ring := _find_ring()
	var cross := _find_crosshair()
	print("QA_LAYERS ring=", (ring.visibility_layer if ring != null else -1),
			" crosshair=", (cross.visibility_layer if cross != null else -1),
			"  (1 = captured by the ghost, 2 = window only / excluded)")

	# ---- 1. THE GHOST MUST NOT REACH THE RING ---------------------------------------------------------
	# Overdriven on purpose: at the shipped 0.32 / 0.13 / 3 px a correct exclusion and a broken one both read
	# roughly clean in a still. Crank it to where a captured ring would smear unmistakably, then turn.
	Settings.hud_ghost_scale = 1.0
	_hud.set(&"hud_ghost_strength", 0.85)
	_hud.set(&"hud_ghost_tau", 0.32)
	_hud.set(&"hud_ghost_drag_max", 11.0)
	await _turn(26)
	await _shot("01_ring_ghost_overdriven_turning")

	# ---- 2. THE TRANSPARENCY A/B ----------------------------------------------------------------------
	# Ghost off, film grain off, world frozen, so the ONLY difference between these frames is the knob.
	# ⭐GRAIN IS NOT OPTIONAL HERE. First run of this probe left it on and the CONTROL pair (two identical
	# baseline frames) differed MORE than the ring itself did — per-frame noise over the whole crop swamps a
	# 2 px arc, and the measurement said ratio 2.25 where the truth is 0.67. See hud_ghost_qa_shots._set_grain.
	Settings.hud_ghost_scale = 0.0
	var grain := _set_grain(0.0)
	await _frames(12)
	Engine.time_scale = 0.0
	await _frames(4)
	var base := await _shot("04_ring_alpha_000_baseline", 0.0)
	var old := await _shot("02_ring_alpha_060_before", 0.6)
	var base_b := await _shot("04b_ring_alpha_000_control", 0.0)
	var fresh := await _shot("03_ring_alpha_040_shipped", 0.4)
	Engine.time_scale = 1.0
	_set_grain(grain)

	# ⭐MEASURE ON THE RING'S OWN FOOTPRINT, NOT THE WHOLE CROP. The arc is 2 px of an 80x60 region, so a
	# mean over the crop divides the signal by ~100 and lands in the noise whatever the alpha is. The
	# footprint is "every pixel the 0.6 ring actually changed"; both readings are then taken over exactly
	# those pixels, and the control pair is the same statistic with no ring involved at all.
	var mask := _footprint(base, old)
	var d_old := _delta(base, old, mask)
	var d_new := _delta(base, fresh, mask)
	var d_ctl := _delta(base, base_b, mask)
	print("QA_MEASURE footprint_px=%d ring_at_0.60=%.4f ring_at_0.40=%.4f control=%.4f"
			% [mask.size(), d_old, d_new, d_ctl])
	print("QA_MEASURE ratio=%.3f (expect ~0.667 = 0.40/0.60; the control must be a small fraction of either)"
			% (d_new / maxf(d_old, 0.00001)))
	# The shape, amplified 8x, so the footprint can be SEEN to be the ring and not some unrelated churn.
	_save(_zoom(_amplify(base, old)), "05_diff_at_0.60_x8")
	_save(_zoom(_amplify(base, fresh)), "06_diff_at_0.40_x8")

	for k in KEYS:
		_hud.set(k, _saved[k])
	Settings.hud_ghost_scale = _saved_scale
	Settings.world_ghost_scale = _saved_world
	await _frames(4)
	print("QA_DONE")
	get_tree().quit(0)


## Pin the pool part-drained, through the raw `stamina` alias, EVERY frame the probe is live — regen would
## otherwise refill it between shots and the ring would fade back out mid-run.
func _pin_pool() -> void:
	if is_instance_valid(_player) and _player.has_method(&"stamina_max"):
		_player.stamina = FILL * float(_player.call(&"stamina_max"))


func _find_ring() -> CanvasItem:
	var ui: Node = _player.get(&"ui") as Node
	if ui == null:
		return null
	for c in ui.get_children():
		var s: Script = c.get_script() as Script
		if s != null and s.resource_path.ends_with("stamina_ring.gd"):
			return c as CanvasItem
	return null


func _find_crosshair() -> CanvasItem:
	var ui: Node = _player.get(&"ui") as Node
	return (ui.get(&"crosshair") as CanvasItem) if ui != null else null


func _turn(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		_pin_pool()
		if is_instance_valid(_player):
			_player.rotation.y += TURN_RATE * get_process_delta_time()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		_pin_pool()


## Shoot the full frame plus a 6x crop of the annulus (the ring lives at radius 14 around screen centre).
## `alpha` >= 0 stamps the knob first; < 0 leaves it alone. Returns the RAW crop so the caller can difference
## two of them.
func _shot(shot_name: String, alpha: float = -1.0) -> Image:
	if alpha >= 0.0:
		_hud.set(&"stamina_ring_alpha", alpha)
	await get_tree().process_frame
	_pin_pool()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	_save(img, shot_name)
	var size := img.get_size()
	var region := img.get_region(Rect2i(size.x / 2 - 40, size.y / 2 - 30, 80, 60))
	_save(_zoom(region), shot_name + "_ring")
	return region


## Mean per-pixel RGB distance between two crops over `mask` (all pixels when empty), 0..1. ADJACENT frames
## only — a stored baseline drifts (the __ghost_align_probe lesson).
func _delta(a: Image, b: Image, mask: Array[Vector2i] = []) -> float:
	var pts := mask
	if pts.is_empty():
		for y in a.get_height():
			for x in a.get_width():
				pts.append(Vector2i(x, y))
	var total := 0.0
	for p in pts:
		var ca := a.get_pixel(p.x, p.y)
		var cb := b.get_pixel(p.x, p.y)
		total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
	return total / maxf(float(pts.size()), 1.0)


## Every pixel the ring actually paints, found from the reference (alpha 0.6) pair rather than from the
## ring's geometry — so the mask can never claim coverage the renderer did not produce.
func _footprint(base: Image, lit: Image, threshold: float = 0.06) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in base.get_height():
		for x in base.get_width():
			var ca := base.get_pixel(x, y)
			var cb := lit.get_pixel(x, y)
			if (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 >= threshold:
				out.append(Vector2i(x, y))
	return out


## The difference between two crops, multiplied 8x into visible range — the shape of what changed.
func _amplify(a: Image, b: Image, gain: float = 8.0) -> Image:
	var out := Image.create_empty(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			out.set_pixel(x, y, Color(
					minf(absf(ca.r - cb.r) * gain, 1.0),
					minf(absf(ca.g - cb.g) * gain, 1.0),
					minf(absf(ca.b - cb.b) * gain, 1.0)))
	return out


## Film grain is per-frame NOISE and it is the difference between this probe measuring the ring and this
## probe measuring the dither. Walks the post-process material by SHADER NAME (a HUD reshuffle cannot
## silently turn the control off) and returns the previous value so the caller can restore it.
## ⭐`get_shader_parameter` returns Nil for a uniform the material has never had assigned — the shader-side
## default is not in the param cache — so the null branch is load-bearing, not defensive.
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


func _zoom(region: Image) -> Image:
	var out := region.duplicate() as Image
	out.resize(out.get_width() * 6, out.get_height() * 6, Image.INTERPOLATE_NEAREST)
	return out


func _save(img: Image, shot_name: String) -> void:
	var path := _dir.path_join(shot_name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
