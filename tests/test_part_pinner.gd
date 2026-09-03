extends GutTest

## PartPinner is the whole decision layer of the thrown-weapon PIN kill (a lethal knife throw staples the body
## part it struck to the wall behind, blade through it) expressed as pure statics — no nodes, no tree, no physics
## server — precisely so it can be pinned here off-tree, the BodyPartGib.mount_placement / BodyPartGibs.wants_part
## idiom. The in-tree halves (GoreSpawner._resolve_pin's raycast, BodyPartGib's flight) are playtest surface; every
## number they feed on is decided by one of the functions below.

const PartPinner := preload("res://scripts/effects/part_pinner.gd")

## A stand-in for GoreSpawner's live part centres: the six BodyModelSwap parts of a character facing +Z at the
## origin. Arms sit to either SIDE (the left/right split body_part_at cannot make), legs low, head high.
func _rig() -> Array:
	return [
		{"key": "torso", "centre": Vector3(0.0, 1.1, 0.0)},
		{"key": "head", "centre": Vector3(0.0, 1.6, 0.0)},
		{"key": "arm_l", "centre": Vector3(-0.35, 1.15, 0.0)},
		{"key": "arm_r", "centre": Vector3(0.35, 1.15, 0.0)},
		{"key": "leg_l", "centre": Vector3(-0.15, 0.45, 0.0)},
		{"key": "leg_r", "centre": Vector3(0.15, 0.45, 0.0)},
	]

# --- nearest_key: WHICH limb the knife took --------------------------------------------------------------------

func test_nearest_key_picks_the_part_the_strike_landed_on() -> void:
	assert_eq(PartPinner.nearest_key(Vector3(0.02, 1.58, -0.2), _rig()), "head",
		"a strike at head height in front of the body names the head")
	assert_eq(PartPinner.nearest_key(Vector3(0.0, 1.05, -0.2), _rig()), "torso",
		"a strike at chest height on the centre line names the torso")

func test_nearest_key_resolves_left_vs_right() -> void:
	# THE reason this exists rather than Character.body_part_at: that classifier's BodyPart.ARMS names BOTH arms,
	# so it cannot say which limb node to fling at the wall. Measuring to live centres splits the pair for free.
	assert_eq(PartPinner.nearest_key(Vector3(-0.4, 1.15, -0.1), _rig()), "arm_l",
		"a strike on the body's left side names the LEFT arm, not the pair")
	assert_eq(PartPinner.nearest_key(Vector3(0.4, 1.15, -0.1), _rig()), "arm_r",
		"the mirrored strike names the RIGHT arm")

func test_nearest_key_tracks_a_moved_rig_rather_than_fixed_thresholds() -> void:
	# The other reason: a SEATED actor's visible parts ride ~0.28 m below the capsule Character.body_part_at
	# measures against, so a knife in a sitting guard's chest classifies as a leg there. Centres move with the
	# body, so the same strike still names the torso.
	var seated: Array = []
	for e in _rig():
		seated.append({"key": e["key"], "centre": (e["centre"] as Vector3) - Vector3(0.0, 0.28, 0.0)})
	assert_eq(PartPinner.nearest_key(Vector3(0.0, 0.82, -0.2), seated), "torso",
		"a chest strike on a seated rig still names the torso once the parts have dropped with the pose")

func test_nearest_key_degrades_to_empty_rather_than_guessing() -> void:
	assert_eq(PartPinner.nearest_key(Vector3.ZERO, []), "",
		"no parts at all yields no key, so the caller skips the pin instead of pinning something arbitrary")
	assert_eq(PartPinner.nearest_key(Vector3.ZERO, [{"key": "head"}, "not a dictionary", {"centre": Vector3.ONE}]), "",
		"entries with no centre (and non-Dictionary junk) are skipped, and an all-junk list yields no key")

