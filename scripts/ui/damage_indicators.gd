class_name DamageIndicators
extends Control

## TF2-style directional damage indicators: a fading red arc around the crosshair pointing toward
## each recent damage source. The owner records a hit's WORLD position via add(); the on-screen
## bearing is recomputed every frame from the live `camera` orientation, so each arc keeps pointing
## at its source as you turn — a frozen bearing would drift and mislead the moment you rotate.

## Seconds each arc stays visible (it fades over this).
@export var duration: float = 1.0
## Distance of the arc from screen centre, in pixels.
@export var radius: float = 120.0
## Angular width of each arc wedge, in degrees.
@export var arc_degrees: float = 55.0
@export var thickness: float = 8.0
@export var color: Color = Color(0.85, 0.08, 0.08)

## Viewer camera (a Node3D). Bearings are taken relative to its facing each frame. Set by the
## owner (Player) right after creation.
var camera: Node3D

var _hits: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input

## Record a damage source at `world_pos`; its on-screen direction is computed live in _draw.
func add(world_pos: Vector3) -> void:
	_hits.append({"pos": world_pos, "t": duration})
	queue_redraw()

func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for i in range(_hits.size() - 1, -1, -1):
		_hits[i]["t"] -= delta
		if _hits[i]["t"] <= 0.0:
			_hits.remove_at(i)
	queue_redraw()  # redraw every frame so the arcs follow camera rotation

func _draw() -> void:
	if _hits.is_empty() or not is_instance_valid(camera):
		return
	var centre := size * 0.5
	var half := deg_to_rad(arc_degrees) * 0.5
	# Horizontal camera frame: right (X) flattened, forward from it. Yawing turns these, so the
	# bearing — and thus the arc — follows where the player is looking.
	var right := camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var fwd := Vector3.UP.cross(right)
	var eye := camera.global_position
	for h in _hits:
		var to_source: Vector3 = (h["pos"] as Vector3) - eye
		to_source.y = 0.0
		if to_source.length_squared() < 0.0001:
			continue
		# 0 = dead ahead (top of screen). Godot 2D angles run 0 = +x clockwise, so subtract 90.
		var bearing := atan2(to_source.dot(right), to_source.dot(fwd))
		var a := bearing - PI * 0.5
		var col := color
		col.a *= clampf(h["t"] / duration, 0.0, 1.0)
		draw_arc(centre, radius, a - half, a + half, 24, col, thickness, true)
