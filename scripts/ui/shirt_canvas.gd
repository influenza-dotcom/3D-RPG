extends Control

## The character creator's "DRAW YOUR OWN T-SHIRT" paint surface. The player paints on a small square pixel grid;
## the result becomes the torso's albedo (a BodyModelSwap `body_texture`, planar-projected onto the chest) — a
## blank tee they decorate. Self-drawing (no child TextureRect): `_draw()` blits the live texture + a faint grid +
## the hover-cell highlight, `_gui_input` paints cells with drag + line-interpolation so a quick swipe leaves no gaps.
##
## FRONT + BACK: the tee has TWO independently-drawn sides (SIDE_FRONT / SIDE_BACK). The canvas edits ONE at a time
## (`_side`, set by set_side()); every paint/undo/fill/reset acts on the active side's own buffer + undo stack.
## reset_all() is the creator-facing "drop the custom shirt" command and clears both sides. The APPLIED + SAVED
## texture is a COMBINED image, front stacked ABOVE back (edit_res × 2·edit_res), which the planar shader samples
## per-face (top half on chest-facing faces, bottom half on back-facing ones — see shirt_planar.gdshader).
##
## TOOLS: PAINT (drag-paint the brush colour), FILL (bucket — flood the clicked same-colour region), ERASE
## (drag-paint the blank colour), EYEDROP (click/drag to sample the cell's colour INTO the brush — emits
## color_picked so the creator can sync its swatches). RIGHT-drag always pixel-erases whatever the tool (quick
## fixes without switching). `mirror_x` paints both horizontal halves at once; `brush_size` is the square
## footprint. Every stroke/fill/reset snapshots the ACTIVE side first, so `undo()` (also Ctrl+Z while visible)
## steps back through that side's last MAX_UNDO edits — including un-reset. The creator owns the tool/side/mirror
## BUTTONS; this widget owns the behaviour.
##
## NO `class_name` on purpose — it's preloaded BY PATH (as `ShirtCanvas`) by character_creation.gd (which itself
## has no class_name) and used as a type there, matching the StatBudget / CharacterPreview-preload idiom and keeping
## this UI helper off the global class cache.
##
## TWO resolutions. The EDIT buffers (`_imgs`, edit_res² each) are what the player paints and what gets SAVED (a
## tiny combined PNG). The APPLIED texture (`_tex`, apply_res-upscaled, a NEAREST upscale) is what the 3D material
## samples, so the chunky pixels stay CRISP through the material's own filter. `_tex` is a SINGLE ImageTexture
## updated in place: a menu binds it once as `body_texture` and every later stroke shows live in the 3D preview with
## NO rig rebuild (see character_creation `_on_shirt_changed`). The drawn shirt is cosmetic + first-person-invisible
## today (the torso only shows in the creation / Stats portrait) and persists as PNG bytes in
## `GameState.appearance["shirt"]` — decoded back by `CharacterAppearanceCatalog.shirt_texture`.

## Emitted after ANY edit (stroke / fill / erase / reset / undo). The creator binds the preview on the first one and
## reads is_dirty() on it; every edit has already updated the shared `_tex`. A bare side switch does NOT emit (the
## combined texture already carries both sides — the creator re-gates its Undo button itself in _on_shirt_side).
signal changed

## Emitted by the EYEDROP tool with the colour sampled from the canvas (already opaque). The creator uses it to
## reflect the new brush colour on the Custom swatch + preset highlights.
signal color_picked(color: Color)

## The paint tools (see `tool`). Plain int consts, not an enum — the creator preloads this script by path and an
## enum on a path-preloaded script can't be referenced as a type there.
const TOOL_PAINT := 0
const TOOL_FILL := 1
const TOOL_ERASE := 2
const TOOL_EYEDROP := 3  ## click/drag samples the cell's colour into the brush (does not paint)

## The two independently-drawn sides of the tee (indices into `_imgs` / `_undos` / `_dirtys`).
const SIDE_FRONT := 0
const SIDE_BACK := 1

## Undo depth (PER SIDE). Snapshots are edit_res² RGBA images (~4KB at 32) — 32 of them per side is nothing.
const MAX_UNDO := 32