func test_nearest_key_skips_non_finite_centres() -> void:
	var entries: Array = [
		{"key": "head", "centre": Vector3(INF, INF, INF)},
		{"key": "torso", "centre": Vector3(0.0, 1.1, 0.0)},
	]
	assert_eq(PartPinner.nearest_key(Vector3(0.0, 1.6, 0.0), entries), "torso",
		"a non-finite centre can never win the distance compare, however close the strike")

# --- support_along: how deep a body has to sit to look flush ---------------------------------------------------

func test_support_along_is_the_half_extent_facing_the_wall() -> void:
	var size := Vector3(0.4, 0.6, 0.2)
	assert_almost_eq(PartPinner.support_along(Basis.IDENTITY, size, Vector3.RIGHT), 0.2, 0.0001,
		"travelling along +X, the body sticks out by half its X size")
	assert_almost_eq(PartPinner.support_along(Basis.IDENTITY, size, Vector3.BACK), 0.1, 0.0001,
		"travelling along +Z, by half its Z size")

func test_support_along_follows_the_bodys_own_rotation() -> void:
	# A limb hangs at whatever angle it died at; the seat depth has to be measured in ITS frame, not the world's.
	var size := Vector3(0.4, 0.6, 0.2)
	var yawed := Basis(Vector3.UP, deg_to_rad(90.0))
	assert_almost_eq(PartPinner.support_along(yawed, size, Vector3.RIGHT), 0.1, 0.0001,
		"yawed 90 degrees, the extent facing +X is the box's Z half-size, not its X one")

func test_support_along_is_never_negative_or_nan() -> void:
	assert_eq(PartPinner.support_along(Basis.IDENTITY, Vector3.ONE, Vector3.ZERO), 0.0,
		"a degenerate direction reports no support (a shallow seat) rather than NaN")
	assert_almost_eq(PartPinner.support_along(Basis.IDENTITY, Vector3(-0.4, -0.6, -0.2), Vector3.RIGHT), 0.2, 0.0001,
		"a negatively-authored collider size is read by magnitude, so support stays positive")

# --- seat_origin: where the limb comes to rest -----------------------------------------------------------------

func test_seat_origin_bury_zero_rests_the_limb_against_the_wall() -> void:
	var seat := PartPinner.seat_origin(Vector3(0.0, 1.5, 4.0), Vector3.BACK, 0.25, 0.0)
	assert_almost_eq(seat.distance_to(Vector3(0.0, 1.5, 3.75)), 0.0, 0.0001,
		"with no bury the body sits its full half-extent back, so its face just touches the surface")

func test_seat_origin_bury_one_puts_the_centre_on_the_surface() -> void:
	var seat := PartPinner.seat_origin(Vector3(0.0, 1.5, 4.0), Vector3.BACK, 0.25, 1.0)
	assert_almost_eq(seat.distance_to(Vector3(0.0, 1.5, 4.0)), 0.0, 0.0001,
		"full bury sinks the body until its centre is on the wall face — half of it inside the geometry")

func test_seat_origin_clamps_a_bury_outside_zero_to_one() -> void:
	var over := PartPinner.seat_origin(Vector3.ZERO, Vector3.BACK, 0.25, 4.0)
	var under := PartPinner.seat_origin(Vector3.ZERO, Vector3.BACK, 0.25, -3.0)
	assert_almost_eq(over.distance_to(Vector3.ZERO), 0.0, 0.0001,
		"a bury above 1 clamps — a limb can never be seated PAST the surface it hit")
	assert_almost_eq(under.distance_to(Vector3(0.0, 0.0, -0.25)), 0.0, 0.0001,
		"a negative bury clamps to 0 — never seated in front of where it stopped")

# --- blade_origin: the knife left in the wall ------------------------------------------------------------------

func test_blade_origin_leaves_the_tip_embedded_past_the_surface() -> void:
	# Measured from the SURFACE, not from the limb: the knife goes through the limb INTO the wall.
	var surface := Vector3(0.0, 1.5, 4.0)
	var origin := PartPinner.blade_origin(surface, Vector3.BACK, 0.23, 0.1)
	assert_almost_eq(origin.distance_to(Vector3(0.0, 1.5, 3.87)), 0.0, 0.0001,
		"a 0.46 m blade embedded 0.1 m sits its origin 0.13 m in front of the wall")
	var tip := origin + Vector3.BACK * 0.23
	assert_almost_eq(tip.z - surface.z, 0.1, 0.0001,
		"...which puts the TIP exactly the embed depth inside the surface")

