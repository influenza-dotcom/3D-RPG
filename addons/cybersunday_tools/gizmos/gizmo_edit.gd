@tool
extends RefCounted

## Pure math behind EDITABLE gizmo handles. The gizmo plugin's _set_handle turns a viewport drag (a camera ray, in
## the node's LOCAL space) into a value here; keeping the math pure makes it unit-testable without the editor (the
## handle wiring + undo/redo are editor-verified). Today the only editable handle is ExplosiveBarrel.blast_radius —
## a single radius dragged along +X.

## The radius for a radius-handle drag: the parameter t of the closest point on the axis line (through the local
## origin, direction `axis`) to the camera ray (`ray_origin` + s*`ray_dir`, both in the node's LOCAL space). This is
## the standard closest-points-between-two-lines solution specialized to a line through the origin. When the ray is
## ~parallel to the axis (degenerate) it falls back to projecting the ray origin onto the axis. NOT clamped — pass
## the result through clamp_radius(). Pure + tested.
static func radius_from_drag(ray_origin: Vector3, ray_dir: Vector3, axis: Vector3 = Vector3.RIGHT) -> float:
	var u := axis.normalized()
	var rd := ray_dir.normalized()
	var b := u.dot(rd)
	var denom := 1.0 - b * b  # a*c - b^2 with a (=u·u) and c (=rd·rd) both 1 for unit vectors
	if absf(denom) < 0.0001:
		return u.dot(ray_origin)  # ray ~parallel to the axis -> project the ray origin onto the axis
	var d := -u.dot(ray_origin)
	var e := -rd.dot(ray_origin)
	return (b * e - d) / denom


## Keep a dragged radius at or above a small floor so the handle stays grabbable and the shape stays visible
## (blast_radius has no @export_range, so this is the only clamp; mirror an Inspector range here if one is added).
static func clamp_radius(v: float, min_r: float = 0.1) -> float:
	return maxf(min_r, v)
