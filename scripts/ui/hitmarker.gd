class_name Hitmarker
extends Control

## Crosshair hit-confirm: four short ticks forming an X around the centre that pop in and fade
## out whenever the player lands damage on something (an enemy, or themselves via splash). The
## owner calls flash().

@export var duration: float = 0.25
@export var tick_length: float = 5.0   ## length of each tick (px)
@export var gap: float = 3.0            ## gap from the crosshair centre (px)
@export var thickness: float = 2.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.9)

var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Pop the hitmarker (call when a shot/explosion of ours connects).
func flash() -> void:
	_t = duration
	queue_redraw()

func _process(delta: float) -> void:
	if _t <= 0.0:
		return
	_t -= delta
	queue_redraw()

func _draw() -> void:
	if _t <= 0.0:
		return
	var a := clampf(_t / duration, 0.0, 1.0)
	var col := color
	col.a *= a
	var centre := size * 0.5
	# Slight pop: ticks sit a touch further out at full strength, settle in as they fade.
	var g := gap + 3.0 * a
	for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var d = dir.normalized()
		draw_line(centre + d * g, centre + d * (g + tick_length), col, thickness, true)
