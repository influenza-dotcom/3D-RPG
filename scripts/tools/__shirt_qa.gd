extends Node
## TEMP shirt-creator QA harness — delete once the shirt work settles. Boots the real game windowed, opens
## character creation on the Shirt tab, paints test patterns through the real canvas API, and screenshots the tab
## + the 3D preview from front/side/back. Patterns: (1) the orientation "F" + colour-coded corners, (2) a
## realistic red tee with a white logo (checks the side-face FABRIC colour tracks the drawing). Run (NOT headless):
##   godot --path <proj> res://scripts/tools/__shirt_qa.tscn -- --shots-dir="C:/some/dir"
## Driver-copy pattern borrowed from menu_qa_shots.gd (the boot scene dies on scene change).

var _dir := "user://shirt_qa"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "ShirtQaDriver"
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

	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
	await _frames(10)
	var cc: Control = load("res://scripts/ui/character_creation.gd").new()
	get_tree().root.add_child(cc)
	await _frames(6)
	var tabs := cc.find_children("*", "TabContainer", true, false)
	if tabs.is_empty():
		print("QA_FAIL no TabContainer in character creation")
		_finish()
		return
	var prev: Control = cc.get(&"_shirt_preview")
	if prev != null:
		prev.set(&"auto_rotate", false)  # deterministic shots
	(tabs[0] as TabContainer).current_tab = 2
	await _frames(16)
	var canvas: Control = cc.get(&"_shirt_canvas")
	print("QA_PALETTE chips=", (cc.get(&"_shirt_swatches") as Array).size())

	# Custom colour picker: open the overlay (the spray-can-style wheel), drive a teal, confirm brush + swatch follow.
	var custom: Button = cc.get(&"_shirt_custom_btn")
	if custom != null:
		custom.emit_signal(&"pressed")  # open the overlay
		await _frames(4)
		var wheel: ColorPicker = cc.get(&"_shirt_picker")
		var layer: CanvasLayer = cc.get(&"_shirt_picker_layer")
		if wheel != null:
			wheel.color = Color(0.1, 0.7, 0.65)
			wheel.emit_signal(&"color_changed", wheel.color)  # mimic a wheel drag
		var csb = cc.get(&"_shirt_custom_sb")
		print("QA_CUSTOM overlay_visible=", (layer != null and layer.visible), " brush=", canvas.get(&"paint_color"),
				" swatch=", (csb.bg_color if csb != null else "nil"))
		await _frames(2)
		await _shot("custom_picker_open")
		if wheel != null:
			cc.call(&"_on_shirt_picker_close")
	else:
		print("QA_CUSTOM missing custom swatch button")

	# Front/back: a RED "F" on the front, a BLUE "B" on the back — proves the two sides are independent and each
	# reads correctly on the model. Drive the canvas' side switch + the preview snap directly.
	if canvas != null:
		var res0 := int(canvas.get(&"edit_res"))
		canvas.call(&"set_side", 0)  # SIDE_FRONT
		_blit(canvas, _letter_pattern(res0, "F", Color(0.85, 0.16, 0.16)))
		canvas.call(&"set_side", 1)  # SIDE_BACK
		_blit(canvas, _letter_pattern(res0, "B", Color(0.16, 0.3, 0.85)))
		canvas.call(&"set_side", 0)
	await _frames(8)
	await _shot("fb_editor_front")  # canvas shows the FRONT (red F) + the tool row incl. the "Pick" eyedropper

	# Eyedropper: sample the red "F" pixel and confirm the brush + Custom swatch follow.
	if canvas != null:
		canvas.call(&"set_paint_color", Color.WHITE)
		canvas.call(&"set_tool", 3)  # TOOL_EYEDROP
		canvas.call(&"_eyedrop", Vector2i(10, 10))  # a cell inside the red F spine
		var csb = cc.get(&"_shirt_custom_sb")
		print("QA_EYEDROP brush=", canvas.get(&"paint_color"), " tool=", canvas.get(&"tool"),
				" swatch=", (csb.bg_color if csb != null else "nil"))
		canvas.call(&"set_tool", 0)  # back to PAINT for the later shots
	# Model, front then back.
	await _shot_angle(prev, 0.0, "fb_model_front")
	await _shot_angle(prev, PI, "fb_model_back")

	# Pattern 1: the orientation "F" + corner markers.
	if canvas != null:
		var res := int(canvas.get(&"edit_res"))
		canvas.call(&"load_png", _test_pattern(res).save_png_to_buffer())
		canvas.emit_signal(&"changed")  # load_png marks dirty but doesn't emit; bind like a real stroke would
	await _frames(16)
	await _shot_angle(prev, 0.0, "f_front")
	await _shot_angle(prev, PI * 0.5, "f_side")
	await _shot_angle(prev, PI, "f_back")

	# Pattern 2: a realistic tee — RED fill, white logo. Side faces must come out RED (live fabric colour).
	if canvas != null:
		var res2 := int(canvas.get(&"edit_res"))
		canvas.call(&"load_png", _logo_pattern(res2).save_png_to_buffer())
		canvas.emit_signal(&"changed")
	await _frames(8)
	await _shot_angle(prev, 0.0, "logo_front")
	await _shot_angle(prev, PI * 0.5, "logo_side")
	await _shot_angle(prev, PI * 0.25, "logo_quarter")
	cc.queue_free()
	_finish()

