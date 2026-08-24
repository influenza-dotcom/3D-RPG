extends Node
## Colour Depth QA harness — boots the REAL game, walks Options -> Video -> Colour Depth through every row,
## and for each one captures the frame AND COUNTS THE DISTINCT COLOURS IN IT.
##
## WHY THIS EXISTS. `--headless` runs a dummy rasterizer and NEVER compiles a .gdshader: post_process.gdshader
## could have a hard syntax error and every GUT test over it would still pass. So the suite can pin the source
## text and the mode table, and nothing more — whether the GPU actually quantises anything is not a question a
## headless run is able to ask. This harness asks it, and unlike most "look" QA it does not need an eye to
## answer: a quantiser has an arithmetic promise (15-bit = at most 32768 distinct colours), so counting the
## colours in the captured frame either confirms it or does not. The PNGs are for the eye; the counts are the test.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/color_depth_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://qa_shots. Prints one QA_DEPTH line per depth and quits non-zero if
## any depth produced more colours than its own cap, or if the list ever got FINER as it went coarser.
##
## WHAT IT NEUTRALISES, AND WHY EACH ONE MATTERS TO THE COUNT:
##  - FILM GRAIN is added AFTER the quantiser (stage 5, over the finished image) and is per-pixel noise, so with
##    grain on, a 3-bit frame still reports tens of thousands of colours. Zeroed, or this measures nothing.
##  - The HUD draws on the same CanvasLayer but ABOVE the post-process ColorRect, so its labels and minimap are
##    NOT quantised. Every overlay is hidden and only the post-process layer restored.
##  - CONTRAST / COLORBLIND are pushed live from the player's own settings.cfg and both remap colours after the
##    quantiser. Forced neutral IN MEMORY (never through a setter — see below).
##
## ⭐ NEVER `Settings.set_*` FROM A TOOL. Every setter calls save_settings(), which rewrites the player's real
## user://settings.cfg — a QA run that left someone's game at 3-bit would be this project's own documented
## __perf_probe trap repeating. Everything here poked through `.set()` is in-memory only.
##
## Driver-copy pattern, copied from flashlight_qa_shots.gd: this scene is the boot scene, but the run switches
## current_scene to game.tscn (change_scene_to_file frees the current scene), so _ready re-attaches a COPY of
## this script on a bare Node parented to root, which survives the scene change and drives.

const SettingsScript := preload("res://managers/Settings.gd")

