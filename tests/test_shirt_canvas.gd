extends GutTest

## ShirtCanvas — the character-creator "draw your own t-shirt" paint widget. Exercises the pure edit-buffer logic:
## dirty tracking (which gates whether a custom shirt is applied/saved), fill/reset, the applied-texture size, and
## the PNG save/restore round-trip. Built IN-TREE (a Control whose _ready allocates its Image); no 3D. It has no
## class_name, so it's preloaded by path (like character_creation preloads it).

const ShirtCanvasScript := preload("res://scripts/ui/shirt_canvas.gd")

func _canvas() -> ShirtCanvasScript:
	var c: ShirtCanvasScript = ShirtCanvasScript.new()
	c.edit_res = 16
	c.apply_res = 64
	add_child_autofree(c)  # _ready allocates the edit buffer + applied texture at these resolutions
	return c

func test_starts_blank_not_dirty() -> void:
	var c := _canvas()
	assert_false(c.is_dirty(), "a fresh canvas is a blank tee, not a custom shirt")
	assert_not_null(c.applied_texture(), "the applied texture exists from the start")
	assert_eq(c.applied_texture().get_width(), 64, "the applied texture is upscaled to apply_res")

func test_fill_marks_dirty_and_reset_clears() -> void:
	var c := _canvas()
	c.set_paint_color(Color(0.2, 0.4, 0.8))
	c.fill_all()
	assert_true(c.is_dirty(), "filling the canvas makes it a custom shirt")
	c.reset()
	assert_false(c.is_dirty(), "reset drops the custom shirt back to the default")

func test_set_paint_color_forces_opaque() -> void:
	var c := _canvas()
	c.set_paint_color(Color(0.1, 0.2, 0.3, 0.4))  # a translucent pick...
	assert_eq(c.paint_color.a, 1.0, "...is forced opaque (a shirt replaces the albedo, no holes)")

func test_png_round_trips_the_painted_colour() -> void:
	var c := _canvas()
	c.set_paint_color(Color(1, 0, 0))
	c.fill_all()
	var bytes := c.png_bytes()
	assert_gt(bytes.size(), 0, "a painted shirt encodes to PNG bytes")
	var c2 := _canvas()
	c2.load_png(bytes)
	assert_true(c2.is_dirty(), "loading a saved shirt marks it a custom shirt")
	var img := Image.new()
	assert_eq(img.load_png_from_buffer(c2.png_bytes()), OK, "the restored shirt re-encodes to a valid PNG")
	assert_eq(img.get_pixel(3, 3), Color(1, 0, 0), "the restored shirt keeps its painted colour")

func test_load_png_ignores_junk() -> void:
	var c := _canvas()
	c.load_png(PackedByteArray())  # empty
	assert_false(c.is_dirty(), "empty bytes leave the canvas blank (no custom shirt)")
	c.load_png(PackedByteArray([1, 2, 3, 4]))  # not a PNG
	assert_false(c.is_dirty(), "un-decodable bytes are ignored, not applied")

# --- Tools: erase / bucket fill / mirror (driven through the API, not synthetic mouse events) -------------------

func test_erase_tool_paints_the_blank_colour() -> void:
	var c := _canvas()
	c.set_paint_color(Color(1, 0, 0))
	c.fill_all()
	c.set_tool(ShirtCanvasScript.TOOL_ERASE)
	c._snapshot_once()
	c._set_cell(Vector2i(2, 2))
	assert_eq(c._img.get_pixel(2, 2), c.blank_color, "the eraser rubs a cell back to the blank tee colour")
	assert_eq(c._img.get_pixel(3, 3), Color(1, 0, 0), "other cells keep their paint")

func test_picking_a_colour_leaves_erase_mode() -> void:
	var c := _canvas()
	c.set_tool(ShirtCanvasScript.TOOL_ERASE)
	assert_true(c.is_erasing(), "the ERASE tool reports erasing (compat alias)")
	c.set_paint_color(Color.RED)
	assert_eq(c.tool, ShirtCanvasScript.TOOL_PAINT, "picking a paint chip returns to the PAINT tool")
	c.set_tool(ShirtCanvasScript.TOOL_FILL)
	c.set_paint_color(Color.GREEN)
	assert_eq(c.tool, ShirtCanvasScript.TOOL_FILL, "...but a pick keeps the bucket selected")