## Rotate the preview turntable to `yaw`, screenshot the whole tab, and save the preview SubViewport too.
func _shot_angle(prev: Control, yaw: float, name: String) -> void:
	if prev != null:
		var root: Node3D = prev.get(&"_char_root")
		if root != null:
			root.rotation = Vector3(0.0, yaw, 0.0)
	await _frames(3)
	await _shot(name)
	if prev != null:
		var vp: SubViewport = prev.get(&"_viewport")
		if vp != null:
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path(_dir.path_join(name + "_preview.png")))

## Orientation test pattern: white tee, big black asymmetric "F", corner squares TL=red TR=green BL=blue BR=yellow.
func _test_pattern(res: int) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var s := res / 32.0
	_draw_f(img, s, Color(0.05, 0.05, 0.05))
	var c := int(maxf(4.0, 5.0 * s))
	_fill_rect_px(img, 0, 0, c, c, Color(0.85, 0.15, 0.15))
	_fill_rect_px(img, res - c, 0, c, c, Color(0.2, 0.7, 0.2))
	_fill_rect_px(img, 0, res - c, c, c, Color(0.2, 0.35, 0.9))
	_fill_rect_px(img, res - c, res - c, c, c, Color(0.95, 0.85, 0.2))
	return img

## Realistic tee: solid red fabric, white "F" logo, NO corner markers — the side-face fabric should read RED.
func _logo_pattern(res: int) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.75, 0.12, 0.12))
	_draw_f(img, res / 32.0, Color(0.95, 0.95, 0.95))
	return img

func _draw_f(img: Image, s: float, col: Color) -> void:
	_fill_rect(img, 9, 5, 3, 22, s, col)   # F spine
	_fill_rect(img, 9, 5, 14, 4, s, col)   # F top bar
	_fill_rect(img, 9, 14, 10, 3, s, col)  # F mid bar

## Push `img` onto the canvas' ACTIVE side buffer and refresh the combined texture (a shortcut for the QA harness;
## the buffer + dirty arrays are shared by reference through get()).
func _blit(canvas: Control, img: Image) -> void:
	var side: int = canvas.get(&"_side")
	canvas.get(&"_imgs")[side] = img
	canvas.get(&"_dirtys")[side] = true
	canvas.call(&"_push")

## A coloured tee (tee_color fill) with a big white block letter ("F" or "B") — a clear front/back tell.
func _letter_pattern(res: int, letter: String, tee_color: Color) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	img.fill(tee_color)
	var s := res / 32.0
	var white := Color(0.97, 0.97, 0.97)
	_fill_rect(img, 9, 5, 3, 22, s, white)   # spine (both letters)
	_fill_rect(img, 9, 5, 12, 4, s, white)   # top bar
	_fill_rect(img, 9, 14, 11, 3, s, white)  # mid bar
	if letter == "B":
		_fill_rect(img, 9, 24, 12, 3, s, white)  # bottom bar
		_fill_rect(img, 18, 5, 3, 22, s, white)  # right edge closes the bowls
	return img

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, s: float, col: Color) -> void:
	_fill_rect_px(img, int(x * s), int(y * s), int(maxf(1.0, w * s)), int(maxf(1.0, h * s)), col)

func _fill_rect_px(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for px in range(maxi(0, x), mini(img.get_width(), x + w)):
		for py in range(maxi(0, y), mini(img.get_height(), y + h)):
			img.set_pixel(px, py, col)

func _finish() -> void:
	print("QA_SHIRT_DONE dir=", _dir)
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
