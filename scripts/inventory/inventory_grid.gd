class_name InventoryGrid
extends RefCounted

## Pure, Node-free SPATIAL placement model for a Tetris-style inventory — the same "logic is a RefCounted so
## it's GUT-testable off-tree" idiom as RadioPlaybackState / MusicPlaylist / SearchState. It owns ONLY where
## things sit on a cols×rows grid; it knows nothing about Item / stacks / weight (CharacterInventory layers it
## on in a later slice). Each PLACEMENT is an opaque `key` (the caller's id for the thing) occupying a
## width×height footprint at a top-left cell (x, y). No Node, no resources, no I/O → it runs headless.
##
## Footprints are pre-rotated by the caller: to place an item rotated, pass swapped (h, w) — the grid just
## stores the footprint it's given. find_free_slot() optionally tries the rotated footprint for you.

var cols: int = 0
var rows: int = 0

var _cells: Array = []          ## size cols*rows; each holds the occupying placement's key, or null when empty
var _placements: Dictionary = {}  ## key -> {x, y, w, h}

## (Re)size the grid to cols×rows and clear all placements.
func configure(p_cols: int, p_rows: int) -> void:
	cols = maxi(0, p_cols)
	rows = maxi(0, p_rows)
	clear()

## Drop every placement (the grid keeps its dimensions).
func clear() -> void:
	_placements.clear()
	_cells = []
	_cells.resize(cols * rows)  # resize fills new slots with null

func _idx(x: int, y: int) -> int:
	return y * cols + x

## True if a w×h footprint at (x, y) lies entirely on the grid (and w/h are positive).
func in_bounds(x: int, y: int, w: int, h: int) -> bool:
	return w >= 1 and h >= 1 and x >= 0 and y >= 0 and x + w <= cols and y + h <= rows

## Can a w×h footprint sit at (x, y)? In bounds AND every covered cell is empty — except cells owned by
## `ignore_key` (pass the moving item's own key so a placement can slide onto cells it already occupies).
func can_place(x: int, y: int, w: int, h: int, ignore_key = null) -> bool:
	if not in_bounds(x, y, w, h):
		return false
	for cy in range(y, y + h):
		for cx in range(x, x + w):
			var occ = _cells[_idx(cx, cy)]
			if occ != null and occ != ignore_key:
				return false
	return true

## Place (or MOVE) `key` as a w×h footprint at (x, y). On a move the old footprint is freed first (so it can
## overlap its own former cells); if the destination doesn't fit, the old placement is restored and this
## returns false, leaving the grid unchanged. Returns true on success.
func place(key, x: int, y: int, w: int, h: int) -> bool:
	var had: bool = _placements.has(key)
	var prev: Dictionary = _placements.get(key, {})
	if had:
		_clear_cells(key)
	if not can_place(x, y, w, h):
		if had:
			_fill_cells(key, prev["x"], prev["y"], prev["w"], prev["h"])  # move failed — put it back
		return false
	_placements[key] = {"x": x, "y": y, "w": w, "h": h}
	_fill_cells(key, x, y, w, h)
	return true

## Remove `key`'s placement, freeing its cells. Returns false if it wasn't placed.
func remove(key) -> bool:
	if not _placements.has(key):
		return false
	_clear_cells(key)
	_placements.erase(key)
	return true

## A copy of `key`'s placement ({x, y, w, h}), or an empty Dictionary if it isn't placed.
func placement_of(key) -> Dictionary:
	return _placements[key].duplicate() if _placements.has(key) else {}

## Is `key` currently placed?
func has_key(key) -> bool:
	return _placements.has(key)

## Is the single cell (x, y) empty (and on the grid)?
func is_free(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return false
	return _cells[_idx(x, y)] == null

## The first cell (scanning row-major, top-left first) where a w×h footprint fits. With allow_rotate, also
## tries the rotated h×w footprint at each cell. Returns {found, x, y, w, h, rotated} — w/h are the chosen
## (possibly swapped) footprint. {found = false} when nothing fits anywhere.
func find_free_slot(w: int, h: int, allow_rotate: bool = false) -> Dictionary:
	for y in range(rows):
		for x in range(cols):
			if can_place(x, y, w, h):
				return {"found": true, "x": x, "y": y, "w": w, "h": h, "rotated": false}
			if allow_rotate and w != h and can_place(x, y, h, w):
				return {"found": true, "x": x, "y": y, "w": h, "h": w, "rotated": true}
	return {"found": false}

## How many placements are currently on the grid.
func count() -> int:
	return _placements.size()

func _fill_cells(key, x: int, y: int, w: int, h: int) -> void:
	for cy in range(y, y + h):
		for cx in range(x, x + w):
			_cells[_idx(cx, cy)] = key

func _clear_cells(key) -> void:
	var p: Dictionary = _placements.get(key, {})
	if p.is_empty():
		return
	for cy in range(p["y"], p["y"] + p["h"]):
		for cx in range(p["x"], p["x"] + p["w"]):
			if _cells[_idx(cx, cy)] == key:
				_cells[_idx(cx, cy)] = null
