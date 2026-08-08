class_name PartPinner
extends RefCounted

## PURE GEOMETRY + POLICY for the thrown-weapon PIN kill: a knife thrown hard enough to kill carries the body
## part it struck off the corpse and staples it to the wall behind, blade still through it.
##
## Nothing here touches a node, a tree or the physics server -- every function is a static over plain values, so
## GUT can pin the whole decision layer off-tree (tests/test_part_pinner.gd) exactly the way
## BodyPartGib.mount_placement and BodyPartGibs.wants_part are pinned. The in-tree halves live where they belong:
##   * GoreSpawner._spawn_pinned_part  -- reads the intent, raycasts for the surface, hands the flight over
##   * BodyPartGib.begin_pin_flight    -- flies the limb to the wall and freezes it there
##   * Throwable.pin_at / unpin        -- parks and releases the blade
##
## WHY NEAREST-CENTRE AND NOT Character.body_part_at: that classifier splits zones against the CHARACTER ROOT's
## local frame with fixed thresholds (head_local_y / leg_local_y / arm_local_x), which is right for damage
## because it stays cheap and yaw-correct. It is wrong for choosing a MODEL PART twice over: it has no left /
## right (BodyPart.ARMS names both), and a SEATED actor's visible parts ride ~0.28 m below the capsule those
## thresholds measure (BodyModelSwap.posture_offset), so a knife in a sitting guard's chest classifies as a leg.
## Measuring straight to the live part centres has neither problem -- the parts ARE where they are drawn, so the
## answer is posture-correct and side-correct for free, and "the part it hit" means literally the nearest one.
static func nearest_key(contact: Vector3, entries: Array) -> String:
	var best := ""
	var best_d := INF
	for e in entries:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var centre: Variant = d.get("centre", null)
		if not (centre is Vector3) or not (centre as Vector3).is_finite():
			continue
		var dist: float = contact.distance_squared_to(centre as Vector3)
		if dist < best_d:
			best_d = dist
			best = String(d.get("key", ""))
	return best

## Half-extent of an oriented box along `dir` -- how far the body sticks out from its own origin in the
## direction it is travelling. The standard box-vs-axis support function: project each half-axis onto `dir` and
## sum the magnitudes. Used twice, for the two things that have to end up flush with the wall: how deep to seat
## the LIMB (its auto-fitted collider) and how far back the BLADE's origin sits from its own tip.
## A degenerate dir or size returns 0.0, which seats the body exactly on the surface point -- visibly wrong but
## never NaN, and unreachable from a real collider.
static func support_along(basis: Basis, size: Vector3, dir: Vector3) -> float:
	if dir.length_squared() < 0.000001:
		return 0.0
	var d := dir.normalized()
	var half := size.abs() * 0.5
	return absf(d.dot(basis.x)) * half.x + absf(d.dot(basis.y)) * half.y + absf(d.dot(basis.z)) * half.z

## Where the pinned limb's BODY ORIGIN comes to rest, given the surface point the probe found, the travel
## direction, the limb's `support` along that direction, and how far it sinks in.
##
## `bury` is a 0..1 fraction of the limb's own half-depth, NOT metres -- a head and a forearm are different
## sizes and the same absolute sink would swallow one and barely dent the other. 0 leaves the limb exactly
## touching the wall (it reads as resting against it); 1 puts its CENTRE on the wall face (half the limb inside
## the geometry). The shipped default sits between, so the limb visibly bites in.
static func seat_origin(surface_point: Vector3, dir: Vector3, support: float, bury: float) -> Vector3:
	if dir.length_squared() < 0.000001:
		return surface_point
	return surface_point - dir.normalized() * support * (1.0 - clampf(bury, 0.0, 1.0))

## Where the BLADE's origin sits once it is embedded: aimed along `dir`, its TIP `embed` metres past the
## surface. `half_length` is the blade's support along dir (support_along with its aimed basis), so the origin
## is that far back from the tip. Independent of the limb's seat -- the knife goes through the limb into the
## wall, so it is the SURFACE, not the limb, both of them are measured from.
static func blade_origin(surface_point: Vector3, dir: Vector3, half_length: float, embed: float) -> Vector3:
	if dir.length_squared() < 0.000001:
		return surface_point
	return surface_point + dir.normalized() * (embed - half_length)

## Has a body flying along `dir` reached its seat yet? True once it is at or past the seat plane -- a
## HALF-SPACE test, not a distance one, so a limb that overshoots between physics ticks (the flight is short and
## fast, and the chassis runs continuous_cd) still seats instead of sailing on and missing its window.
static func reached(pos: Vector3, seat: Vector3, dir: Vector3) -> bool:
	if dir.length_squared() < 0.000001:
		return true
	return (pos - seat).dot(dir.normalized()) >= 0.0

## Is this surface worth stapling to? The probe already fires ALONG the throw, so anything it hits was in the
## knife's path; the only thing left to reject is a surface the knife merely GRAZED -- a floor caught by a
## downward throw, where a limb lying flat reads as an ordinary gib that failed to bounce rather than a trophy.
## `max_angle_degrees` is how far the surface may face away from straight-on (0 = only a wall square to the
## throw; 90 = accept anything, including a graze).
static func surface_accepts(normal: Vector3, dir: Vector3, max_angle_degrees: float) -> bool:
	if normal.length_squared() < 0.000001 or dir.length_squared() < 0.000001:
		return false
	# The normal points BACK out of the surface, so a head-on hit has dot(normal, dir) == -1.
	var head_on := -normal.normalized().dot(dir.normalized())
	if head_on <= 0.0:
		return false  # a back face / a surface we are leaving, never a wall we are driving into
	return rad_to_deg(acos(clampf(head_on, -1.0, 1.0))) <= maxf(max_angle_degrees, 0.0)
