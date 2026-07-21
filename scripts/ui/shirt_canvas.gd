extends Control

## The character creator's "DRAW YOUR OWN T-SHIRT" paint surface. The player paints on a small square pixel grid;
## the result becomes the torso's albedo (a BodyModelSwap `body_texture`, planar-projected onto the chest) — a
## blank tee they decorate. Self-drawing (no child TextureRect): `_draw()` blits the live texture + a faint grid +
## the hover-cell highlight, `_gui_input` paints cells with drag + line-interpolation so a quick swipe leaves no gaps.
##
## TOOLS: PAINT (drag-paint the brush colour), FILL (bucket — flood the clicked same-colour region), ERASE
## (drag-paint the blank colour). RIGHT-drag always pixel-erases whatever the tool (quick fixes without switching).
## `mirror_x` paints both horizontal halves at once (symmetric designs). Every stroke/fill/reset snapshots the
## buffer first, so `undo()` (also Ctrl+Z while visible) steps back through the last MAX_UNDO edits — including
## un-reset. The creator owns the tool/mirror BUTTONS; this widget owns the behaviour.
##
## NO `class_name` on purpose — it's preloaded BY PATH (as `ShirtCanvas`) by character_creation.gd (which itself
## has no class_name) and used as a type there, matching the StatBudget / CharacterPreview-preload idiom and keeping
## this UI helper off the global class cache.
##
## TWO resolutions. The EDIT buffer (`_img`, `edit_res`²) is what the player paints and what gets SAVED (a tiny
## PNG). The APPLIED texture (`_tex`, `apply_res`², a NEAREST upscale) is what the 3D material samples, so the
## chunky pixels stay CRISP through the material's own filter. `_tex` is a SINGLE ImageTexture updated in
## place: a menu binds it once as `body_texture` and every later stroke shows live in the 3D preview with NO rig
## rebuild (see character_creation `_on_shirt_changed`). The drawn shirt is cosmetic + first-person-invisible today
## (the torso only shows in the creation / Stats portrait) and persists as PNG bytes in
## `GameState.appearance["shirt"]` — decoded back by `CharacterAppearanceCatalog.shirt_texture`.

## Emitted after ANY edit (stroke / fill / erase / reset / undo). The creator binds the preview on the first one and
## reads is_dirty() on it; every edit has already updated the shared `_tex` in place before this fires.
signal changed

## The paint tools (see `tool`). Plain int consts, not an enum — the creator preloads this script by path and an
## enum on a path-preloaded script can't be referenced as a type there.
const TOOL_PAINT := 0
const TOOL_FILL := 1
const TOOL_ERASE := 2

## Undo depth. Snapshots are edit_res² RGBA images (~4KB at 32) — 32 of them is nothing.
const MAX_UNDO := 32

## Logical paint resolution — the grid the player draws on. Bigger = finer detail but smaller (harder-to-click)
## cells. Chunky-by-design for the game's PS1 look. Changing it at runtime rebuilds the (blanked) buffers.
@export var edit_res: int = 32:
	set(value):
		edit_res = maxi(4, value)
		if is_inside_tree():
			_rebuild_buffers()
## Resolution the shirt is NEAREST-upscaled to before it skins the torso, so the pixels read crisp through the 3D
## material's linear sampling. A multiple of edit_res keeps every logical cell an exact block. Fixed for a session.
@export var apply_res: int = 128
## The blank-tee colour: the canvas starts here and the eraser paints it. Kept opaque — the shirt REPLACES the
## torso albedo, so transparency would punch holes rather than reveal a base layer.
@export var blank_color: Color = Color.WHITE
## Faint grid-line colour drawn over the canvas so the (possibly blank) cells stay visible against a dark panel.
@export var grid_color: Color = Color(0, 0, 0, 0.15)

var paint_color: Color = Color.BLACK   ## the currently selected brush colour (set by the palette swatches)
var tool: int = TOOL_PAINT             ## the active tool (TOOL_*) — set via set_tool by the creator's toggle row
var mirror_x: bool = false             ## paint both horizontal halves at once (symmetric designs)
var brush_size: int = 1                ## side of the square brush footprint in CELLS (1 = a single pixel); set via set_brush_size

