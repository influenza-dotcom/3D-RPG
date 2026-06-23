@tool
extends RefCounted

## Pure line-segment generators for the editor gizmos. Each returns a PackedVector3Array in EditorNode3DGizmo
## add_lines() PAIR format (consecutive points = one segment). The optional `x` Transform3D is baked into every
## point, so a caller can pass an Area3D child's relative transform and get lines already in the gizmo's local
## space. No engine/tree access -- all math, unit-testable off-tree.


## 12 edges of an axis-aligned box of `size` (full extents), centered at the origin.
static func box(size: Vector3, x := Transform3D.IDENTITY) -> PackedVector3Array:
	var h := size * 0.5
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var e := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	var out := PackedVector3Array()
	for i in e:
		out.append(x * c[i])
	return out


## A small 3-axis cross (X/Y/Z spokes through the origin) marking a single point. `size` is each spoke's
## half-length, so the cross spans 2*size on every axis. Six points = three segments.
static func cross(size: float, x := Transform3D.IDENTITY) -> PackedVector3Array:
	var out := PackedVector3Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		out.append(x * (axis * -size))
		out.append(x * (axis * size))
	return out


## A flat circle in the local XZ plane (a "ground ring"), centered at the origin.
static func ring(radius: float, x := Transform3D.IDENTITY, segments := 32) -> PackedVector3Array:
	var out := PackedVector3Array()
	var prev := Vector3(radius, 0.0, 0.0)
	for i in range(1, segments + 1):
		var a := TAU * float(i) / float(segments)
		var cur := Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		out.append(x * prev)
		out.append(x * cur)
		prev = cur
	return out


## A wire sphere: three orthogonal great circles (XY, XZ, YZ).
static func sphere(radius: float, x := Transform3D.IDENTITY, segments := 24) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append_array(_circle_plane(radius, Vector3.RIGHT, Vector3.UP, x, segments))
	out.append_array(_circle_plane(radius, Vector3.RIGHT, Vector3.FORWARD, x, segments))
	out.append_array(_circle_plane(radius, Vector3.UP, Vector3.FORWARD, x, segments))
	return out