var _dir := "user://qa_shots"
var _post_material: ShaderMaterial = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "ColorDepthQaDriver"
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
	await _frames(150)   # level loads, ps1 applier walks, nav bakes, sky title fades
	_strip_overlays()
	if not _restore_post_process():
		print("QA_FAIL no post-process CanvasLayer — there is nothing to measure")
		get_tree().quit(1)
		return

	# Neutralise everything that would add colours after the quantiser (see the header).
	Settings.set(&"contrast", 1.0)
	Settings.set(&"colorblind_mode", 0)
	var authored_grain: Variant = _post_material.get_shader_parameter("grain_amount")
	_post_material.set_shader_parameter("grain_amount", 0.0)
	await _frames(5)
	print("QA_SETUP grain %s -> 0 for the measurement, contrast 1.0, colorblind 0, HUD hidden, post-process ON"
			% str(authored_grain))
	print("QA_SETUP canvas=", get_viewport().get_texture().get_size(), " (the low-res retro canvas, not the window)")

	var failures := 0
	var previous_count := -1
	var previous_label := ""
	for mode in range(SettingsScript.COLOR_QUANTIZE_LEVELS.size()):
		var levels: Vector3 = SettingsScript.color_quantize_levels(mode)
		var cap := int(SettingsScript.color_quantize_color_count(mode))
		# The FIELD, never the setter: a setter here would persist the depth into the player's settings.cfg.
		Settings.set(&"color_quantization", mode)
		# Two frames, not one: player.gd pushes the uniform from _physics_process, so the frame drawn in the
		# same tick the field changed can still be the OLD depth. A one-frame wait here would silently measure
		# the previous row and report every depth shifted by one.
		await _frames(6)
		var img: Image = await _shot("depth_%d" % mode)
		if img == null:
			failures += 1
			continue
		var count := _distinct_colors(img)
		var verdict := "ok"
		if cap > 0 and count > cap:
			verdict = "OVER CAP"
			failures += 1
		elif previous_count >= 0 and cap > 0 and count > previous_count:
			# Only compared between REAL depths; the index-0 sentinel is the material's authored 16 steps,
			# which is coarser than 24-bit and would fire this on the very first step.
			verdict = "COARSER STEP GOT FINER (vs %s)" % previous_label
			failures += 1
		print("QA_DEPTH %d  levels=(%d,%d,%d)  cap=%s  measured=%d distinct colours  %s" % [
			mode, int(levels.x), int(levels.y), int(levels.z),
			"authored" if cap == 0 else str(cap), count, verdict])
		if cap > 0:
			previous_count = count
			previous_label = "depth %d" % mode

	# One A/B on the PS1 row, because the quantiser and the dither only make sense as a pair: the same 32768
	# colours look like bands without the Bayer threshold and like a gradient with it. Same depth, same frame,
	# so the only difference in the two PNGs is the dither.
	Settings.set(&"color_quantization", 3)
	Settings.set(&"dither_strength", 1.0)
	await _frames(6)
	var with_dither: Image = await _shot("ab_15bit_dither_on")
	Settings.set(&"dither_strength", 0.0)
	await _frames(6)
	var without_dither: Image = await _shot("ab_15bit_dither_off")
	if with_dither != null and without_dither != null:
		print("QA_AB 15-bit dither ON = %d distinct colours, OFF = %d — ON should be HIGHER (the threshold mixes two grid levels per gradient; OFF snaps every pixel in a band to one)"
				% [_distinct_colors(with_dither), _distinct_colors(without_dither)])

	_post_material.set_shader_parameter("grain_amount", authored_grain)
	print("QA_DONE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## How many DISTINCT RGB triples the frame contains — the whole point of the harness.
##
## Converted to RGB8 and walked as raw bytes rather than get_pixel()'d: the canvas is 792x444 = 351,648 pixels,
## and a per-pixel Color allocation over that is slow enough to be worth avoiding in a loop that runs eleven
## times. Alpha is dropped deliberately — the post-process writes COLOR.a = 1.0 for every fragment, so it
## carries no information and would only pad the key.
func _distinct_colors(img: Image) -> int:
	var rgb: Image = img.duplicate()
	rgb.convert(Image.FORMAT_RGB8)
	var data := rgb.get_data()
	var seen := {}
	var i := 0
	var n := data.size()
	while i + 2 < n:
		seen[(int(data[i]) << 16) | (int(data[i + 1]) << 8) | int(data[i + 2])] = true
		i += 3
	return seen.size()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Capture the exact retro canvas (the root viewport IS the 792x444 low-res image; the window merely
## nearest-upscales it), save it, and hand the Image back so the caller can count it without a second grab.
func _shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("QA_SHOT_FAIL ", name, " — no viewport image")
		return null
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
	return img


## Hide everything painted OVER the 3D frame — the boot sky title, the HUD, the debug tickers. The HUD matters
## here for a specific reason: it is on the SAME CanvasLayer as the post-process ColorRect but added after it,
## so it draws on top and is NOT quantised. Left visible, its labels and minimap would contribute their own
## un-quantised colours to every count and the coarse depths would read far richer than they are.
func _strip_overlays() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		elif n.name == "SkyTitle" and n is Node3D:
			(n as Node3D).visible = false
		stack.append_array(n.get_children())


## Turn the POST-PROCESS layer back on and nothing else, and remember its material — this harness measures what
## that shader produces, so without it every shot is a raw grab and every count is meaningless. Found by walking
## for the shader rather than by node name, so renaming the HUD cannot silently turn the measurement off.
func _restore_post_process() -> bool:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var mat := (n as CanvasItem).material as ShaderMaterial
			if mat != null and mat.shader != null and String(mat.shader.resource_path).contains("post_process"):
				_post_material = mat
				var layer: Node = n
				while layer != null and not (layer is CanvasLayer):
					layer = layer.get_parent()
				if layer != null:
					(layer as CanvasLayer).visible = true
					return true
		stack.append_array(n.get_children())
	return false