## Logical paint resolution — the grid the player draws on. Bigger = finer detail but smaller (harder-to-click)
## cells. Chunky-by-design for the game's PS1 look. Changing it at runtime rebuilds the (blanked) buffers.
@export var edit_res: int = 32:
	set(value):
		edit_res = maxi(4, value)
		if is_inside_tree():
			_rebuild_buffers()
## Resolution each side is NEAREST-upscaled to before it skins the torso, so the pixels read crisp through the 3D
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

var _imgs: Array[Image] = []           ## the two edit buffers [front, back] (edit_res² each) — painted + saved
var _dirtys: Array[bool] = [false, false]  ## per-side "has the player painted this side?" — gates the custom shirt
var _undos: Array = []                 ## per-side snapshot stacks: [ [ {img, dirty}, … ], … ], oldest first
var _side: int = SIDE_FRONT            ## which side the canvas is currently editing / showing
var _tex: ImageTexture                 ## the COMBINED applied texture (front over back) — shared with the 3D material, updated in place

var _last_cell := Vector2i(-1, -1)     ## last cell painted this drag, to interpolate fast mouse moves (no gaps)
var _hover_cell := Vector2i(-1, -1)    ## cell under the cursor (highlighted in _draw); (-1,-1) = not over the canvas
var _stroke_erase: bool = false        ## this drag started with the RIGHT button -> it erases whatever the tool
var _stroke_snapped: bool = false      ## an undo snapshot has been taken for the current drag (one per stroke)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp blocks when _draw blits _tex
	_rebuild_buffers()

## (Re)create both edit buffers + the combined applied texture at the current resolutions, blanked, and drop
## every side's dirty flag + undo stack.
func _rebuild_buffers() -> void:
	_imgs = [_blank_side(), _blank_side()]
	_dirtys = [false, false]
	_undos = [[], []]
	_tex = ImageTexture.create_from_image(_combined_upscaled())
	queue_redraw()

func _blank_side() -> Image:
	var img := Image.create(edit_res, edit_res, false, Image.FORMAT_RGBA8)
	img.fill(blank_color)
	return img

## The two edit buffers stacked front-over-back into ONE image (edit_res × 2·edit_res) — the compact form that's
## saved and that the planar shader samples (top half = front faces, bottom half = back faces).
func _combined_edit() -> Image:
	var c := Image.create(edit_res, edit_res * 2, false, Image.FORMAT_RGBA8)
	c.blit_rect(_imgs[SIDE_FRONT], Rect2i(0, 0, edit_res, edit_res), Vector2i(0, 0))
	c.blit_rect(_imgs[SIDE_BACK], Rect2i(0, 0, edit_res, edit_res), Vector2i(0, edit_res))
	return c

## The combined edit image NEAREST-upscaled to apply_res (keeping the 1:2 front/back stack) — the crisp texture the
## 3D material samples. Falls back to the edit size if apply_res is smaller (keeps _tex stable).
func _combined_upscaled() -> Image:
	var c := _combined_edit()
	if apply_res > edit_res:
		c.resize(apply_res, apply_res * 2, Image.INTERPOLATE_NEAREST)
	return c

## Push both edit buffers into the live combined texture (in place — bound materials update) + redraw + notify.
func _push() -> void:
	if _tex != null:
		_tex.update(_combined_upscaled())
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
				if cell.x >= 0 and tool == TOOL_EYEDROP and not _stroke_erase:
					_eyedrop(cell)  # sample, don't paint
				elif cell.x >= 0 and tool == TOOL_FILL and not _stroke_erase:
					_flood(cell)  # owns its own snapshot — only if the fill actually changes the canvas (no no-op undo spam)
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
			# Right-drag always erases; PAINT/ERASE drag-paint; EYEDROP drag-samples; FILL is click-only (no smear).
			if _stroke_erase or tool == TOOL_PAINT or tool == TOOL_ERASE:
				_paint_at(mm.position)
			elif tool == TOOL_EYEDROP:
				_eyedrop(hover)
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
	# Erasing a CLEAN side is a no-op (it's already blank): don't mark it a custom shirt, don't burn an undo
	# entry — a stray right-click on an untouched side must not swap the base shirt for a plain white one.
	if (tool == TOOL_ERASE or _stroke_erase) and not _dirtys[_side]:
		return
	_snapshot_once()  # first painted cell of this drag — even if the press landed on the widget's margin
	if _last_cell.x >= 0 and _last_cell != cell:
		_paint_line(_last_cell, cell)
	else:
		_set_cell(cell)
	_last_cell = cell
	_dirtys[_side] = true
	_push()

