class_name GridInventoryView
extends Control

## A Tetris-style GRID view of one CharacterInventory (inventory T3) — items drawn as footprint-sized rectangles
## at their (x,y) grid placement, DRAG to move, the RotateItem key (default R) to rotate the held item, click to
## activate (equip / use), right-click to drop. Pure code-built + self-contained, so the same component renders
## BOTH the player's backpack (InventoryScreen, T3) and, later, a looted container/corpse side-by-side (T4).
##
## Each placed stack is a styled child GridTile (a tinted panel + its item's LIVE 3D mesh via ItemMeshView, or a
## category glyph when it has none, + a count badge). The view itself draws only the empty-cell backdrop; the drag
## preview + hover ring are painted on a GridOverlay child kept ABOVE the tiles. ALL input is handled at the VIEW
## level (mouse_filter STOP; tiles + overlay are mouse-transparent), which keeps the drag clean — nothing under the
## cursor steals the motion events. It reads the bag through the T2 API (placed_contents -> [{item,count,key,x,y,
## w,h}], can_place_stack, move_stack, grid_cols/rows) and never mutates the bag except via move_stack on a valid
## drop. Actions go OUT as signals so the host wires them to the player calls (equip_item / use_consumable /
## drop_item) — the view stays player-agnostic + reusable (InventoryScreen now, the loot screen's two grids in T4).
##
## Cells size to the available width (the game runs at a narrow 396px viewport), so the grid stays on-screen.

## Click on a tile (no drag): the host equips a weapon or uses a consumable (routes by item type).
signal activate_requested(item: Item)
## Right-click on a tile: the host drops the whole stack to the world.
signal drop_requested(item: Item)
## The hovered tile changed (item, or null when the cursor leaves the grid) — the host shows the detail line.
signal hover_changed(item: Item)

const MIN_CELL := 26   ## floor on cell pixel size — bigger now that each tile shows a 3D mesh, not text
const MAX_CELL := 56   ## cap so a near-empty grid doesn't render giant cells
const DRAG_THRESHOLD := 6.0  ## px the cursor must move past a press before it counts as a drag (vs a click)
const GridTile := preload("res://scripts/ui/grid_tile.gd")        ## one styled stack tile (mesh + chrome)
const GridOverlay := preload("res://scripts/ui/grid_overlay.gd")  ## top layer for the drag preview + hover ring

var _inv: CharacterInventory = null
var _rows: Array = []          ## cached placed_contents() for this frame's render + hit-tests
var _cell_px: int = MIN_CELL
var _tiles: Dictionary = {}    ## stack key -> GridTile child (reused across refreshes so meshes aren't rebuilt)
var _overlay: Control = null   ## top layer (drag preview + hover ring), kept above the tile children

# --- drag state ---
var _pressed_key: int = -1     ## stack under the mouse-down (pre-threshold; -1 = none)
var _press_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_key: int = -1
var _drag_w: int = 1
var _drag_h: int = 1
var _grab_dx: int = 0          ## which sub-cell of the footprint was grabbed (so it tracks the cursor naturally)
var _grab_dy: int = 0
var _drag_cell: Vector2i = Vector2i.ZERO  ## clamped target top-left
var _drag_valid: bool = false

var _hovered_item: Item = null  ## the tile under the cursor when NOT dragging (the hotbar + detail read this)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # the view handles all mouse itself; nothing falls through
	focus_mode = Control.FOCUS_NONE           # mouse-driven menu: never grab keyboard focus / Tab-cycle
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_on_resized)
	mouse_exited.connect(_on_mouse_exited)
	# Top layer for the drag preview / hover ring (the item tiles are child nodes, so they draw over the view's
	# own _draw — the overlay, kept last, paints above them).
	_overlay = GridOverlay.new()
	_overlay.host = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

## Point the view at a backpack and render it. Safe to call again to rebind (T4 reuse). A rebind/unbind (incl.
## bind(null) on the loot screen's close) cancels any in-progress drag, so a later motion/rotate can't deref a
## now-null / swapped inventory.
func bind(inv: CharacterInventory) -> void:
	_cancel_drag()
	_inv = inv
	refresh()

