class_name DamageIndicators
extends Control

## TF2-style directional damage indicators: a fading red arc around the crosshair pointing
## toward each recent damage source. The owner calls add(bearing), where bearing is the
## source's direction relative to where the player faces (0 = dead ahead, + = right,
## ±PI = behind). Multiple hits stack; each fades out over `duration`.

## Seconds each arc stays visible (it fades over this).
@export var duration: float = 1.0
## Distance of the arc from screen centre, in pixels.
@export var radius: float = 120.0
## Angular width of each arc wedge, in degrees.
@export var arc_degrees: float = 55.0
@export var thickness: float = 8.0
@export var color: Color = Color(0.85, 0.08, 0.08)

var _hits: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input

## Flash an indicator toward `bearing` radians (0 = ahead, + = right, ±PI = behind).
func add(bearing: float) -> void:
	_hits.append({"bearing": bearing, "t": duration})
	queue_redraw()

func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for i in range(_hits.size() - 1, -1, -1):
		_hits[i]["t"] -= delta
		if _hits[i]["t"] <= 0.0:
			_hits.remove_at(i)
	queue_redraw()

func _draw() -> void:
	var centre := size * 0.5
	var half := deg_to_rad(arc_degrees) * 0.5
	for h in _hits:
		# 0 bearing (ahead) maps to the top of the screen. Godot 2D angles: 0 = +x (right),
		# increasing clockwise (y is down), so subtract 90° to put "ahead" at 12 o'clock.
		var a: float = h["bearing"] - PI * 0.5
		var col := color
		col.a *= clampf(h["t"] / duration, 0.0, 1.0)
		draw_arc(centre, radius, a - half, a + half, 24, col, thickness, true)
