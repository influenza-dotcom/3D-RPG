class_name Compass
extends Control

## A screen-edge compass: for every WorldMarker (anything in the "compass" group) it draws a marker at its
## on-screen position when visible, else a chevron pinned to the screen edge pointing toward it. Add it to the
## HUD as a full-rect Control. Needs the active Camera3D to project world->screen; the edge projection
## (project_to_edge) is pure + unit-tested. Drawing is playtest-tuned.

## Inset (px) of the edge chevron ring from the screen border.
@export var edge_margin: float = 28.0
## Radius (px) of a drawn marker dot / chevron.
@export var marker_size: float = 6.0
## Hide markers farther than this from the camera (0 = no limit).
@export var max_distance: float = 0.0

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for n in get_tree().get_nodes_in_group(&"compass"):
		if n is Node3D:
			_draw_marker(cam, n as Node3D)

func _draw_marker(cam: Camera3D, marker: Node3D) -> void:
	var wp := marker.global_position
	if max_distance > 0.0 and cam.global_position.distance_to(wp) > max_distance:
		return
	var raw_col: Variant = marker.get(&"color")
	var col: Color = raw_col if raw_col is Color else Color(1.0, 0.85, 0.3)
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp)
	if not behind and Rect2(Vector2.ZERO, size).has_point(sp):
		draw_circle(sp, marker_size, col)  # visible on-screen -> mark it where it is
	else:
		# Off-screen (outside the view rect, or behind us): pin a chevron to the edge ring pointing toward it.
		var dir := sp - size * 0.5
		if behind:
			dir = -dir  # a behind-camera point's unprojection is mirrored — flip so the chevron points the right way
		draw_circle(project_to_edge(dir, size, edge_margin), marker_size, col)

## Pure: the point on the viewport's inset-edge rectangle along `dir` from the center. `dir` need not be
## normalized; a near-zero dir returns the center. The inset is `margin` px in from each border. Unit-tested.
static func project_to_edge(dir: Vector2, size: Vector2, margin: float = 0.0) -> Vector2:
	var center := size * 0.5
	if dir.length_squared() < 0.000001:
		return center
	var d := dir.normalized()
	var half := Vector2(maxf(1.0, center.x - margin), maxf(1.0, center.y - margin))
	var tx: float = half.x / absf(d.x) if absf(d.x) > 0.0001 else INF
	var ty: float = half.y / absf(d.y) if absf(d.y) > 0.0001 else INF
	return center + d * minf(tx, ty)
