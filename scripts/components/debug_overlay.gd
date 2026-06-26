class_name DebugOverlay
extends CanvasLayer

## Drop-in RUNTIME debug HUD: live perf + content stats with rolling line graphs (#10 profiler + #12 graphs). Drop
## it into game.tscn (or any scene) and press `toggle_key` (F3 by default) while playing to show/hide it. READ-ONLY:
## it only samples Engine / Performance / group counts and draws an overlay — it never touches gameplay. The graph
## math (push_capped / graph_points) is pure + unit-tested; the live sampling + draw are play-verified.

@export var toggle_key: Key = KEY_F3
@export var start_visible: bool = false
@export var sample_interval: float = 0.25   ## seconds between samples (text + a new graph point)
@export_range(8, 600) var history: int = 120  ## samples kept per graph series (the graph's width in points)

var _text: Label = null
var _graph: _Graph = null
var _t: float = 0.0
var _fps := PackedFloat32Array()
var _frame_ms := PackedFloat32Array()


func _ready() -> void:
	layer = 128  # above the game HUD
	visible = start_visible
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.modulate = Color(1, 1, 1, 0.92)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a debug overlay must never eat clicks (project convention, cf. player_hud)
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(190, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 12)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	_graph = _Graph.new()
	_graph.custom_minimum_size = Vector2(190, 80)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_graph)
	_text.text = "Debug overlay"


## Toggle on the configured key (a dev key, not a rebindable action). Ignores key echoes.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == toggle_key:
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = sample_interval
	var fps := Engine.get_frames_per_second()
	var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var mem_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var npcs := get_tree().get_nodes_in_group(Groups.NPC).size() if is_inside_tree() else 0
	_text.text = "FPS %d   (%.1f ms)\nDraw calls %d\nStatic mem %.1f MB\nNodes %d\nNPCs %d" % [fps, frame_ms, draws, mem_mb, nodes, npcs]
	_fps = push_capped(_fps, float(fps), history)
	_frame_ms = push_capped(_frame_ms, frame_ms, history)
	_graph.fps = _fps
	_graph.frame_ms = _frame_ms
	_graph.queue_redraw()


# --- pure helpers (unit-tested) --------------------------------------------------------------------------------

## Append `v` to `buf` and keep only the last `cap` samples (a rolling window). Returns the new array (PackedArrays
## are value types, so callers reassign). Pure.
static func push_capped(buf: PackedFloat32Array, v: float, cap: int) -> PackedFloat32Array:
	buf.append(v)
	var n := maxi(1, cap)
	if buf.size() > n:
		buf = buf.slice(buf.size() - n)
	return buf


## Map `samples` to polyline points inside `rect`: x spread left->right across the samples, y mapping the value
## range [vmin, vmax] to bottom->top (a higher value draws higher). Clamped to the rect vertically. Pure.
static func graph_points(samples: PackedFloat32Array, rect: Rect2, vmin: float, vmax: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := samples.size()
	if n == 0:
		return pts
	var span := maxf(0.0001, vmax - vmin)
	var denom := float(maxi(1, n - 1))
	for i in n:
		var x := rect.position.x + rect.size.x * (float(i) / denom)
		var frac := clampf((samples[i] - vmin) / span, 0.0, 1.0)
		var y := rect.position.y + rect.size.y * (1.0 - frac)  # high value -> top of the rect
		pts.append(Vector2(x, y))
	return pts


## The graph surface: two stacked line graphs (FPS on top, frame-time below), redrawn each sample. Inner so the
## overlay is one file; uses DebugOverlay's pure graph_points so the mapping is the tested one.
class _Graph extends Control:
	var fps := PackedFloat32Array()
	var frame_ms := PackedFloat32Array()

	func _draw() -> void:
		var half := size.y * 0.5
		_one(Rect2(0, 0, size.x, half), fps, 0.0, 120.0, Color(0.4, 1.0, 0.5), "FPS")
		_one(Rect2(0, half, size.x, half), frame_ms, 0.0, 33.3, Color(1.0, 0.82, 0.3), "ms")

	func _one(r: Rect2, buf: PackedFloat32Array, vmin: float, vmax: float, col: Color, label: String) -> void:
		draw_rect(r, Color(0, 0, 0, 0.25), true)
		var font := get_theme_default_font()
		if font != null:
			draw_string(font, Vector2(r.position.x + 2.0, r.position.y + 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))
		var pts := DebugOverlay.graph_points(buf, r, vmin, vmax)
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], col, 1.0)