## Abandon any press / drag in progress (on rebind). Leaves the hover alone — a _rebuild mid-hover must not drop
## the item the hotbar is about to assign; the hover re-evaluates on the next motion / mouse_exited anyway.
func _cancel_drag() -> void:
	_end_drag()
	_pressed_key = -1

## If the view is hidden (the screen closed — possibly on the interact key mid-drag), drop the drag AND the hover
## so a stray Rotate keypress afterward can't act on a stale/null inventory and no stale hover lingers.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_cancel_drag()
		_set_hovered(null)
		queue_redraw()

## Re-read the bag and relayout (the host calls this on inventory.changed).
func refresh() -> void:
	_rows = _inv.placed_contents() if _inv != null else []
	_recompute_cell()
	_sync_tiles()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()

## The item under the cursor (the hotbar polls this through the host while the bag is open). Null while dragging
## or when nothing is hovered.
func hovered_item() -> Item:
	return _hovered_item

# ---------------------------------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------------------------------

func _on_resized() -> void:
	_recompute_cell()
	_sync_tiles()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()

## Size cells to fit the view's width across all columns (clamped), and reserve the matching height.
func _recompute_cell() -> void:
	var cols := _cols()
	if cols <= 0:
		_cell_px = MIN_CELL
		custom_minimum_size.y = 0
		return
	_cell_px = clampi(int(size.x / cols), MIN_CELL, MAX_CELL)
	custom_minimum_size.y = _cell_px * _rows_count()

func _cols() -> int:
	return _inv.grid_cols() if _inv != null else 0

func _rows_count() -> int:
	return _inv.grid_rows() if _inv != null else 0

## Left edge of the grid (centred horizontally in the view's width).
func _origin_x() -> float:
	return maxf(0.0, (size.x - _cols() * _cell_px) * 0.5)

## Grid cell under a local position, or (-1,-1) if outside the grid rect.
func cell_from_local(pos: Vector2) -> Vector2i:
	var lx := pos.x - _origin_x()
	if lx < 0.0 or pos.y < 0.0 or _cell_px <= 0:
		return Vector2i(-1, -1)
	var cx := int(lx / _cell_px)
	var cy := int(pos.y / _cell_px)
	if cx < 0 or cy < 0 or cx >= _cols() or cy >= _rows_count():
		return Vector2i(-1, -1)
	return Vector2i(cx, cy)

## The stack key whose footprint covers `cell`, or -1. (Reads the cached _rows.)
func _key_at_cell(cell: Vector2i) -> int:
	if cell.x < 0:
		return -1
	for row in _rows:
		var rx := int(row["x"])
		if rx < 0:
			continue  # unplaced stack — not on the grid
		if cell.x >= rx and cell.x < rx + int(row["w"]) and cell.y >= int(row["y"]) and cell.y < int(row["y"]) + int(row["h"]):
			return int(row["key"])
	return -1

func _row_for_key(key: int) -> Dictionary:
	for row in _rows:
		if int(row["key"]) == key:
			return row
	return {}

