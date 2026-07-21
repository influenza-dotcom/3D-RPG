class_name WireShapes
extends RefCounted

## Pure line-segment generators for RUNTIME debug drawing (static-only; never instanced). Each returns a
## PackedVector3Array in PAIR format (consecutive points = one segment) ready for ImmediateMesh PRIMITIVE_LINES
## (or any add_lines() caller). The optional `x` Transform3D is baked into every point, so a caller can pass a
## world transform (e.g. an NPC's eye pose, or a zone's global_transform * its CollisionShape3D.transform) and get
## lines already in world space. No engine/tree access — all math, so it's off-tree unit-testable.
##
## This is the runtime SIBLING of the editor-only addons/cybersunday_tools/gizmos/gizmo_shapes.gd: the editor gizmo
## plugin draws these same volumes at EDIT time; this lets NavDebugOverlay redraw them at RUNTIME (gizmos don't run
## in a running game). Keep the two visually consistent — same recipes, same segment counts — so a designer sees the
## same shape whether they're placing it in the editor or diagnosing it in-game.


## 12 edges of an axis-aligned box of `size` (FULL extents), centered at the origin.
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


## A flat circle in the local XZ plane (a "ground ring"), centered at the origin.
static func ring(radius: float, x := Transform3D.IDENTITY, segments := 32) -> PackedVector3Array:
	var out := PackedVector3Array()
	if radius <= 0.0:
		return out
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


## A FLAT sight cone in the local XZ plane: apex at the origin, two edge rays at +/-half_angle around `facing` out
## to `radius`, plus the far arc between them. `facing` is flattened to XZ. Mirrors the editor gizmo's cone: a
## Perception view-cone is HORIZONTAL-only (vertical unbounded), so a flat ground fan at eye height is the honest
## shape, not a 3D cone. Pass the eye pose as `x` and Vector3.BACK as `facing` (the model's +Z front).
static func cone_flat(radius: float, half_angle_rad: float, facing := Vector3.FORWARD, x := Transform3D.IDENTITY, arc_segments := 20) -> PackedVector3Array:
	var out := PackedVector3Array()
	if radius <= 0.0:
		return out
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


## Wireframe for a physics `shape` at world transform `x` (dispatches Box/Sphere/Cylinder/Capsule — the shapes the
## trigger/hazard/audio/shadow zones use). Empty for an unsupported shape (e.g. a ConvexPolygon/Concave mesh), so a
## caller can safely skip it. Mirrors the editor gizmo's _shape_lines so a zone reads identically in-game.
static func shape_lines(shape: Shape3D, x := Transform3D.IDENTITY) -> PackedVector3Array:
	if shape is BoxShape3D:
		return box((shape as BoxShape3D).size, x)
	elif shape is SphereShape3D:
		return sphere((shape as SphereShape3D).radius, x)
	elif shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		return cylinder(c.radius, c.height, x)
	elif shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		return capsule(cap.radius, cap.height, x)
	return PackedVector3Array()
