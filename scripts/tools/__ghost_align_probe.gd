extends Node
## QA probe (2026-08-20) for "the ghosting effect is misaligned with the ui" -- CONFIRMED, then FIXED, and this
## is now the regression harness for the seat that fixed it. Windowed only.
##
## WHAT WAS WRONG. `HudGhost`'s display rect shipped at `z_index -1` on the HUD CanvasLayer. The post-process
## ColorRect that carries the game's look is a SIBLING at z 0, and z -1 draws first -- so the ghost was INSIDE
## the screen texture that shader fetches, while every live readout (z 0..2, added later) draws over that
## shader's output and is never sampled by it. Harmless while the shader was per-pixel. Then it grew
## `lens_barrel`, a radial BARREL WARP of the fetch, on by default at 0.12: the echo was bent by a world lens
## its own source never sees, and stood clear of its readout with the camera dead still.
##
## THE MEASUREMENT. Adjacent A/B with the HUD ON and the world frozen: shoot the frame at `hud_ghost_scale` 0,
## then at 1, and difference them. That difference IS the ghost. At rest the drag offset is zero, so a correct
## ghost hides exactly behind the live HUD and the two frames nearly match -- hud_ghost_qa_shots.gd's shot 02
## promise, as a number. Sweep `lens_barrel_amount` at BOTH SEATS and watch which one moves.
##
##   OLD seat (z -1)            band 0.00077 -> 0.00258 -> 0.00338 -> 0.00420   (3.4x, 4.4x, 5.5x)
##   NEW seat (after the pass)  band 0.00077 -> 0.00077 -> 0.00078 -> 0.00079   (flat)
##
## ⭐ THREE TRAPS THIS FILE WALKED INTO, ALL WORTH KEEPING:
##   1. READ THE MID-RADIUS BAND, NOT A CORNER. A corner-pinned barrel warp moves nothing at the centre and
##      nothing at the corner, peaking near r2n = 1/3. Gating on the top-right minimap reported a real 5.5x
##      displacement as "held" -- the same trap __lens_probe.gd already documents, walked into anyway.
##   2. THE SkyTitle KEEPS FADING THROUGH `Engine.time_scale = 0`, and it is the size of the screen: it put
##      ~20k changed pixels into differences that are supposed to contain nothing but the ghost. _quiet_world.
##   3. MEASURE BOTH SEATS IN ONE RUN. A number remembered from a run before the change is the drift trap;
##      moving the seat mid-run means anything still drifting drifts under both readings.
##
## The HUD must stay VISIBLE, so this must NOT borrow __lens_probe's `_strip_overlays` (`hud off`) -- that
## hides the very thing being measured.
## NEVER `Settings.set_*()`: every setter calls save_settings() and rewrites the developer's real
## user://settings.cfg (the documented __perf_probe trap). Fields are written directly and restored at the end.
##
## Run windowed from the project root (NOT --headless -- the GPU must compile and run the shaders):
##   godot --path . res://scripts/tools/__ghost_align_probe.tscn -- --shots-dir="C:/some/dir"

const GroupsScript := preload("res://scripts/world/groups.gd")