# --- reached: the arrival test the flight stops on -------------------------------------------------------------

func test_reached_is_a_half_space_so_an_overshoot_still_seats() -> void:
	var seat := Vector3(0.0, 1.5, 4.0)
	assert_false(PartPinner.reached(Vector3(0.0, 1.5, 2.0), seat, Vector3.BACK),
		"short of the seat plane, the limb is still in flight")
	assert_true(PartPinner.reached(seat, seat, Vector3.BACK),
		"exactly on the seat plane counts as arrived")
	assert_true(PartPinner.reached(Vector3(0.0, 1.5, 9.0), seat, Vector3.BACK),
		"PAST it counts too — a fast limb that overshoots between physics ticks must still seat, not sail on")

func test_reached_ignores_travel_perpendicular_to_the_throw() -> void:
	assert_false(PartPinner.reached(Vector3(50.0, 1.5, 2.0), Vector3(0.0, 1.5, 4.0), Vector3.BACK),
		"only distance ALONG the throw counts; drifting sideways never arrives")

# --- surface_accepts: which surfaces are worth stapling to -----------------------------------------------------

func test_surface_accepts_a_wall_square_to_the_throw() -> void:
	assert_true(PartPinner.surface_accepts(Vector3.FORWARD, Vector3.BACK, 55.0),
		"a wall facing straight back at the throw is the ideal case")

func test_surface_accepts_rejects_a_graze() -> void:
	# The case this exists for: a downward throw catching the FLOOR. A limb lying flat on the ground is what an
	# ordinary gib that failed to bounce already looks like, so pinning there reads as a bug, not a trick shot.
	var shallow := Vector3(0.0, 0.3, -1.0).normalized()
	assert_false(PartPinner.surface_accepts(Vector3.UP, shallow, 55.0),
		"a floor caught at a glancing angle is refused, and the death plays as a normal burst")
	assert_true(PartPinner.surface_accepts(Vector3.UP, Vector3.DOWN, 55.0),
		"...but a throw straight DOWN into the floor is square to it, and does pin")

func test_surface_accepts_rejects_a_back_face() -> void:
	assert_false(PartPinner.surface_accepts(Vector3.BACK, Vector3.BACK, 89.0),
		"a normal pointing the same way we are travelling is a surface we are leaving, never one to staple to")

func test_surface_accepts_degrades_safely() -> void:
	assert_false(PartPinner.surface_accepts(Vector3.ZERO, Vector3.BACK, 55.0),
		"no normal, no pin")
	assert_false(PartPinner.surface_accepts(Vector3.FORWARD, Vector3.ZERO, 55.0),
		"no travel direction, no pin")

# --- rigid_anchor / attach_offset / attached_pose: riding a LIVING body part ------------------------------------
#
# The other half of PartPinner: a blade the victim SURVIVES stays in the part it struck and is re-posed onto that
# part's frame every physics step (Throwable._follow_stuck_part). These three are that maths, and the property
# that has to hold is a round trip — measure once at the strike, replay forever, and the blade must sit exactly
# where it was put when nothing has moved, and rigidly with the part when something has.

func test_rigid_anchor_strips_scale_but_keeps_rotation() -> void:
	var scaled := Transform3D(Basis.from_euler(Vector3(0.0, 0.9, 0.0)).scaled(Vector3(1.3, 1.3, 1.3)), Vector3(0.0, 1.6, 2.0))
	var anchor := PartPinner.rigid_anchor(scaled)
	assert_almost_eq(anchor.basis.get_scale().x, 1.0, 0.0001,
		"a 1.3x head must NOT make a 1.3x knife — the anchor carries rotation only")
	assert_eq(anchor.origin, scaled.origin,
		"...and it stays exactly where the part is")
	assert_almost_eq(anchor.basis.get_euler().y, 0.9, 0.0001,
		"the part's facing is the whole point of the anchor and survives untouched")