## Sample the active side's colour at `cell` into the brush and announce it (EYEDROP tool). Sets paint_color
## DIRECTLY (not via set_paint_color, which would kick us out of EYEDROP) so a drag keeps scrubbing colours; the
## player clicks Paint to draw with the pick. No snapshot / dirty change — it only reads.
func _eyedrop(cell: Vector2i) -> void:
	if cell.x < 0:
		return
	var c := _imgs[_side].get_pixelv(cell)
	paint_color = Color(c.r, c.g, c.b, 1.0)  # opaque (the buffer already is), but normalise defensively
	color_picked.emit(paint_color)

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
		# The mirrored twin biases its footprint the OTHER way (down-RIGHT): an even brush biases up-left, so its true
		# reflection across the axis must bias up-right — otherwise the mirrored blob lands one cell off and "symmetric"
		# designs come out visibly asymmetric for brush sizes 2 and 4. Odd sizes are centre-symmetric and unaffected.
		_stamp(Vector2i(edit_res - 1 - cell.x, cell.y), col, true)

## Paint the brush FOOTPRINT — a `brush_size`×`brush_size` square of cells centred on `center` (for an even size it
## biases up-left by half a cell, or up-RIGHT for the mirrored twin so the two halves reflect exactly), clipped to the
## grid. brush_size 1 is a single pixel (the original behaviour).
func _stamp(center: Vector2i, col: Color, mirror: bool = false) -> void:
	var img: Image = _imgs[_side]
	if brush_size <= 1:
		img.set_pixelv(center, col)
		return
	var start := center - Vector2i(_brush_start_offset_x(mirror), _brush_start_offset_y())
	for dy in brush_size:
		for dx in brush_size:
			var p := start + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < edit_res and p.y < edit_res:
				img.set_pixelv(p, col)

## Half the brush in whole cells for the footprint's top-left corner. X biases left (dropped .5) normally, but the
## mirrored twin biases right ((brush_size-1)/2) so an even footprint's reflection across the vertical axis is exact.
@warning_ignore("integer_division")
func _brush_start_offset_x(mirror: bool) -> int:
	return (brush_size - 1) / 2 if mirror else brush_size / 2

@warning_ignore("integer_division")
func _brush_start_offset_y() -> int:
	return brush_size / 2

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

## Bucket: flood the clicked same-colour region with the brush (both halves' regions when mirroring). Guards a NO-OP fill:
## a bucket click that repaints same-on-same (white on an already-blank side, or re-filling an already-filled region)
## must NOT snapshot, dirty the side, or push. Without this it silently swaps the authored base shirt for a plain white
## tee (the exact failure _paint_at's erase guard prevents) and spams identical undo entries that evict real art from
## the 32-cap. The change-check runs BEFORE the snapshot so a no-op leaves the undo stack (and the clean side) untouched.
func _flood(seed_cell: Vector2i) -> void:
	var img: Image = _imgs[_side]
	var changes := img.get_pixelv(seed_cell) != paint_color
	if mirror_x and not changes:
		changes = img.get_pixelv(Vector2i(edit_res - 1 - seed_cell.x, seed_cell.y)) != paint_color
	if not changes:
		return
	_snapshot_once()
	_flood_from(seed_cell)
	if mirror_x:
		_flood_from(Vector2i(edit_res - 1 - seed_cell.x, seed_cell.y))
	_dirtys[_side] = true
	_push()