static func _circle_plane(radius: float, a: Vector3, b: Vector3, x: Transform3D, segments: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var prev := a * radius
	for i in range(1, segments + 1):
		var t := TAU * float(i) / float(segments)
		var cur := (a * cos(t) + b * sin(t)) * radius
		out.append(x * prev)
		out.append(x * cur)
		prev = cur
	return out


## A wire cylinder: top + bottom rings joined by 4 vertical edges. Height along local Y, centered.
static func cylinder(radius: float, height: float, x := Transform3D.IDENTITY, segments := 24) -> PackedVector3Array:
	var out := PackedVector3Array()
	var hy := height * 0.5
	out.append_array(ring(radius, x * Transform3D(Basis(), Vector3(0.0, hy, 0.0)), segments))
	out.append_array(ring(radius, x * Transform3D(Basis(), Vector3(0.0, -hy, 0.0)), segments))
	for i in 4:
		var a := TAU * float(i) / 4.0
		var p := Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		out.append(x * (p + Vector3(0.0, hy, 0.0)))
		out.append(x * (p + Vector3(0.0, -hy, 0.0)))
	return out


## A wire capsule: cylinder body + two sphere caps (Godot CapsuleShape3D: height is TOTAL, includes the caps).
static func capsule(radius: float, height: float, x := Transform3D.IDENTITY, segments := 24) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cyl_h := maxf(0.0, height - 2.0 * radius)
	out.append_array(cylinder(radius, cyl_h, x, segments))
	var hy := cyl_h * 0.5
	out.append_array(sphere(radius, x * Transform3D(Basis(), Vector3(0.0, hy, 0.0)), segments))
	out.append_array(sphere(radius, x * Transform3D(Basis(), Vector3(0.0, -hy, 0.0)), segments))
	return out


## Connect `points` in order; `closed` adds the last->first wrap segment.
static func polyline(points: PackedVector3Array, closed := false, x := Transform3D.IDENTITY) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := points.size()
	if n < 2:
		return out
	for i in n - 1:
		out.append(x * points[i])
		out.append(x * points[i + 1])
	if closed:
		out.append(x * points[n - 1])
		out.append(x * points[0])
	return out


## A facing arrow from the origin along `dir`, with a small splayed arrowhead at the tip.
static func arrow(dir: Vector3, length := 1.0, x := Transform3D.IDENTITY) -> PackedVector3Array:
	var out := PackedVector3Array()
	var d := dir.normalized()
	if d == Vector3.ZERO:
		return out
	var tip := d * length
	out.append(x * Vector3.ZERO)
	out.append(x * tip)
	var side := d.cross(Vector3.UP)
	if side.length() < 0.01:
		side = d.cross(Vector3.RIGHT)
	side = side.normalized()
	var back := tip - d * (length * 0.25)
	out.append(x * tip)
	out.append(x * (back + side * length * 0.12))
	out.append(x * tip)
	out.append(x * (back - side * length * 0.12))
	return out


## A flat ARC swept in the local XZ plane: a fan from the origin out to `radius`, sweeping from `start_rad` to
## `start_rad + sweep_rad` (signed — a negative sweep goes the other way). Emits the two bounding radii (origin->
## start point, origin->end point) PLUS the curved edge between them, so a door swing reads as "panel here -> panel
## there". Angles are measured the same way as ring()/cone_flat() (atan2(x, z) convention: 0 = +Z, increasing
## toward +X). `segments` divides the curved edge.
static func arc(radius: float, start_rad: float, sweep_rad: float, x := Transform3D.IDENTITY, segments := 16) -> PackedVector3Array:
	var out := PackedVector3Array()
	var seg: int = maxi(1, segments)
	var p_start := Vector3(sin(start_rad), 0.0, cos(start_rad)) * radius
	var end_ang := start_rad + sweep_rad
	var p_end := Vector3(sin(end_ang), 0.0, cos(end_ang)) * radius
	# The two bounding radii (closed-panel edge + open-panel edge).
	out.append(x * Vector3.ZERO)
	out.append(x * p_start)
	out.append(x * Vector3.ZERO)
	out.append(x * p_end)
	# The curved edge between them.
	var prev := p_start
	for i in range(1, seg + 1):
		var t := float(i) / float(seg)
		var a := start_rad + sweep_rad * t
		var cur := Vector3(sin(a), 0.0, cos(a)) * radius
		out.append(x * prev)
		out.append(x * cur)
		prev = cur
	return out


## A FLAT sight cone in the local XZ plane: apex at the origin, two edge rays at +/-half_angle around `facing`
## out to `radius`, plus the far arc between them. `facing` is flattened to XZ.
static func cone_flat(radius: float, half_angle_rad: float, facing := Vector3.FORWARD, x := Transform3D.IDENTITY, arc_segments := 16) -> PackedVector3Array:
	var out := PackedVector3Array()
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() < 0.001:
		f = Vector3.FORWARD
	f = f.normalized()
	var base_ang := atan2(f.x, f.z)
	for s in [-1.0, 1.0]:
		var a: float = base_ang + s * half_angle_rad
		var p := Vector3(sin(a), 0.0, cos(a)) * radius
		out.append(x * Vector3.ZERO)
		out.append(x * p)
	var prev_a := base_ang - half_angle_rad
	var prev := Vector3(sin(prev_a), 0.0, cos(prev_a)) * radius
	for i in range(1, arc_segments + 1):
		var t := float(i) / float(arc_segments)
		var a := base_ang - half_angle_rad + 2.0 * half_angle_rad * t
		var cur := Vector3(sin(a), 0.0, cos(a)) * radius
		out.append(x * prev)
		out.append(x * cur)
		prev = cur
	return out