func test_rigid_anchor_keeps_a_mirrored_limb_mirrored() -> void:
	# A right limb is authored as a MIRROR of the left, so its basis has a negative determinant. Orthonormalising
	# must not "fix" that: the mirror has to survive into the anchor so it cancels back out through the offset.
	var mirrored := Transform3D(Basis.IDENTITY.scaled(Vector3(-1.0, 1.0, 1.0)), Vector3(0.4, 1.15, 0.0))
	assert_lt(PartPinner.rigid_anchor(mirrored).basis.determinant(), 0.0,
		"a mirrored part keeps its handedness in the anchor")

func test_rigid_anchor_degrades_on_a_collapsed_basis() -> void:
	var collapsed := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(1.0, 2.0, 3.0))
	var anchor := PartPinner.rigid_anchor(collapsed)
	assert_eq(anchor.origin, Vector3(1.0, 2.0, 3.0),
		"a zero-scaled part still parks the blade AT the part rather than producing a NaN pose")
	assert_almost_eq(anchor.basis.determinant(), 1.0, 0.0001,
		"...with no rotation at all, which is visibly wrong but never invalid")

func test_the_attach_round_trip_reproduces_the_strike_pose_exactly() -> void:
	var part := Transform3D(Basis.from_euler(Vector3(0.0, 1.2, 0.0)), Vector3(0.0, 1.1, 0.0))
	var pose := Transform3D(Basis.from_euler(Vector3(0.3, -0.4, 0.1)), Vector3(0.05, 1.18, 0.22))
	var anchor := PartPinner.rigid_anchor(part)
	var back := PartPinner.attached_pose(anchor, PartPinner.attach_offset(anchor, pose))
	assert_almost_eq(back.origin.distance_to(pose.origin), 0.0, 0.0001,
		"replaying the offset onto an UNMOVED part must put the blade back exactly where the strike left it")
	assert_almost_eq((back.basis.get_euler() - pose.basis.get_euler()).length(), 0.0, 0.0001,
		"...facing included, or the knife would snap to a new angle on its first frame")

func test_the_blade_rides_a_part_that_moves_and_turns() -> void:
	# The feature itself, as arithmetic: the guard walks 3 m and turns 90 degrees; the knife in his chest has to
	# arrive at the same place ON him, not the same place in the room.
	var part := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.1, 0.0))
	var pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.1, 0.25))  # 25 cm out in front of his chest
	var offset := PartPinner.attach_offset(PartPinner.rigid_anchor(part), pose)
	var moved := Transform3D(Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)), Vector3(3.0, 1.1, 0.0))
	var now := PartPinner.attached_pose(PartPinner.rigid_anchor(moved), offset)
	assert_almost_eq(now.origin.distance_to(Vector3(3.25, 1.1, 0.0)), 0.0, 0.0001,
		"a quarter-turn puts the hilt out to his +X side, still 25 cm from his chest")
	assert_almost_eq(now.origin.distance_to(moved.origin), 0.25, 0.0001,
		"the blade never drifts closer to or further from the part it is buried in")

func test_the_blade_keeps_its_own_size_on_a_scaled_part() -> void:
	# The regression rigid_anchor exists to prevent: bolting to the RAW transform would multiply the part's scale
	# into the knife every frame, so a knife in a big head would be a big knife.
	var big := Transform3D(Basis.IDENTITY.scaled(Vector3(2.0, 2.0, 2.0)), Vector3(0.0, 1.6, 0.0))
	var pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, 0.2))
	var anchor := PartPinner.rigid_anchor(big)
	var back := PartPinner.attached_pose(anchor, PartPinner.attach_offset(anchor, pose))
	assert_almost_eq(back.basis.get_scale().distance_to(Vector3.ONE), 0.0, 0.0001,
		"the blade comes back at its authored 1:1 scale however big the part it is in")