func test_bucket_fills_only_the_clicked_region() -> void:
	var c := _canvas()
	# A vertical black wall splits the tee; bucket-filling the left half must not leak past it.
	c.set_paint_color(Color(0, 0, 0))
	for y in c.edit_res:
		c._set_cell(Vector2i(8, y))
	c.set_paint_color(Color(1, 0, 0))
	c._flood(Vector2i(2, 2))
	assert_eq(c._img.get_pixel(0, 0), Color(1, 0, 0), "the clicked (left) region floods with the brush")
	assert_eq(c._img.get_pixel(8, 4), Color(0, 0, 0), "the dividing wall keeps its colour")
	assert_eq(c._img.get_pixel(12, 4), Color.WHITE, "the far (right) region is untouched")
	assert_true(c.is_dirty(), "a bucket fill is a real edit")

func test_bucket_survives_brush_matching_the_region() -> void:
	var c := _canvas()
	c.set_paint_color(Color.WHITE)  # brush == the blank region colour — the classic flood-fill infinite loop
	c._flood(Vector2i(4, 4))
	assert_true(c.is_dirty(), "a same-colour flood terminates (visited bits, not did-the-pixel-change)")

func test_mirror_paints_both_halves() -> void:
	var c := _canvas()
	c.mirror_x = true
	c.set_paint_color(Color(0, 0, 1))
	c._snapshot_once()
	c._set_cell(Vector2i(1, 5))
	assert_eq(c._img.get_pixel(1, 5), Color(0, 0, 1), "the painted cell takes the brush")
	assert_eq(c._img.get_pixel(c.edit_res - 2, 5), Color(0, 0, 1), "the mirrored twin paints too")
	assert_eq(c._img.get_pixel(2, 5), Color.WHITE, "neighbours are untouched")

# --- Undo -------------------------------------------------------------------------------------------------------

func test_undo_steps_back_one_action_and_restores_dirty() -> void:
	var c := _canvas()
	assert_false(c.can_undo(), "a fresh canvas has nothing to undo")
	c.set_paint_color(Color(1, 0, 0))
	c.fill_all()
	assert_true(c.can_undo(), "an edit arms undo")
	c.undo()
	assert_eq(c._img.get_pixel(3, 3), Color.WHITE, "undo restores the pre-fill pixels")
	assert_false(c.is_dirty(), "undoing the only edit returns to a clean (no-custom-shirt) canvas")
	assert_false(c.can_undo(), "the stack is spent")

func test_undo_recovers_from_reset() -> void:
	var c := _canvas()
	c.set_paint_color(Color(0, 1, 0))
	c.fill_all()
	c.reset()
	assert_false(c.is_dirty(), "reset drops the custom shirt")
	c.undo()
	assert_eq(c._img.get_pixel(3, 3), Color(0, 1, 0), "undo brings the art back from a slipped Reset")
	assert_true(c.is_dirty(), "...and restores the custom-shirt state")

func test_undo_updates_the_applied_texture_in_place() -> void:
	var c := _canvas()
	var tex := c.applied_texture()
	c.set_paint_color(Color(1, 0, 0))
	c.fill_all()
	c.undo()
	assert_eq(c.applied_texture(), tex, "undo updates the SAME shared ImageTexture (bound materials keep working)")
	assert_eq(tex.get_image().get_pixel(0, 0), Color.WHITE, "the shared texture shows the undone (blank) state")

func test_undo_rearms_the_stroke_snapshot() -> void:
	var c := _canvas()
	c.set_paint_color(Color(1, 0, 0))
	c.fill_all()
	c._stroke_snapped = true  # simulate: Ctrl+Z lands MID-DRAG (the stroke already took its snapshot)
	c.undo()
	assert_false(c._stroke_snapped, "undo re-arms the per-stroke snapshot so the drag's tail is undoable too")

# --- No-op guards: a clean canvas must stay clean ---------------------------------------------------------------

func test_reset_on_a_clean_canvas_is_a_noop() -> void:
	var c := _canvas()
	c.reset()
	assert_false(c.can_undo(), "resetting an already-blank tee pushes no undo entry (Undo must not lie)")
	c.set_paint_color(Color(1, 0, 0))
	c.fill_all()
	c.reset()
	c.reset()  # the double-click habit
	assert_eq(c._undo.size(), 2, "only the fill and the FIRST reset snapshot; the no-op second reset doesn't")
	c.undo()
	assert_eq(c._img.get_pixel(3, 3), Color(1, 0, 0), "one Undo after double-Reset brings the art straight back")

func test_erasing_a_clean_canvas_is_a_noop() -> void:
	var c := _canvas()
	c.size = Vector2(160, 160)  # square widget -> _cell_at maps positions 1:1 onto the grid
	c.set_tool(ShirtCanvasScript.TOOL_ERASE)
	c._paint_at(Vector2(15.0, 15.0))
	assert_false(c.is_dirty(), "a stray erase on an untouched tee must NOT bind a blank custom shirt")
	assert_false(c.can_undo(), "...and must not burn an undo entry")