## 4-way flood from `seed_cell` over its contiguous same-colour region. Explicit visited bits (not "did the pixel
## change") so a brush matching the region colour can never loop.
func _flood_from(seed_cell: Vector2i) -> void:
	var img: Image = _imgs[_side]
	var target := img.get_pixelv(seed_cell)  # exact ==: the buffer is one 8-bit-quantised image
	var visited := PackedByteArray()
	visited.resize(edit_res * edit_res)
	var stack: Array[Vector2i] = [seed_cell]
	visited[seed_cell.y * edit_res + seed_cell.x] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		img.set_pixelv(c, paint_color)
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + o
			if n.x < 0 or n.y < 0 or n.x >= edit_res or n.y >= edit_res:
				continue
			var i := n.y * edit_res + n.x
			if visited[i] == 1 or img.get_pixelv(n) != target:
				continue
			visited[i] = 1
			stack.append(n)

# --- sides ------------------------------------------------------------------------------------------------------

## Switch which side (SIDE_FRONT / SIDE_BACK) the canvas edits + shows. A side switch happens between strokes, so it
## just re-points the active buffer and redraws; the combined texture already carries both, so no _push is needed.
func set_side(s: int) -> void:
	var ns := clampi(s, SIDE_FRONT, SIDE_BACK)
	if ns == _side:
		return
	_side = ns
	_last_cell = Vector2i(-1, -1)
	_stroke_snapped = false
	queue_redraw()

func current_side() -> int:
	return _side

# --- undo (per side) --------------------------------------------------------------------------------------------

## Snapshot the active side once per user action (stroke / bucket / fill / reset) so undo() steps whole actions back.
func _snapshot_once() -> void:
	if _stroke_snapped:
		return
	_stroke_snapped = true
	_snapshot()

func _snapshot() -> void:
	_snapshot_side(_side)

func _snapshot_side(side: int) -> void:
	var copy := Image.new()
	copy.copy_from(_imgs[side])
	var stack: Array = _undos[side]
	stack.append({"img": copy, "dirty": _dirtys[side]})
	while stack.size() > MAX_UNDO:
		stack.pop_front()

## Undo applies to the SIDE currently shown (the one you're looking at when you press Ctrl+Z / Undo).
func can_undo() -> bool:
	return not (_undos[_side] as Array).is_empty()

## Step back one action on the active side. Restores that side's dirty flag too, so undoing all the way to a blank
## side (and the other side also blank) drops the "custom shirt" state (the creator un-applies it on the change).
func undo() -> void:
	var stack: Array = _undos[_side]
	if stack.is_empty():
		return
	var snap: Dictionary = stack.pop_back()
	_imgs[_side] = snap["img"]
	_dirtys[_side] = bool(snap["dirty"])
	_last_cell = Vector2i(-1, -1)
	_stroke_snapped = false  # a Ctrl+Z mid-drag consumed this stroke's snapshot; the drag's tail must re-arm one
	_push()

# --- tools + palette hooks --------------------------------------------------------------------------------------

## Select the brush colour (forced opaque — the shirt replaces the albedo). Picking a colour means you want to
## PAINT, so it leaves ERASE and EYEDROP for the brush — but keeps a FILL pick as FILL (still a colour op). The
## EYEDROP tool sets paint_color directly (not through here) so its own sampling doesn't kick it out of the tool.
func set_paint_color(c: Color) -> void:
	paint_color = Color(c.r, c.g, c.b, 1.0)
	if tool == TOOL_ERASE or tool == TOOL_EYEDROP:
		tool = TOOL_PAINT

func set_tool(t: int) -> void:
	tool = clampi(t, TOOL_PAINT, TOOL_EYEDROP)
	queue_redraw()  # the hover preview differs by tool (eyedrop shows a bare cursor, not a paint footprint)

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

## Flood the ACTIVE side with the current brush (or the blank colour while erasing) — a solid-colour side.
func fill_all() -> void:
	_snapshot()
	_imgs[_side].fill(blank_color if tool == TOOL_ERASE else paint_color)
	_dirtys[_side] = true
	_push()

## Wipe the ACTIVE side back to a blank tee AND drop its dirty flag. Snapshots first, so a slip of the Reset button
## is one undo() away from recovered art. A Reset of an already-clean side is a pure no-op (no snapshot, no
## emission): a double-click habit must not push blank entries that make the first Undo "do nothing" or evict the
## real art from the capped stack.
func reset() -> void:
	if not _dirtys[_side]:
		return
	_snapshot()
	_imgs[_side].fill(blank_color)
	_dirtys[_side] = false
	_push()

