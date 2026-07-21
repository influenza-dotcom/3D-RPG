extends SceneTree

## TEMP runtime smoke test for the shirt-canvas TOOL upgrade (undo / bucket fill / mirror / erase) — run headless,
## delete after. Drives the REAL widget through the same API surface the creator + GUT tests use (the GUT suite is
## not run automatically per project policy; this is the sanctioned one-off `-s` harness idiom, like __verify_shirt).
## Prints PASS/FAIL per check and exits non-zero on any failure.

var _pass := 0
var _fail := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", msg)
	else:
		_fail += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	var Canvas: GDScript = load("res://scripts/ui/shirt_canvas.gd")
	var c: Control = Canvas.new()
	c.edit_res = 16
	c.apply_res = 64
	get_root().add_child(c)
	if c._img == null:
		c._rebuild_buffers()  # -s _initialize runs before the root is READY, so the child's _ready hasn't fired yet

	# Undo: arm on edit, restore pixels + dirty, spend the stack.
	_check(not c.can_undo(), "fresh canvas: nothing to undo")
	c.set_paint_color(Color(1, 0, 0))
	c.fill_all()
	_check(c.can_undo(), "an edit arms undo")
	c.undo()
	_check(c._img.get_pixel(3, 3) == Color.WHITE, "undo restores pre-fill pixels")
	_check(not c.is_dirty(), "undoing the only edit returns to a clean canvas")
	_check(not c.can_undo(), "the undo stack is spent")

	# Undo recovers from Reset.
	c.set_paint_color(Color(0, 1, 0))
	c.fill_all()
	c.reset()
	_check(not c.is_dirty(), "reset drops the custom shirt")
	c.undo()
	_check(c._img.get_pixel(3, 3) == Color(0, 1, 0), "undo recovers the art from a slipped Reset")
	_check(c.is_dirty(), "...and restores the custom-shirt state")

	# Undo updates the SHARED applied texture in place.
	var tex: Texture2D = c.applied_texture()
	c.undo()  # back to the green fill
	c.undo()  # back to blank
	_check(c.applied_texture() == tex, "undo keeps the same shared ImageTexture")
	_check((tex as ImageTexture).get_image().get_pixel(0, 0) == Color.WHITE, "the shared texture shows the undone state")

	# Bucket: fills only the clicked region; wall holds; same-colour flood terminates.
	c.reset()
	c.set_paint_color(Color(0, 0, 0))
	for y in int(c.edit_res):
		c._set_cell(Vector2i(8, y))
	c.set_paint_color(Color(1, 0, 0))
	c._flood(Vector2i(2, 2))
	_check(c._img.get_pixel(0, 0) == Color(1, 0, 0), "bucket floods the clicked region")
	_check(c._img.get_pixel(8, 4) == Color(0, 0, 0), "the dividing wall keeps its colour")
	_check(c._img.get_pixel(12, 4) == Color.WHITE, "the far region is untouched")
	c.set_paint_color(Color.WHITE)
	c._flood(Vector2i(12, 4))  # brush == region colour: must terminate (visited bits)
	_check(true, "a same-colour flood terminates")

	# Mirror: paints the twin cell; erase tool rubs back to blank; a colour pick leaves ERASE (keeps FILL).
	c.reset()
	c.mirror_x = true
	c.set_paint_color(Color(0, 0, 1))
	c._set_cell(Vector2i(1, 5))
	_check(c._img.get_pixel(1, 5) == Color(0, 0, 1), "mirror: the painted cell takes the brush")
	_check(c._img.get_pixel(int(c.edit_res) - 2, 5) == Color(0, 0, 1), "mirror: the twin cell paints too")
	c.mirror_x = false
	c.set_tool(Canvas.TOOL_ERASE)
	c._set_cell(Vector2i(1, 5))
	_check(c._img.get_pixel(1, 5) == Color.WHITE, "the eraser rubs back to the blank colour")
	_check(c.is_erasing(), "compat alias: ERASE tool reports erasing")
	c.set_paint_color(Color.RED)
	_check(int(c.tool) == int(Canvas.TOOL_PAINT), "picking a colour returns ERASE to PAINT")
	c.set_tool(Canvas.TOOL_FILL)
	c.set_paint_color(Color.GREEN)
	_check(int(c.tool) == int(Canvas.TOOL_FILL), "...but keeps the bucket selected")

	# Brush size: a 3-wide stamp paints a 3x3 block; erase respects it; clamp guards; size 1 is a single pixel.
	c.reset()
	c.set_tool(Canvas.TOOL_PAINT)
	c.set_paint_color(Color(1, 0, 0))
	c.set_brush_size(3)
	c._set_cell(Vector2i(6, 6))
	var block_ok := true
	for by in range(5, 8):
		for bx in range(5, 8):
			block_ok = block_ok and c._img.get_pixel(bx, by) == Color(1, 0, 0)
	_check(block_ok, "brush size 3 stamps a 3x3 block centred on the cell")
	_check(c._img.get_pixel(4, 6) == Color.WHITE and c._img.get_pixel(8, 6) == Color.WHITE, "...and no wider")
	c.set_tool(Canvas.TOOL_ERASE)
	c._set_cell(Vector2i(6, 6))
	_check(c._img.get_pixel(6, 6) == Color.WHITE and c._img.get_pixel(5, 5) == Color.WHITE, "erase respects brush size (3x3 rubbed)")
	c.set_brush_size(1)
	c.set_tool(Canvas.TOOL_PAINT)
	c.set_paint_color(Color(0, 0, 1))
	c._set_cell(Vector2i(10, 10))
	_check(c._img.get_pixel(10, 10) == Color(0, 0, 1) and c._img.get_pixel(11, 10) == Color.WHITE, "size 1 is a single pixel")
	c.set_brush_size(999)
	_check(c.brush_size == int(c.edit_res), "set_brush_size clamps to edit_res")
	c.set_brush_size(0)
	_check(c.brush_size == 1, "set_brush_size clamps up to 1")
	c.set_brush_size(1)

	# No-op guards: a clean canvas stays clean (stray erase / double-Reset must not lie to Undo).
	c.reset()
	c.set_tool(Canvas.TOOL_PAINT)
	c._undo.clear()
	c.reset()
	_check(not c.can_undo(), "reset on an already-blank tee pushes no undo entry")
	c.size = Vector2(160, 160)
	c.set_tool(Canvas.TOOL_ERASE)
	c._paint_at(Vector2(15.0, 15.0))
	_check(not c.is_dirty(), "a stray erase on an untouched tee stays not-dirty")
	_check(not c.can_undo(), "...and burns no undo entry")
	c.set_tool(Canvas.TOOL_PAINT)
	c.set_paint_color(Color(1, 0, 0))
	c.fill_all()
	c.reset()
	c.reset()  # double-click habit: second reset is a no-op
	c.undo()
	_check(c._img.get_pixel(3, 3) == Color(1, 0, 0), "one Undo after double-Reset brings the art straight back")

	# Undo mid-drag re-arms the per-stroke snapshot.
	c._stroke_snapped = true
	c.undo()
	_check(not c._stroke_snapped, "undo re-arms the per-stroke snapshot (mid-drag Ctrl+Z keeps the tail undoable)")

	# Chorded buttons: erase-mode follows the LIVE button mask, not the last press.
	c.reset()
	c._undo.clear()
	c.set_tool(Canvas.TOOL_PAINT)
	c.set_paint_color(Color(0, 0, 1))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = Vector2(15.0, 15.0)
	c._gui_input(press)
	_check(c._img.get_pixel(1, 1) == Color(0, 0, 1), "left press paints")
	var move := InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT  # right chords in mid-drag
	move.position = Vector2(25.0, 15.0)
	c._gui_input(move)
	_check(c._img.get_pixel(2, 1) == c.blank_color, "chorded right-in-mask erases")
	var move2 := InputEventMouseMotion.new()
	move2.button_mask = MOUSE_BUTTON_MASK_LEFT  # right released, left survives
	move2.position = Vector2(35.0, 15.0)
	c._gui_input(move2)
	_check(c._img.get_pixel(3, 1) == Color(0, 0, 1), "after the right RELEASE the surviving left drag paints again")

	# Whole-body models never wear the drawn shirt.
	var Cat: GDScript = load("res://scripts/player/character_appearance_catalog.gd")
	var wcat = Cat.default()
	wcat.bodies[0].whole_body = true
	var wimg := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	wimg.fill(Color.RED)
	var wtex := ImageTexture.create_from_image(wimg)
	var wswap = load("res://scripts/components/body_model_swap.gd").new()
	wcat.configure_swap(wswap, {"body": "standard", "shirt": wtex})
	_check(wswap.body_texture != wtex, "whole-body model keeps its own texture, not the drawn shirt")
	_check(not wswap.body_texture_planar, "...and never takes planar mode")
	wswap.free()

	# Planar material builder (off-tree BodyModelSwap): parameterises from the mesh AABB.
	var swap = load("res://scripts/components/body_model_swap.gd").new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 1.0, 0.8)  # Z-wide "torso": width axis Z, depth X
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var stex := ImageTexture.create_from_image(img)
	var mat: ShaderMaterial = swap._planar_shirt_material(box, stex, Color.WHITE)
	_check(mat != null and mat.shader != null, "planar material builds with the shirt shader")
	_check(mat.get_shader_parameter(&"width_dir") == Vector3(0, 0, 1), "Z-wide mesh: width axis Z")
	_check(mat.get_shader_parameter(&"depth_dir") == Vector3(1, 0, 0), "Z-wide mesh: depth axis X")
	_check(mat.get_shader_parameter(&"shirt_tex") == stex, "the drawn texture is bound")
	swap.free()

	c.queue_free()
	print("=== SHIRT TOOLS VERIFY: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