var _dir := "user://qa_shots/ghost_align"
var _post: ShaderMaterial = null
var _post_rect: CanvasItem = null
var _ui: CanvasLayer = null
var _fail := 0
var _grain: Variant = null
var _dither := 0.0
var _world_ghost_scale := 1.0
var _ghost_scale := 1.0
var _barrel := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "GhostAlignDriver"
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
	await _frames(200)

	var player := GroupsScript.human_player(get_tree())
	if not is_instance_valid(player):
		print("QA_FAIL no human player after 200 frames")
		get_tree().quit(1)
		return
	if not _find_post():
		print("QA_FAIL no post-process material found")
		get_tree().quit(1)
		return

	# --- 1. THE STRUCTURE, before a single pixel is measured ------------------------------------------------
	# Draw order inside one canvas is z_index first, then child index. Print it and let the ordering speak.
	print("QA_TREE HUD layer children in DRAW order (z, index, name, visibility_layer):")
	var kids: Array = []
	for c in _ui.get_children():
		if c is CanvasItem:
			kids.append(c)
	kids.sort_custom(_draw_order)
	for c in kids:
		var mat := (c as CanvasItem).material as ShaderMaterial
		var tag := ""
		if mat != null and mat.shader != null:
			tag = "  shader=" + String(mat.shader.resource_path).get_file()
		print("QA_TREE   z=%+d  i=%d  %s  vis_layer=%d%s" % [
			(c as CanvasItem).z_index, c.get_index(), c.name, (c as CanvasItem).visibility_layer, tag])

	var ghost_z := 999
	var post_z := 999
	var ghost_i := -1
	var post_i := -1
	for c in kids:
		if c.name == "HudGhost":
			ghost_z = (c as CanvasItem).z_index
			ghost_i = c.get_index()
		elif (c as CanvasItem).material == _post:
			post_z = (c as CanvasItem).z_index
			post_i = c.get_index()
	var under := ghost_z < post_z or (ghost_z == post_z and ghost_i < post_i)
	print("QA_TREE ghost(z=%d,i=%d) vs post-process(z=%d,i=%d) -> the ghost draws %s" % [
		ghost_z, ghost_i, post_z, post_i,
		"BEFORE it (INSIDE the screen texture the lens bends)" if under else "AFTER it (outside the shader)"])

	# --- 2. Quiet the frame so the A/B means something ------------------------------------------------------
	_grain = _post.get_shader_parameter("grain_amount")
	_post.set_shader_parameter("grain_amount", 0.0)
	_dither = float(Settings.get(&"dither_strength"))
	Settings.set(&"dither_strength", 0.0)
	_world_ghost_scale = float(Settings.get(&"world_ghost_scale"))
	Settings.set(&"world_ghost_scale", 0.0)   # the OTHER accumulator would show up in every difference
	_ghost_scale = float(Settings.get(&"hud_ghost_scale"))
	_barrel = _f(GameSettings.camera.get(&"lens_barrel_amount"))
	print("QA_SETUP authored lens_barrel_amount=%.3f  LensCurve=%.2f  hud_ghost_strength=%.2f  hud_curve_amount=%.3f" % [
		_barrel, _f(Settings.get(&"lens_curve"), 1.0), _f(GameSettings.hud.get(&"hud_ghost_strength")),
		_f(GameSettings.hud.get(&"hud_curve_amount"))])
	Engine.time_scale = 0.0
	await _frames(10)

	# --- 3. The sweep, at BOTH SEATS, in this one frozen run -------------------------------------------------
	# ⭐ THE FIX IS A SEAT, SO THE PROBE MOVES THE SEAT. Comparing this run against a remembered number from a
	# run before the change is exactly the drift trap __lens_probe documents -- and it bit here first time out:
	# the level-intro SkyTitle keeps fading THROUGH Engine.time_scale = 0, which put ~20k changed pixels into
	# every difference taken while it happened to be fading fastest. _quiet_world kills it, and measuring both
	# seats inside one run means anything still drifting drifts under both of them.
	var display := _ui.get_node_or_null(^"HudGhost") as CanvasItem
	if display == null:
		print("QA_FAIL no HudGhost display rect on the HUD layer -- the effect did not build")
		_fail += 1
	for seat: String in ["OLD z_index -1 (below the post-process pass)", "NEW index after the pass"]:
		var old_seat: bool = seat.begins_with("OLD")
		var base := 0.0
		var base_lit := 0
		for k in [0.0, 0.06, 0.12, 0.24]:
			GameSettings.camera.set(&"lens_barrel_amount", k)
			_seat(display, old_seat)
			await _frames(8)
			Settings.set(&"hud_ghost_scale", 0.0)
			await _frames(14)   # the accumulator parks and the display hides
			var tag := "%s_lens_%.2f" % ["old" if old_seat else "new", k]
			var off: Image = await _shot(tag + "_a_ghost_off")
			Settings.set(&"hud_ghost_scale", 1.0)
			_seat(display, old_seat)   # poll() re-shows the rect; the seat itself survives, but re-assert it
			await _frames(14)          # CLEAR_MODE_ONCE, then the buffer saturates on the standing-still HUD
			var on: Image = await _shot(tag + "_b_ghost_on")
			var whole := _diff(off, on, 0.0, 0.0, 1.0, 1.0)
			# ⭐ READ THE MID-RADIUS BAND, NOT A CORNER. A corner-pinned barrel warp moves NOTHING at the
			# centre and NOTHING at the corner (the bend is divided by its own value at the corner), peaking
			# around r2n = 1/3 -- the trap __lens_probe already documents, which this file then walked into by
			# gating on the top-right minimap and reporting a real 5.6x displacement as "held". The bottom-left
			# instrument cluster straddles that peak band, so it is the metric with teeth; the minimap is kept
			# beside it as the PINNED control, and its flatness under a growing lens is the pinning working.
			var band := _diff(off, on, 0.0, 0.72, 0.34, 0.28)     # bottom-left HP / stamina / ammo cluster
			var pinned := _diff(off, on, 0.82, 0.0, 0.18, 0.28)   # top-right map, hard against the pinned corner
			var lit := _lit(off, on, 6)
			print("QA_GHOST [%s] lens %.2f -> ghost visible AT REST: whole %.5f | mid-radius band %.5f | pinned corner %.5f | %d px over 6/255" % [
				seat, k, whole, band, pinned, lit])
			# THE GATE. A ghost that lives in HUD space does not care what the world lens is doing, so every
			# number must match the flat-lens baseline. That baseline is NOT zero and is not supposed to be:
			# the ghost sits behind readouts that are only partly opaque, so ghost-on and ghost-off differ
			# wherever the HUD is see-through even when the two images sit perfectly on top of each other.
			# What says "misaligned" is the number GROWING with k -- ghost energy landing where no readout is.
			if k == 0.0:
				base = band
				base_lit = lit
				print("QA_BASE [%s] flat lens: band %.5f, %d lit px -- the aligned-ghost reading" % [seat, band, lit])
			elif band > base * 1.5 + 0.0004:
				print("QA_MOVED [%s] lens %.2f MOVES THE GHOST: band %.5f vs %.5f flat (%.1fx), %d lit px vs %d" % [
					seat, k, band, base, band / maxf(base, 0.00001), lit, base_lit])
				if not old_seat:
					print("QA_FAIL the shipped seat still lets the world lens drag the HUD echo off its readouts")
					_fail += 1
			else:
				print("QA_HELD [%s] lens %.2f leaves the ghost on its readouts (band %.5f vs %.5f flat, %d lit px vs %d)" % [
					seat, k, band, base, lit, base_lit])
				if old_seat and k >= 0.12:
					print("QA_FAIL the OLD seat did NOT move the ghost at lens %.2f -- the diagnosis this fix rests on does not reproduce" % k)
					_fail += 1

	GameSettings.camera.set(&"lens_barrel_amount", _barrel)
	_seat(display, false)
	await _frames(6)
	# One evidence shot at the SHIPPED lens, overdriven only in STRENGTH so the displacement is unmistakable in
	# a still image (the dither harness's lesson: a correct subtle effect needs an exaggerated shot to read).
	var authored_strength := _f(GameSettings.hud.get(&"hud_ghost_strength"))
	GameSettings.hud.set(&"hud_ghost_strength", 1.0)
	await _frames(16)
	var _e: Image = await _shot("evidence_shipped_lens_overdriven_ghost")
	GameSettings.hud.set(&"hud_ghost_strength", authored_strength)

	_restore()
	print("QA_DONE failures=%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## Put the ghost's display rect at the seat under test. OLD is what shipped: `z_index -1`, which draws before
## the post-process rect whatever its child index is. NEW is the fix: z 0, immediately after that rect.
func _seat(display: CanvasItem, old_seat: bool) -> void:
	if display == null:
		return
	if old_seat:
		display.z_index = -1
		_ui.move_child(display, 0)
	else:
		display.z_index = 0
		_ui.move_child(display, _post_rect.get_index() + 1)


## Silence everything that keeps CHANGING while the world is nominally frozen, without touching the HUD (which
## is the thing being measured, so `hud off` is not available here).
## ⭐ THE SkyTitle KEEPS FADING THROUGH Engine.time_scale = 0 and it is the size of the screen -- it put ~20k
## changed pixels into a difference that is supposed to contain nothing but the ghost. By CLASS, never by node
## name (the name test is the documented miss in color_depth_qa_shots / flashlight_qa_shots).
func _quiet_world() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SkyTitle:
			(n as Node3D).visible = false
		elif n is CanvasLayer and n != _ui:
			(n as CanvasLayer).visible = false   # the debug ticker and any other overlay
		stack.append_array(n.get_children())


func _draw_order(a: CanvasItem, b: CanvasItem) -> bool:
	if a.z_index != b.z_index:
		return a.z_index < b.z_index
	return a.get_index() < b.get_index()


func _restore() -> void:
	Engine.time_scale = 1.0
	if _post != null and _grain != null:
		_post.set_shader_parameter("grain_amount", _grain)
	Settings.set(&"dither_strength", _dither)
	Settings.set(&"world_ghost_scale", _world_ghost_scale)
	Settings.set(&"hud_ghost_scale", _ghost_scale)
	GameSettings.camera.set(&"lens_barrel_amount", _barrel)


## The post-process material, found by SHADER PATH (never by node name), plus the CanvasLayer carrying it --
## which is the player's HUD layer, the one every element in question shares.
func _find_post() -> bool:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var mat := (n as CanvasItem).material as ShaderMaterial
			if mat != null and mat.shader != null and String(mat.shader.resource_path).contains("post_process"):
				var layer: Node = n
				while layer != null and not (layer is CanvasLayer):
					layer = layer.get_parent()
				if layer != null:
					_post = mat
					_post_rect = n as CanvasItem
					_ui = layer as CanvasLayer
					return true
		stack.append_array(n.get_children())
	return false


## Mean absolute RGB difference over a rect given as fractions of the frame.
func _diff(a: Image, b: Image, fx: float, fy: float, fw: float, fh: float) -> float:
	if a == null or b == null:
		return 0.0
	var ia: Image = a.duplicate()
	var ib: Image = b.duplicate()
	ia.convert(Image.FORMAT_RGB8)
	ib.convert(Image.FORMAT_RGB8)
	var w := ia.get_width()
	var h := ia.get_height()
	var da := ia.get_data()
	var db := ib.get_data()
	var total := 0.0
	var n := 0
	for y in range(int(fy * float(h)), mini(int((fy + fh) * float(h)), h)):
		for x in range(int(fx * float(w)), mini(int((fx + fw) * float(w)), w)):
			var i := (y * w + x) * 3
			total += absf(float(da[i]) - float(db[i]))
			total += absf(float(da[i + 1]) - float(db[i + 1]))
			total += absf(float(da[i + 2]) - float(db[i + 2]))
			n += 3
	return (total / maxf(float(n), 1.0)) / 255.0


## How many pixels differ by more than `thresh` on any channel -- the "can a player see it" count, which a mean
## over a mostly-empty frame hides.
func _lit(a: Image, b: Image, thresh: int) -> int:
	if a == null or b == null:
		return 0
	var ia: Image = a.duplicate()
	var ib: Image = b.duplicate()
	ia.convert(Image.FORMAT_RGB8)
	ib.convert(Image.FORMAT_RGB8)
	var w := ia.get_width()
	var h := ia.get_height()
	var da := ia.get_data()
	var db := ib.get_data()
	var n := 0
	for y in h:
		for x in w:
			var i := (y * w + x) * 3
			if absi(int(da[i]) - int(db[i])) > thresh \
					or absi(int(da[i + 1]) - int(db[i + 1])) > thresh \
					or absi(int(da[i + 2]) - int(db[i + 2])) > thresh:
				n += 1
	return n


func _f(v: Variant, fallback: float = 0.0) -> float:
	if v is float or v is int or v is bool:
		return float(v)
	return fallback


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> Image:
	_quiet_world()   # re-asserted before EVERY shot: the sky title re-shows itself the same way the HUD does
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("QA_SHOT_FAIL ", name)
		return null
	img.save_png(ProjectSettings.globalize_path(_dir.path_join(name + ".png")))
	return img