var _img: Image                        ## the edit buffer (edit_res²) — painted + saved
var _tex: ImageTexture                 ## the applied texture (apply_res²) — shared with the 3D material, updated in place
var _dirty: bool = false               ## has the player painted anything? gates whether a custom shirt is applied / emitted
var _last_cell := Vector2i(-1, -1)     ## last cell painted this drag, to interpolate fast mouse moves (no gaps)
var _hover_cell := Vector2i(-1, -1)    ## cell under the cursor (highlighted in _draw); (-1,-1) = not over the canvas
var _stroke_erase: bool = false        ## this drag started with the RIGHT button -> it erases whatever the tool
var _stroke_snapped: bool = false      ## an undo snapshot has been taken for the current drag (one per stroke)
var _undo: Array[Dictionary] = []      ## snapshot stack: {img: Image copy, dirty: bool}, oldest first

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp blocks when _draw blits _tex
	_rebuild_buffers()

## (Re)create the edit buffer + the applied texture at the current resolutions, blanked, and drop dirty + undo.
func _rebuild_buffers() -> void:
	_img = Image.create(edit_res, edit_res, false, Image.FORMAT_RGBA8)
	_img.fill(blank_color)
	_tex = ImageTexture.create_from_image(_upscaled())
	_dirty = false
	_undo.clear()
	queue_redraw()

## The edit buffer NEAREST-upscaled to apply_res — the crisp texture the 3D material samples. Deep-copied so the
## resize never touches the edit buffer. Falls back to the edit size if apply_res is smaller (keeps _tex stable).
func _upscaled() -> Image:
	var big := Image.new()
	big.copy_from(_img)
	if apply_res > edit_res:
		big.resize(apply_res, apply_res, Image.INTERPOLATE_NEAREST)
	return big

## Push the edit buffer into the live applied texture (in place — bound materials update) + redraw + notify.
func _push() -> void:
	if _tex != null:
		_tex.update(_upscaled())
	queue_redraw()
	changed.emit()

