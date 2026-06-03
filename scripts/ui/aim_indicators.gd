class_name AimIndicators
extends Control

## "You're being aimed at" warning: a white arc around the crosshair pointing toward each enemy
## currently drawing a bead on you. Its opacity tracks that enemy's aim charge (0 = just noticing
## you / translucent, 1 = locked + about to fire / opaque). Like DamageIndicators the bearing is
## recomputed every frame from the live `camera`, so each arc keeps pointing at its source as you
## turn. Enemies push reports via report(); an entry expires shortly after they stop aiming.

## Distance of the arc from screen centre, in pixels (inside the red damage arcs so both read).
@export var radius: float = 100.0
## Angular width of each arc wedge, in degrees.
@export var arc_degrees: float = 45.0
@export var thickness: float = 6.0
@export var color: Color = Color(1, 1, 1)  # white

## Seconds an aim entry survives without a fresh report (i.e. the enemy stopped aiming at us).
const EXPIRY: float = 0.2

## Viewer camera (a Node3D). Bearings are taken relative to its facing each frame. Set by the owner.
var camera: Node3D

var _aims: Dictionary = {}  # source instance id -> { pos: Vector3, charge: float, t: float }

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input

## Called each frame by an enemy aiming at us: where it's aiming from + its 0..1 readiness.
func report(source: Object, world_pos: Vector3, charge: float) -> void:
	var id := source.get_instance_id()
	if charge <= 0.0:
		_aims.erase(id)
		return
	_aims[id] = {"pos": world_pos, "charge": clampf(charge, 0.0, 1.0), "t": EXPIRY}
	queue_redraw()

func _process(delta: float) -> void:
	if _aims.is_empty():
		return
	for id in _aims.keys():
		_aims[id]["t"] -= delta
		if _aims[id]["t"] <= 0.0:
			_aims.erase(id)
	queue_redraw()  # redraw every frame so the arcs follow camera rotation

func _draw() -> void:
	if _aims.is_empty() or not is_instance_valid(camera):
		return
	var centre := size * 0.5
	var half := deg_to_rad(arc_degrees) * 0.5
	# Horizontal camera frame (same math as DamageIndicators) so the bearing follows your view.
	var right := camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var fwd := Vector3.UP.cross(right)
	var eye := camera.global_position
	for id in _aims:
		var aim: Dictionary = _aims[id]
		var to_source: Vector3 = (aim["pos"] as Vector3) - eye
		to_source.y = 0.0
		if to_source.length_squared() < 0.0001:
			continue
		var bearing := atan2(to_source.dot(right), to_source.dot(fwd))
		var a := bearing - PI * 0.5
		var col := color
		col.a = clampf(aim["charge"], 0.0, 1.0)
		draw_arc(centre, radius, a - half, a + half, 24, col, thickness, true)
