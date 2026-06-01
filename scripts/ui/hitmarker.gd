class_name Hitmarker
extends Control

## Crosshair hit-confirm: four short ticks forming an X around the centre that pop in and fade
## out whenever the player lands damage. flash(headshot) makes a HEADSHOT pop bigger and in a
## distinct colour, so head hits read instantly. The owner calls flash().

@export var duration: float = 0.25
@export var tick_length: float = 5.0   ## length of each tick (px)
@export var gap: float = 3.0            ## gap from the crosshair centre (px)
@export var thickness: float = 2.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.9)
## Headshots flash this colour, scaled up, so they're unmistakable.
@export var headshot_color: Color = Color(1.0, 0.22, 0.12, 0.95)
@export var headshot_scale: float = 1.9

var _t: float = 0.0
var _headshot: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Pop the marker. Pass headshot = true for the bigger, coloured head-hit confirm.
func flash(headshot := false) -> void:
	_t = duration
	_headshot = headshot
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
	var col := headshot_color if _headshot else color
	col.a *= a
	var mult := headshot_scale if _headshot else 1.0
	var tick_len := tick_length * mult
	var tick_w := thickness * mult
	var centre := size * 0.5
	# Slight pop: ticks sit a touch further out at full strength, settle in as they fade.
	var g := (gap + 3.0 * a) * mult
	for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var d = dir.normalized()
		draw_line(centre + d * g, centre + d * (g + tick_len), col, tick_w, true)