# ---------------------------------------------------------------------------------------------------
# Input — mouse (drag / click / drop) at the view level; keys (rotate / cancel) via _input while dragging
# ---------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if _inv == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_press(mb.position)
			else:
				_release(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var key := _key_at_cell(cell_from_local(mb.position))
			if key >= 0:
				var row := _row_for_key(key)
				if not row.is_empty():
					drop_requested.emit(row["item"])
			accept_event()
	elif event is InputEventMouseMotion:
		_on_motion((event as InputEventMouseMotion).position)

## Mouse-down on a tile: remember it, but don't drag until the cursor moves past the threshold (so a still click
## activates instead of micro-dragging).
func _begin_press(pos: Vector2) -> void:
	_press_pos = pos
	_pressed_key = _key_at_cell(cell_from_local(pos))

func _release(pos: Vector2) -> void:
	if _dragging:
		if _drag_valid:
			_inv.move_stack(_drag_key, _drag_cell.x, _drag_cell.y, _drag_w, _drag_h)  # commit (fires changed)
		_end_drag()  # clear _dragging BEFORE refreshing so the settled tile draws normally, not as the skipped drag
		refresh()    # re-read placements + redraw (an invalid drop just snaps the tile back to its unchanged spot)
	elif _pressed_key >= 0:
		# A click without a drag -> activate (equip / use). hit-test again at release in case the cursor slid off.
		if _key_at_cell(cell_from_local(pos)) == _pressed_key:
			var row := _row_for_key(_pressed_key)
			if not row.is_empty():
				activate_requested.emit(row["item"])
	_pressed_key = -1

func _on_motion(pos: Vector2) -> void:
	if _pressed_key >= 0 and not _dragging and pos.distance_to(_press_pos) > DRAG_THRESHOLD:
		_start_drag(pos)
	if _dragging:
		_update_drag_target(pos)
	else:
		_update_hover(pos)

func _start_drag(pos: Vector2) -> void:
	var row := _row_for_key(_pressed_key)
	if row.is_empty() or int(row["x"]) < 0:
		_pressed_key = -1
		return
	_dragging = true
	_drag_key = _pressed_key
	_drag_w = int(row["w"])
	_drag_h = int(row["h"])
	var grab := cell_from_local(pos)
	_grab_dx = clampi(grab.x - int(row["x"]), 0, _drag_w - 1)
	_grab_dy = clampi(grab.y - int(row["y"]), 0, _drag_h - 1)
	if _tiles.has(_drag_key) and is_instance_valid(_tiles[_drag_key]):
		_tiles[_drag_key].visible = false  # the dragged tile is shown as the moving preview instead
	_set_hovered(null)  # not hovering while dragging
	_update_drag_target(pos)

## Recompute the clamped target top-left + validity from the cursor (used on motion AND after a rotate).
func _update_drag_target(pos: Vector2) -> void:
	if _inv == null:
		return
	var cell := cell_from_local(pos)
	if cell.x < 0:
		_drag_valid = false  # cursor off the grid -> can't drop here
		if _overlay != null:
			_overlay.queue_redraw()
		return
	var tx := clampi(cell.x - _grab_dx, 0, maxi(0, _cols() - _drag_w))
	var ty := clampi(cell.y - _grab_dy, 0, maxi(0, _rows_count() - _drag_h))
	_drag_cell = Vector2i(tx, ty)
	_drag_valid = _inv.can_place_stack(_drag_key, tx, ty, _drag_w, _drag_h)
	if _overlay != null:
		_overlay.queue_redraw()

func _update_hover(pos: Vector2) -> void:
	var key := _key_at_cell(cell_from_local(pos))
	if key < 0:
		_set_hovered(null)
		return
	var row := _row_for_key(key)
	_set_hovered(row["item"] if not row.is_empty() else null)

func _set_hovered(item: Item) -> void:
	if item == _hovered_item:
		return
	_hovered_item = item
	hover_changed.emit(item)
	if _overlay != null:
		_overlay.queue_redraw()  # the hover ring follows the hovered tile

func _on_mouse_exited() -> void:
	if not _dragging:
		_set_hovered(null)

func _end_drag() -> void:
	if _drag_key >= 0 and _tiles.has(_drag_key) and is_instance_valid(_tiles[_drag_key]):
		_tiles[_drag_key].visible = true  # restore the tile we hid for the drag (refresh re-positions it)
	_dragging = false
	_drag_key = -1
	if _overlay != null:
		_overlay.queue_redraw()

## Rotate / cancel while dragging — read in _input (beats the screen's _unhandled_input) and gated on _dragging,
## so it's inert any other time. Rotating swaps the held footprint and re-validates against the same cursor cell.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event.is_action_pressed(InputManager.action_rotate_item):
		_rotate_drag()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		_end_drag()  # Esc cancels the drag (rather than closing the whole screen) — snap back
		_set_hovered(null)  # dragging cleared the hover; keep it clear until the cursor moves again
		queue_redraw()
		get_viewport().set_input_as_handled()

## Rotate the held footprint IN PLACE — pivot about its current top-left (clamped so the rotated footprint still
## fits), so the preview never teleports out from under the cursor. Then re-sync the grab offset to the cursor so
## the NEXT move stays smooth (skipped when the cursor is off the grid, so an off-grid rotate stays consistent).
func _rotate_drag() -> void:
	if _inv == null:
		return
	var t := _drag_w
	_drag_w = _drag_h
	_drag_h = t
	var tx := clampi(_drag_cell.x, 0, maxi(0, _cols() - _drag_w))
	var ty := clampi(_drag_cell.y, 0, maxi(0, _rows_count() - _drag_h))
	_drag_cell = Vector2i(tx, ty)
	_drag_valid = _inv.can_place_stack(_drag_key, tx, ty, _drag_w, _drag_h)
	var cur := cell_from_local(get_local_mouse_position())
	if cur.x >= 0:
		_grab_dx = clampi(cur.x - tx, 0, _drag_w - 1)
		_grab_dy = clampi(cur.y - ty, 0, _drag_h - 1)
	if _overlay != null:
		_overlay.queue_redraw()

# ---------------------------------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------------------------------

## The view draws only the empty-cell BACKDROP (a subtle grid of slots). The item tiles are child GridTile nodes
## (so they show live 3D meshes); the drag preview + hover ring are on the overlay child, above the tiles.
func _draw() -> void:
	var cols := _cols()
	var rows := _rows_count()
	if cols <= 0 or rows <= 0:
		return
	var ox := _origin_x()
	var cell := _cell_px
	var w := float(cols * cell)
	var h := float(rows * cell)
	var slot := MenuStyle.dim_color()
	# One quiet backing panel + thin gridlines + an outer border — a clean grid, not 80 separate boxes.
	draw_rect(Rect2(ox, 0.0, w, h), Color(slot.r, slot.g, slot.b, 0.05), true)
	var line := Color(slot.r, slot.g, slot.b, 0.16)
	for cx in range(cols + 1):
		draw_line(Vector2(ox + cx * cell, 0.0), Vector2(ox + cx * cell, h), line, 1.0)
	for cy in range(rows + 1):
		draw_line(Vector2(ox, cy * cell), Vector2(ox + w, cy * cell), line, 1.0)
	draw_rect(Rect2(ox, 0.0, w, h), Color(slot.r, slot.g, slot.b, 0.45), false, 1.0)

## Create / reuse / position a GridTile per placed stack, and free tiles whose stack is gone. Keyed by stack key
## so a move just repositions the same tile (its mesh isn't rebuilt). The overlay is kept as the last child.
func _sync_tiles() -> void:
	var ox := _origin_x()
	var cell := _cell_px
	var seen := {}
	for row in _rows:
		if int(row["x"]) < 0:
			continue  # an unplaced stack has no tile
		var key := int(row["key"])
		seen[key] = true
		var tile: Control = _tiles.get(key)
		if tile == null or not is_instance_valid(tile):
			tile = GridTile.new()
			add_child(tile)
			_tiles[key] = tile
		tile.position = Vector2(ox + int(row["x"]) * cell + 1.0, int(row["y"]) * cell + 1.0)
		tile.size = Vector2(int(row["w"]) * cell - 2.0, int(row["h"]) * cell - 2.0)
		tile.set_data(row["item"], int(row["count"]), _inv != null and row["item"] == _inv.equipped_item)
		tile.visible = not (_dragging and key == _drag_key)
	for key in _tiles.keys():
		if not seen.has(key):
			if is_instance_valid(_tiles[key]):
				_tiles[key].queue_free()
			_tiles.erase(key)
	if _overlay != null:
		move_child(_overlay, -1)  # keep the preview/hover layer above every tile

## Painted by the GridOverlay child (above the tiles): the drag preview at the clamped target, and a subtle ring
## around the hovered tile. `canvas` shares the view's coordinate space (the overlay is anchored full-rect).
func draw_overlay(canvas: CanvasItem) -> void:
	var cell := _cell_px
	var ox := _origin_x()
	if _dragging:
		var col := MenuStyle.accent() if _drag_valid else MenuStyle.danger()
		var rect := Rect2(ox + _drag_cell.x * cell + 1.0, _drag_cell.y * cell + 1.0, _drag_w * cell - 2.0, _drag_h * cell - 2.0)
		canvas.draw_rect(rect, Color(col.r, col.g, col.b, 0.28), true)
		canvas.draw_rect(rect, col, false, 2.0)
	elif _hovered_item != null:
		for row in _rows:
			if row["item"] == _hovered_item and int(row["x"]) >= 0:
				var hr := Rect2(ox + int(row["x"]) * cell + 1.0, int(row["y"]) * cell + 1.0, int(row["w"]) * cell - 2.0, int(row["h"]) * cell - 2.0)
				canvas.draw_rect(hr, Color(1.0, 1.0, 1.0, 0.85), false, 1.5)
				break