## Wipe BOTH sides back to a blank tee and drop the custom-shirt state. This is the creation screen's Reset button:
## players expect it to return to the selected base shirt even if front and back were both painted. Each dirty side
## gets its own undo snapshot, so switching to that side and pressing Undo can still recover its art.
func reset_all() -> void:
	var did_reset := false
	for side: int in [SIDE_FRONT, SIDE_BACK]:
		if not _dirtys[side]:
			continue
		_snapshot_side(side)
		_imgs[side].fill(blank_color)
		_dirtys[side] = false
		did_reset = true
	if not did_reset:
		return
	_last_cell = Vector2i(-1, -1)
	_stroke_snapped = false
	_push()

# --- state for the creator / save -------------------------------------------------------------------------------

## Has the player drawn ANYTHING on EITHER side? False -> keep the character's default (base) shirt; the creator
## only applies / emits a custom shirt while this is true.
func is_dirty() -> bool:
	return _dirtys[SIDE_FRONT] or _dirtys[SIDE_BACK]

## The live COMBINED applied texture (front over back, NEAREST-upscaled) to bind as a BodyModelSwap `body_texture`.
## Shared + updated in place, so every stroke on either side shows at once in a material that already references it.
func applied_texture() -> Texture2D:
	return _tex

## Both sides as a single combined PNG (front over back) — the compact form stored in GameState.appearance["shirt"].
func png_bytes() -> PackedByteArray:
	return _combined_edit().save_png_to_buffer()

## Restore a saved shirt. Accepts the COMBINED front/back PNG (edit_res × 2·edit_res) OR a LEGACY single-side square
## PNG (pre-front/back saves), which is put on BOTH sides so an older character keeps its symmetric look. No-op on
## empty / bad bytes. A restore is a load, not an edit — both undo stacks start fresh from it.
func load_png(bytes: PackedByteArray) -> void:
	if not _looks_like_png(bytes):
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	# Detect a combined front/back stack by its 1:2 RATIO (not by matching edit_res) so a save made at a different
	# resolution still splits correctly — matches CharacterAppearanceCatalog._to_combined_shirt's ratio test.
	if h == w * 2:
		var front := img.get_region(Rect2i(0, 0, w, w))
		var back := img.get_region(Rect2i(0, w, w, w))
		if w != edit_res:
			front.resize(edit_res, edit_res, Image.INTERPOLATE_NEAREST)
			back.resize(edit_res, edit_res, Image.INTERPOLATE_NEAREST)
		_imgs[SIDE_FRONT] = front
		_imgs[SIDE_BACK] = back
	else:
		# Legacy single-side design (or an odd size): fit to the edit grid and mirror it onto BOTH sides.
		if w != edit_res or h != edit_res:
			img.resize(edit_res, edit_res, Image.INTERPOLATE_NEAREST)
		_imgs[SIDE_FRONT] = img
		var back := Image.new()
		back.copy_from(img)
		_imgs[SIDE_BACK] = back
	_dirtys[SIDE_FRONT] = true
	_dirtys[SIDE_BACK] = true
	_undos = [[], []]
	if _tex != null:
		_tex.update(_combined_upscaled())
	else:
		_tex = ImageTexture.create_from_image(_combined_upscaled())
	queue_redraw()

static func _looks_like_png(bytes: PackedByteArray) -> bool:
	if bytes.size() < 45:
		return false
	if bytes[0] != 0x89 or bytes[1] != 0x50 or bytes[2] != 0x4e or bytes[3] != 0x47:
		return false
	if bytes[4] != 0x0d or bytes[5] != 0x0a or bytes[6] != 0x1a or bytes[7] != 0x0a:
		return false
	var pos := 8
	var saw_ihdr := false
	var saw_idat := false
	while pos + 12 <= bytes.size():
		var chunk_len := _png_u32(bytes, pos)
		var next := pos + 8 + chunk_len + 4
		if next > bytes.size():
			return false
		if not saw_ihdr:
			if not _png_chunk_is(bytes, pos, 0x49, 0x48, 0x44, 0x52) or chunk_len != 13:
				return false
			saw_ihdr = true
		if _png_chunk_is(bytes, pos, 0x49, 0x44, 0x41, 0x54):
			saw_idat = true
		if _png_chunk_is(bytes, pos, 0x49, 0x45, 0x4e, 0x44):
			return saw_ihdr and saw_idat and chunk_len == 0 and next == bytes.size()
		pos = next
	return false

