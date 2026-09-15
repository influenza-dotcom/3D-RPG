extends GutTest

## GridOverlay (scripts/ui/grid_overlay.gd) — the TOP layer of GridInventoryView. The tiles are child nodes and so
## paint over the view's own _draw; the drag preview + hover ring therefore live on this child, kept LAST, and it
## just delegates _draw back to host.draw_overlay(self). Three things keep that working and are pinned here:
##   • it is mouse-transparent (the view owns every click — an overlay that stopped input would eat the drag);
##   • a hostless overlay draws nothing (the view's tests build views off-tree where _overlay stays null; and a
##     GridOverlay.new() with no host must never null-deref);
##   • the view's _ready wires one: last child, host == the view, anchored full-rect over the tiles.
## In-tree via add_child_autofree (a Control's _ready is what sets the mouse filter); no rendering is asserted —
## headless has no renderer, and draw_overlay on an idle view issues no draw calls, so calling it outside _draw
## is safe.

const GridOverlay = preload("res://scripts/ui/grid_overlay.gd")


func test_defaults_to_no_host() -> void:
	var o := GridOverlay.new()
	assert_null(o.host, "an overlay is born hostless; the view assigns itself")
	o.free()

func test_ready_makes_it_mouse_transparent() -> void:
	var o := GridOverlay.new()
	add_child_autofree(o)
	assert_eq(o.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the overlay must never intercept the grid's input")

func test_draw_without_a_host_is_a_safe_no_op() -> void:
	var o := GridOverlay.new()
	add_child_autofree(o)
	o._draw()
	assert_null(o.host, "a hostless _draw returns without touching anything (no null deref)")

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

func test_draw_delegates_to_the_hosts_draw_overlay_when_idle() -> void:
	# An idle view (no drag, no hover, no incoming drop) paints nothing, so the delegation can run outside
	# NOTIFICATION_DRAW without an engine error — which is exactly what this proves: _draw reaches draw_overlay
	# with the overlay as the canvas and comes back clean.
	var view := GridInventoryView.new()
	add_child_autofree(view)
	var o: Control = view._overlay
	assert_not_null(o, "fixture: the view built its overlay")
	o._draw()
	assert_eq(o.host, view, "the delegation ran against the view (no error, host intact)")

func test_overlay_stays_last_after_a_refresh() -> void:
	# _sync_tiles adds GridTile children per stack and then move_child()s the overlay to the end — refresh() on
	# a bound bag must leave the overlay on top.
	var view := GridInventoryView.new()
	add_child_autofree(view)
	var inv: CharacterInventory = autofree(CharacterInventory.new())
	view.bind(inv)
	var last := view.get_child(view.get_child_count() - 1)
	assert_eq(last, view._overlay, "after bind()/refresh() the overlay is still the last child")
