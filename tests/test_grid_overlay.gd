extends GutTest

## GridOverlay (scripts/ui/grid_overlay.gd) — the TOP layer of GridInventoryView. The tiles are child nodes and so
## paint over the view's own _draw; the drag preview + hover ring therefore live on this child, kept LAST, and it
## just delegates _draw back to host.draw_overlay(self). What keeps that working, pinned here:
##   • _draw hands the OVERLAY ITSELF to host.draw_overlay (the preview must paint on the layer above the tiles,
##     not on the host underneath them) — observed through a spy host that records every draw_overlay call;
##   • a hostless overlay draws nothing and raises no error (the view's other tests build views off-tree where
##     _overlay stays null, and a GridOverlay.new() with no host must never null-deref);
##   • it is mouse-transparent after _ready (the view owns every click — an overlay that stopped input would eat
##     the drag);
##   • the view's _ready wires one (last child, host == the view, full-rect), and a refresh that ADDS tiles moves
##     it back to the end so it still paints above every tile.
## In-tree via add_child_autofree (a Control's _ready is what sets the mouse filter); no rendering is asserted —
## headless has no renderer, and the spy's draw_overlay issues no draw calls, so calling _draw directly is safe.

const GridOverlay = preload("res://scripts/ui/grid_overlay.gd")
const GridTile = preload("res://scripts/ui/grid_tile.gd")


## A real GridInventoryView (so it satisfies the overlay's typed `host`) whose draw_overlay only RECORDS the
## canvas it was handed, so a test can see whether — and onto which canvas — the overlay delegated its paint.
class SpyView extends GridInventoryView:
	var canvases: Array = []

	func draw_overlay(canvas: CanvasItem) -> void:
		canvases.append(canvas)


## A gridded 4x4 bag holding `n` distinct 1x1 stacks (distinct Item instances never merge into one stack), so a
## bound view has to create one GridTile per stack.
func _bag_with_stacks(n: int) -> CharacterInventory:
	var inv: CharacterInventory = autofree(CharacterInventory.new())
	inv.enable_grid(4, 4)
	for i in range(n):
		inv.add(Item.new(), 1)
	return inv


func _tile_count(view: Control) -> int:
	var tiles := 0
	for c in view.get_children():
		if c.get_script() == GridTile:
			tiles += 1
	return tiles


func test_ready_makes_it_mouse_transparent() -> void:
	var o := GridOverlay.new()
	# Control: before _ready the overlay still has a Control's click-eating default, so the flip below is _ready's doing.
	assert_ne(o.mouse_filter, Control.MOUSE_FILTER_IGNORE, "fixture: a not-yet-ready overlay still intercepts the mouse")
	add_child_autofree(o)
	assert_eq(o.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the overlay must never intercept the grid's input (it would eat the drag)")

func test_draw_hands_the_overlay_itself_to_the_hosts_draw_overlay() -> void:
	var spy: SpyView = autofree(SpyView.new())  # off-tree: its own _ready never builds a second overlay
	var o := GridOverlay.new()
	add_child_autofree(o)
	o.host = spy
	o._draw()
	assert_eq(spy.canvases.size(), 1, "one overlay _draw must paint the drag preview / hover ring exactly once through the host")
	if spy.canvases.size() == 1:
		assert_true(spy.canvases[0] == o,
				"the host must paint ON the overlay (the layer above the tiles) — any other canvas hides the preview under the items")

func test_a_hostless_overlay_draws_nothing_and_raises_no_error() -> void:
	var spy: SpyView = autofree(SpyView.new())
	var o := GridOverlay.new()
	add_child_autofree(o)
	# Control: while hosted, the same overlay gets past the guard and paints through the host.
	o.host = spy
	o._draw()
	assert_eq(spy.canvases.size(), 1, "control: a hosted overlay paints through its host")
	# Detach it: the next draw must neither reach the old host nor dereference the null host.
	o.host = null
	o._draw()
	assert_eq(spy.canvases.size(), 1, "an unhosted overlay must not keep painting into a view it no longer belongs to")
	assert_engine_error_count(0, "a hostless _draw must return cleanly — a null-host call would be a script error every frame")

func test_the_view_wires_the_overlay_as_its_last_full_rect_child() -> void:
	var view := GridInventoryView.new()
	add_child_autofree(view)
	var last := view.get_child(view.get_child_count() - 1)
	assert_true(last.get_script() == GridOverlay, "the overlay is the view's LAST child so it paints above every tile")
	assert_eq(last.host, view, "the overlay's host is the view it paints for")
	assert_eq(view._overlay, last, "the view keeps the same node in _overlay (it move_child()s it back to the end after a tile sync)")
	assert_eq(last.anchor_right, 1.0, "anchored full-rect (right)")
	assert_eq(last.anchor_bottom, 1.0, "anchored full-rect (bottom)")
	assert_eq(last.offset_left, 0.0, "no offset — the overlay shares the view's coordinate space")

func test_overlay_stays_above_tiles_added_by_a_bind_and_a_later_refresh() -> void:
	# The overlay is added in _ready, BEFORE any tile exists; _sync_tiles then add_child()s one GridTile per stack
	# (which lands after the overlay) and must move the overlay back to the end each time.
	var view := GridInventoryView.new()
	add_child_autofree(view)
	var inv := _bag_with_stacks(2)
	view.bind(inv)
	assert_eq(_tile_count(view), 2, "fixture: binding a bag with two stacks created two tiles after the overlay")
	assert_eq(view.get_child(view.get_child_count() - 1), view._overlay,
			"after bind() the overlay must be the last child, or the tiles paint over the drag preview / hover ring")
	# A stack arriving later (loot taken, item picked up) appends a NEW tile on refresh — the overlay must re-surface.
	inv.add(Item.new(), 1)
	view.refresh()
	assert_eq(_tile_count(view), 3, "fixture: the refresh created a tile for the new stack")
	assert_eq(view.get_child(view.get_child_count() - 1), view._overlay,
			"after refresh() adds a tile the overlay must still be the last child")