static func _png_u32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]

static func _png_chunk_is(bytes: PackedByteArray, offset: int, a: int, b: int, c: int, d: int) -> bool:
	return bytes[offset + 4] == a and bytes[offset + 5] == b and bytes[offset + 6] == c and bytes[offset + 7] == d

# --- drawing ----------------------------------------------------------------------------------------------------

## The square draw area, centred in the widget (keeps cells square even if the Control isn't a perfect square).
func _canvas_rect() -> Rect2:
	var s := minf(size.x, size.y)
	return Rect2(((size - Vector2(s, s)) * 0.5).floor(), Vector2(s, s))

func _draw() -> void:
	var area := _canvas_rect()
	if area.size.x <= 0.0:
		return
	# Show ONLY the active side by blitting its half of the combined texture (top = front, bottom = back).
	if _tex != null:
		var full := _tex.get_size()
		var half_h := full.y * 0.5
		var src := Rect2(0.0, 0.0, full.x, half_h) if _side == SIDE_FRONT else Rect2(0.0, half_h, full.x, half_h)
		draw_texture_rect_region(_tex, area, src)
	# Faint grid so the (possibly blank) cells read; skipped once cells shrink too small to be useful.
	var cell := area.size.x / float(edit_res)
	if cell >= 3.0:
		for i in range(edit_res + 1):
			var x := area.position.x + i * cell
			var y := area.position.y + i * cell
			draw_line(Vector2(x, area.position.y), Vector2(x, area.position.y + area.size.y), grid_color, 1.0)
			draw_line(Vector2(area.position.x, y), Vector2(area.position.x + area.size.x, y), grid_color, 1.0)
	# Hover highlight. EYEDROP shows a bare single-cell cursor (it samples, doesn't stamp); the paint/erase tools
	# preview the brush FOOTPRINT (size + colour), plus the mirrored twin while mirroring, so the size is legible.
	if _hover_cell.x >= 0 and cell >= 3.0:
		if tool == TOOL_EYEDROP:
			draw_rect(Rect2(area.position + Vector2(_hover_cell) * cell, Vector2(cell, cell)), Color(1, 1, 1, 0.9), false, 1.0)
		else:
			var col := blank_color if tool == TOOL_ERASE else paint_color
			_draw_brush_preview(area, cell, _hover_cell, col, 0.45, true)
			var mx := edit_res - 1 - _hover_cell.x
			if mirror_x and mx != _hover_cell.x:
				_draw_brush_preview(area, cell, Vector2i(mx, _hover_cell.y), col, 0.25, false, true)
	draw_rect(area, Color(1, 1, 1, 0.25), false, 1.0)  # a light frame around the canvas

## Fill (and optionally outline) the brush footprint at `center`, clamped to the canvas, for the hover preview. `mirror`
## flips the even-brush bias to match the mirrored twin's stamp (see _set_cell), so the preview shows what will paint.
func _draw_brush_preview(area: Rect2, cell: float, center: Vector2i, col: Color, alpha: float, outline: bool, mirror: bool = false) -> void:
	var start := center - Vector2i(_brush_start_offset_x(mirror), _brush_start_offset_y())
	var lo := Vector2i(maxi(0, start.x), maxi(0, start.y))
	var hi := Vector2i(mini(edit_res, start.x + brush_size), mini(edit_res, start.y + brush_size))
	if lo.x >= hi.x or lo.y >= hi.y:
		return
	var r := Rect2(area.position + Vector2(lo) * cell, Vector2(hi - lo) * cell)
	draw_rect(r, Color(col.r, col.g, col.b, alpha))
	if outline:
		draw_rect(r, Color(1, 1, 1, 0.9), false, 1.0)