# --- painting ---------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_last_cell = Vector2i(-1, -1)  # start (or end) of a drag stroke
			_stroke_snapped = false
			# Erase-mode comes from the LIVE button mask (right button held -> erase), not a sticky per-press
			# flag: with chorded left+right presses, whichever button survives must get ITS mode back.
			_stroke_erase = (mb.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0
			if mb.pressed:
				var cell := _cell_at(mb.position)
				if cell.x >= 0 and tool == TOOL_FILL and not _stroke_erase:
					_snapshot_once()
					_flood(cell)
				else:
					_paint_at(mb.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var hover := _cell_at(mm.position)
		if hover != _hover_cell:
			_hover_cell = hover
			queue_redraw()  # move the hover highlight even when not painting
		if mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
			_stroke_erase = (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0  # keep mode live through the drag
			if tool != TOOL_FILL or _stroke_erase:  # the bucket is click-only; dragging it doesn't smear floods
				_paint_at(mm.position)
			accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_cell.x >= 0:
		_hover_cell = Vector2i(-1, -1)
		queue_redraw()

## Ctrl+Z undo while the canvas is on-screen (the Shirt tab is the visible one). Unhandled-key so the name
## LineEdit's own editing shortcuts keep working when it has focus.
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_Z and k.ctrl_pressed and can_undo():
		undo()
		get_viewport().set_input_as_handled()

## Paint the cell under a widget-local position, interpolating from the last cell so a fast drag is continuous.
func _paint_at(local_pos: Vector2) -> void:
	var cell := _cell_at(local_pos)
	if cell.x < 0:
		return
	# Erasing a CLEAN canvas is a no-op (the tee is already blank): don't mark it a custom shirt, don't burn an
	# undo entry — a stray right-click on an untouched tab must not swap the base shirt for a plain white one.
	if (tool == TOOL_ERASE or _stroke_erase) and not _dirty:
		return
	_snapshot_once()  # first painted cell of this drag — even if the press landed on the widget's margin
	if _last_cell.x >= 0 and _last_cell != cell:
		_paint_line(_last_cell, cell)
	else:
		_set_cell(cell)
	_last_cell = cell
	_dirty = true
	_push()

## The edit-grid cell under a widget-local position, or (-1,-1) outside the square canvas area.
func _cell_at(local_pos: Vector2) -> Vector2i:
	var area := _canvas_rect()
	if area.size.x <= 0.0 or not area.has_point(local_pos):
		return Vector2i(-1, -1)
	var u := (local_pos - area.position) / area.size
	return Vector2i(clampi(int(u.x * edit_res), 0, edit_res - 1), clampi(int(u.y * edit_res), 0, edit_res - 1))

func _set_cell(cell: Vector2i) -> void:
	var col := blank_color if (tool == TOOL_ERASE or _stroke_erase) else paint_color
	_stamp(cell, col)
	if mirror_x:
		_stamp(Vector2i(edit_res - 1 - cell.x, cell.y), col)

## Paint the brush FOOTPRINT — a `brush_size`×`brush_size` square of cells centred on `center` (for an even size it
## biases up-left by half a cell), clipped to the grid. brush_size 1 is a single pixel (the original behaviour).
func _stamp(center: Vector2i, col: Color) -> void:
	if brush_size <= 1:
		_img.set_pixelv(center, col)
		return
	@warning_ignore("integer_division")  # deliberate: half the brush in whole cells; the dropped .5 is the up-left bias
	var start := center - Vector2i(brush_size / 2, brush_size / 2)
	for dy in brush_size:
		for dx in brush_size:
			var p := start + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < edit_res and p.y < edit_res:
				_img.set_pixelv(p, col)

## Paint every cell along the line a<->b (Bresenham) so a quick drag paints a continuous stroke.
func _paint_line(a: Vector2i, b: Vector2i) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		_set_cell(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy

## Bucket: flood the clicked same-colour region with the brush (both halves' regions when mirroring).
func _flood(seed_cell: Vector2i) -> void:
	_flood_from(seed_cell)
	if mirror_x:
		_flood_from(Vector2i(edit_res - 1 - seed_cell.x, seed_cell.y))
	_dirty = true
	_push()

## 4-way flood from `seed_cell` over its contiguous same-colour region. Explicit visited bits (not "did the pixel
## change") so a brush matching the region colour can never loop.
func _flood_from(seed_cell: Vector2i) -> void:
	var target := _img.get_pixelv(seed_cell)  # exact ==: both sides are the same 8-bit-quantised buffer
	var visited := PackedByteArray()
	visited.resize(edit_res * edit_res)
	var stack: Array[Vector2i] = [seed_cell]
	visited[seed_cell.y * edit_res + seed_cell.x] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		_img.set_pixelv(c, paint_color)
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + o
			if n.x < 0 or n.y < 0 or n.x >= edit_res or n.y >= edit_res:
				continue
			var i := n.y * edit_res + n.x
			if visited[i] == 1 or _img.get_pixelv(n) != target:
				continue
			visited[i] = 1
			stack.append(n)

# --- undo -------------------------------------------------------------------------------------------------------

## Snapshot the buffer once per user action (stroke / bucket / fill / reset) so undo() steps whole actions back.
func _snapshot_once() -> void:
	if _stroke_snapped:
		return
	_stroke_snapped = true
	_snapshot()

func _snapshot() -> void:
	var copy := Image.new()
	copy.copy_from(_img)
	_undo.append({"img": copy, "dirty": _dirty})
	while _undo.size() > MAX_UNDO:
		_undo.pop_front()

func can_undo() -> bool:
	return not _undo.is_empty()

## Step back one action (stroke / bucket / fill / reset). Restores the dirty flag too, so undoing all the way to a
## blank tee also drops the "custom shirt" state (the creator un-applies it on the emitted change).
func undo() -> void:
	if _undo.is_empty():
		return
	var snap: Dictionary = _undo.pop_back()
	_img = snap["img"]
	_dirty = bool(snap["dirty"])
	_last_cell = Vector2i(-1, -1)
	_stroke_snapped = false  # a Ctrl+Z mid-drag consumed this stroke's snapshot; the drag's tail must re-arm one
	_push()

# --- tools + palette hooks --------------------------------------------------------------------------------------

## Select the brush colour (forced opaque — the shirt replaces the albedo). Leaves ERASE for the brush (picking a
## paint means you want to paint) but keeps a FILL pick as FILL.
func set_paint_color(c: Color) -> void:
	paint_color = Color(c.r, c.g, c.b, 1.0)
	if tool == TOOL_ERASE:
		tool = TOOL_PAINT

func set_tool(t: int) -> void:
	tool = clampi(t, TOOL_PAINT, TOOL_ERASE)

## Set the square brush footprint (side in cells; 1 = single pixel). Clamped to [1, edit_res] and redraws so the
## hover preview reflects the new size at once. Applies to PAINT + ERASE (the bucket fills a whole region regardless).
func set_brush_size(n: int) -> void:
	brush_size = clampi(n, 1, edit_res)
	queue_redraw()

## Compat alias for the old two-state API (pre-tools): erase ON = the ERASE tool, OFF = back to PAINT.
func set_erase(on: bool) -> void:
	tool = TOOL_ERASE if on else TOOL_PAINT

func is_erasing() -> bool:
	return tool == TOOL_ERASE

## Flood the whole canvas with the current brush (or the blank colour while erasing) — a solid-colour tee.
func fill_all() -> void:
	_snapshot()
	_img.fill(blank_color if tool == TOOL_ERASE else paint_color)
	_dirty = true
	_push()

## Wipe back to a blank tee AND drop the dirty flag — the creator reads is_dirty() to mean "no custom shirt".
## Snapshots first, so a slip of the Reset button is one undo() away from recovered art. A Reset of an
## already-clean canvas is a pure no-op (no snapshot, no emission): a double-click habit must not push blank
## entries that make the first Undo "do nothing" or evict the real art from the capped stack.
func reset() -> void:
	if not _dirty:
		return
	_snapshot()
	_img.fill(blank_color)
	_dirty = false
	_push()

# --- state for the creator / save -------------------------------------------------------------------------------

## Has the player actually drawn a shirt? False -> keep the character's default (base) shirt; the creator only
## applies / emits a custom shirt while this is true.
func is_dirty() -> bool:
	return _dirty

## The live applied texture (apply_res², NEAREST-upscaled) to bind as a BodyModelSwap `body_texture`. Shared +
## updated in place, so every stroke shows at once in a material that already references it.
func applied_texture() -> Texture2D:
	return _tex

## The edit buffer as PNG bytes — the compact form stored in GameState.appearance["shirt"].
func png_bytes() -> PackedByteArray:
	return _img.save_png_to_buffer()

## Restore a saved shirt (an edit-res PNG). Marks the canvas dirty (it IS a custom shirt). No-op on empty / bad
## bytes. A restore is a load, not an edit — the undo stack starts fresh from it.
func load_png(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != edit_res or img.get_height() != edit_res:
		img.resize(edit_res, edit_res, Image.INTERPOLATE_NEAREST)
	_img = img
	_dirty = true
	_undo.clear()
	if _tex != null:
		_tex.update(_upscaled())
	else:
		_tex = ImageTexture.create_from_image(_upscaled())
	queue_redraw()

# --- drawing ----------------------------------------------------------------------------------------------------

## The square draw area, centred in the widget (keeps cells square even if the Control isn't a perfect square).
func _canvas_rect() -> Rect2:
	var s := minf(size.x, size.y)
	return Rect2(((size - Vector2(s, s)) * 0.5).floor(), Vector2(s, s))

func _draw() -> void:
	var area := _canvas_rect()
	if area.size.x <= 0.0:
		return
	if _tex != null:
		draw_texture_rect(_tex, area, false)
	# Faint grid so the (possibly blank) cells read; skipped once cells shrink too small to be useful.
	var cell := area.size.x / float(edit_res)
	if cell >= 3.0:
		for i in range(edit_res + 1):
			var x := area.position.x + i * cell
			var y := area.position.y + i * cell
			draw_line(Vector2(x, area.position.y), Vector2(x, area.position.y + area.size.y), grid_color, 1.0)
			draw_line(Vector2(area.position.x, y), Vector2(area.position.x + area.size.x, y), grid_color, 1.0)
	# Hover highlight: a preview of the brush FOOTPRINT (size + colour) the click would paint, plus the mirrored
	# twin while mirroring — so the chosen brush size is legible before you commit a stroke.
	if _hover_cell.x >= 0 and cell >= 3.0:
		var col := blank_color if tool == TOOL_ERASE else paint_color
		_draw_brush_preview(area, cell, _hover_cell, col, 0.45, true)
		var mx := edit_res - 1 - _hover_cell.x
		if mirror_x and mx != _hover_cell.x:
			_draw_brush_preview(area, cell, Vector2i(mx, _hover_cell.y), col, 0.25, false)
	draw_rect(area, Color(1, 1, 1, 0.25), false, 1.0)  # a light frame around the canvas

## Fill (and optionally outline) the brush footprint at `center`, clamped to the canvas, for the hover preview.
func _draw_brush_preview(area: Rect2, cell: float, center: Vector2i, col: Color, alpha: float, outline: bool) -> void:
	@warning_ignore("integer_division")  # deliberate: half the brush in whole cells; the dropped .5 is the up-left bias
	var start := center - Vector2i(brush_size / 2, brush_size / 2)
	var lo := Vector2i(maxi(0, start.x), maxi(0, start.y))
	var hi := Vector2i(mini(edit_res, start.x + brush_size), mini(edit_res, start.y + brush_size))
	if lo.x >= hi.x or lo.y >= hi.y:
		return
	var r := Rect2(area.position + Vector2(lo) * cell, Vector2(hi - lo) * cell)
	draw_rect(r, Color(col.r, col.g, col.b, alpha))
	if outline:
		draw_rect(r, Color(1, 1, 1, 0.9), false, 1.0)
