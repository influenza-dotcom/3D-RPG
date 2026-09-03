extends GutTest

## The seam that puts an NPC's weapon IN ITS HANDS and swings it at the target.
##
## Two public reads on BodyModelSwap, both consumed by npc.gd's `_sync_weapon_anchor`:
##   * `weapon_grip_position()` — swap-local metres, midway between the two hands at the CURRENT arm pose. The
##     NPC moves its `_muzzle` anchor here every physics frame, so the held view-model (and with it the shot
##     origin, the laser, the tracer and the muzzle FX) rides the hold pitch, the aim swing and the seated drop.
##   * `aim_pitch_contribution()` — how far the raised arms swing to follow the host's aim ELEVATION, so the
##     hands go up with the barrel instead of the weapon pivoting out of them.
##
## Both are derived from the LIVE `_arm_left` / `_arm_right` transforms, so the rig below builds real arm nodes
## rather than stubbing the maths. Everything is OFF-TREE (`.new()` + `free()`, no `_ready`) per CLAUDE.md.

const SWAP_PATH := "res://scripts/components/body_model_swap.gd"

## A swap with a real ARM PAIR: two Node3Ds each carrying a 2 m box down local +Z, which is the axis the shipped
## arm.blend puts its hand on (arm_rotation (90,0,0) then turns that axis DOWN into the by-the-side hang).
## `_part_reach` measures the farthest AABB corner from the arm's own origin, so the "hand" lands at ~2 m.
func _swap_with_arms(hold_pitch: float = -78.0) -> Node:
	var bms = load(SWAP_PATH).new()
	bms.arm_position = Vector3(-0.27, 0.155, -0.05)
	bms.arm_rotation = Vector3(90.0, 0.0, 0.0)
	# ⭐SHIPPED PROPORTIONS, not a unit arm. The converge angle only means anything relative to the ratio of the
	# shoulder half-span (0.27 m) to the arm's reach: 0.376 x the 2 m box below gives the 0.753 m the real rig
	# measures, so 24 deg closes the fists onto the centreline here exactly as it does in game. A unit-scale arm
	# over-rotates and the hands cross past each other, which grades the test rig rather than the feature.
	bms.arm_scale = 0.376
	bms.arm_hold_pitch = hold_pitch
	for side in 2:
		var arm := Node3D.new()
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 2.0)
		mi.mesh = box
		mi.position = Vector3(0.0, 0.0, 1.0)
		arm.add_child(mi)
		bms.add_child(arm)
		if side == 0:
			bms._arm_left = arm
		else:
			bms._arm_right = arm
	bms._apply_arm_transform()
	return bms


## Pose both arms exactly as _animate_limbs does with the weapon UP: hold pitch, the inward converge yaw, and the
## fore/aft stagger. `_animate_limbs` needs a live _process, so off-tree tests write the same expression by hand.
func _pose_holding(bms: Node, hold_blend: float = 1.0) -> void:
	var converge: float = bms.arm_hold_converge_deg * hold_blend
	var stagger := Vector3(0.0, 0.0, bms.arm_hold_stagger * hold_blend)
	var rot: Vector3 = bms.arm_rotation + Vector3(bms.arm_hold_pitch, 0.0, 0.0)
	bms._arm_left.transform = bms._arm_pose(rot, stagger, converge)
	bms._arm_right.transform = bms._reflect() * bms._arm_pose(rot, -stagger, converge)


## Minimal duck-typed host that reports an aim elevation. BodyModelSwap reads `aim_pitch_degrees()` off its
## PARENT by name, so a bare Node3D carrying it is all the arm rig needs.
class _AimHost extends Node3D:
	var pitch_deg: float = 0.0
	func aim_pitch_degrees() -> float:
		return pitch_deg


# --- weapon_grip_position -------------------------------------------------------------------------------

func test_no_arms_means_no_grip_so_the_host_keeps_its_authored_anchor() -> void:
	# A bare mob, a swap that has not rebuilt, or a rig with no arm_model must return NULL rather than a zero
	# vector — the host has to be able to tell "no hands" from "hands at the origin" and fall back.
	var bms = load(SWAP_PATH).new()
	assert_null(bms.weapon_grip_position(), "no arm nodes -> nothing to hold a weapon with")
	bms.free()

func test_grip_sits_on_the_centreline_between_the_two_hands() -> void:
	var bms = _swap_with_arms()
	var grip: Variant = bms.weapon_grip_position()
	assert_true(grip is Vector3, "a swap with arms offers a grip point")
	assert_almost_eq((grip as Vector3).x, 0.0, 0.0001,
		"the hands mirror across X, so their midpoint is the body centreline — the two-handed hold")
	bms.free()

func test_grip_is_out_at_the_hands_not_back_at_the_shoulder() -> void:
	# The bug this whole seam exists to kill: the gun used to hang at a fixed anchor on the body while the arms
	# reached ~0.7 m past it. The grip must be most of an arm's length away from the shoulder.
	var bms = _swap_with_arms()
	var grip: Vector3 = bms.weapon_grip_position()
	var shoulder := Vector3(0.0, bms.arm_position.y, bms.arm_position.z)  # centreline shoulder height
	var reach: float = bms._arm_reach_measured() * bms.arm_scale
	assert_gt(reach, 0.0, "the arm rig must measure a reach or there is no hand to find")
	assert_almost_eq(grip.distance_to(shoulder), reach * bms.weapon_grip_reach, 0.001,
		"the grip is weapon_grip_reach of the way down the arm — in the palm, not at the shoulder")
	bms.free()

func test_grip_respects_weapon_grip_reach_and_offset() -> void:
	var bms = _swap_with_arms()
	var far: Vector3 = bms.weapon_grip_position()
	bms.weapon_grip_reach = 0.5
	var near: Vector3 = bms.weapon_grip_position()
	var shoulder := Vector3(0.0, bms.arm_position.y, bms.arm_position.z)
	assert_lt(near.distance_to(shoulder), far.distance_to(shoulder),
		"halving weapon_grip_reach pulls the grip back toward the shoulder")
	bms.weapon_grip_reach = 0.92
	var base: Vector3 = bms.weapon_grip_position()
	bms.weapon_grip_offset = Vector3(0.0, 0.05, 0.1)
	assert_almost_eq((bms.weapon_grip_position() as Vector3) - base, bms.weapon_grip_offset, Vector3.ONE * 0.0001,
		"weapon_grip_offset is a straight per-rig nudge on top of the computed grip")
	bms.free()

func test_grip_rises_as_the_arms_raise() -> void:
	# arm_hold_pitch now decides WHERE THE WEAPON IS, not just how the arms look.
	var low = _swap_with_arms(-40.0)
	var high = _swap_with_arms(-90.0)
	# _apply_arm_transform writes the REST pose; the hold pitch reaches the arms through _animate_limbs, so pose
	# both rigs by hand at their own hold angle — the same expression _animate_limbs writes.
	for pair in [[low, -40.0], [high, -90.0]]:
		var b = pair[0]
		var pitch: float = pair[1]
		b._arm_left.transform = b._arm_pose(b.arm_rotation + Vector3(pitch, 0.0, 0.0))
		b._arm_right.transform = b._reflect() * b._arm_pose(b.arm_rotation + Vector3(pitch, 0.0, 0.0))
	assert_gt((high.weapon_grip_position() as Vector3).y, (low.weapon_grip_position() as Vector3).y,
		"a hold pitch nearer level (-90) lifts the hands, and the weapon hanging off them")
	low.free()
	high.free()

func test_single_arm_rig_still_offers_a_grip() -> void:
	# The Player's first-person view-model arm (single_arm) leaves _arm_right null; the read must degrade to the
	# one hand it has rather than assuming a pair.
	var bms = _swap_with_arms()
	bms._arm_right.free()
	bms._arm_right = null
	var grip: Variant = bms.weapon_grip_position()
	assert_true(grip is Vector3, "one arm is still a hand")
	assert_almost_eq((grip as Vector3).x, bms.arm_position.x, 0.0001,
		"and with no mirror to average against, the grip sits on that arm's own side")
	bms.free()


# --- aim_pitch_contribution -----------------------------------------------------------------------------

func test_aim_follow_is_zero_without_a_host_that_reports_one() -> void:
	# The Player's FP rig, a civilian, and any unit-test stub have no aim_pitch_degrees() — they must contribute
	# exactly nothing, so those arms behave as they always did.
	var bms = load(SWAP_PATH).new()
	var host := Node3D.new()
	host.add_child(bms)
	assert_almost_eq(bms.aim_pitch_contribution(), 0.0, 0.0001, "no aim_pitch_degrees() on the host -> no swing")
	host.free()

func test_aim_follow_tracks_the_host_and_scales_by_arm_aim_follow() -> void:
	var bms = load(SWAP_PATH).new()
	var host := _AimHost.new()
	host.add_child(bms)
	host.pitch_deg = 20.0
	assert_almost_eq(bms.aim_pitch_contribution(), 20.0, 0.0001, "follow 1.0 tracks the host's elevation exactly")
	bms.arm_aim_follow = 0.5
	assert_almost_eq(bms.aim_pitch_contribution(), 10.0, 0.0001, "and arm_aim_follow scales it")
	bms.arm_aim_follow = 0.0
	assert_almost_eq(bms.aim_pitch_contribution(), 0.0, 0.0001, "zero follow opts the rig out entirely")
	host.free()

func test_aim_follow_is_clamped_symmetrically() -> void:
	var bms = load(SWAP_PATH).new()
	var host := _AimHost.new()
	host.add_child(bms)
	bms.arm_aim_pitch_limit = 55.0
	host.pitch_deg = 80.0
	assert_almost_eq(bms.aim_pitch_contribution(), 55.0, 0.0001,
		"a foe overhead clamps, so the arms cannot fold back through the torso")
	host.pitch_deg = -80.0
	assert_almost_eq(bms.aim_pitch_contribution(), -55.0, 0.0001, "and the clamp is symmetric downward")
	host.free()

func test_raised_arm_target_pitch_subtracts_the_aim_swing() -> void:
	# Sign check, and it is easy to get backwards: this rig raises an arm with a MORE NEGATIVE pitch (see
	# arm_air_pitch -160 = straight up), so an UPWARD aim (positive degrees) must SUBTRACT from arm_hold_pitch.
	var bms = _swap_with_arms(-78.0)
	var host := _AimHost.new()
	host.add_child(bms)
	host.pitch_deg = 30.0
	var target: float = bms.arm_hold_pitch - bms.aim_pitch_contribution()
	assert_lt(target, bms.arm_hold_pitch, "aiming UP drives the arm pitch more negative — the hands rise")
	host.pitch_deg = -30.0
	assert_gt(bms.arm_hold_pitch - bms.aim_pitch_contribution(), bms.arm_hold_pitch,
		"and aiming DOWN drives it back the other way")
	host.free()


# --- the two-handed GRIP: converge + stagger ------------------------------------------------------------
# The rig's shoulders are 0.54 m apart and its arms reach ~0.69 m, so a straight forward hold leaves the two
# fists that far apart with the weapon floating between them — "the hands aren't holding it". Converge swings
# them inward onto the weapon; stagger offsets one ALONG the barrel so they read as a foregrip and a trigger hand.

func test_converge_brings_the_hands_together_on_the_centreline() -> void:
	var bms = _swap_with_arms()
	bms.arm_hold_stagger = 0.0
	bms.arm_hold_converge_deg = 0.0
	_pose_holding(bms)
	var apart_open: float = (bms._arm_left.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())).distance_to(
			bms._arm_right.transform * Vector3(0.0, 0.0, bms._arm_reach_measured()))
	bms.arm_hold_converge_deg = 24.0
	_pose_holding(bms)
	var apart_closed: float = (bms._arm_left.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())).distance_to(
			bms._arm_right.transform * Vector3(0.0, 0.0, bms._arm_reach_measured()))
	assert_lt(apart_closed, apart_open * 0.5,
		"converging must close the fists onto the weapon, not merely narrow the stance a little")
	assert_almost_eq((bms.weapon_grip_position() as Vector3).x, 0.0, 0.0001,
		"and the grip stays on the body centreline — the converge is symmetric, so the weapon does not drift sideways")
	bms.free()

func test_converge_is_a_yaw_not_a_pitch_so_the_hands_stay_level() -> void:
	# The converge is PRE-multiplied about UP. Folded into the arm's own euler instead it would tilt the hold.
	var bms = _swap_with_arms()
	bms.arm_hold_stagger = 0.0
	_pose_holding(bms)
	var l: Vector3 = bms._arm_left.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())
	var r: Vector3 = bms._arm_right.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())
	assert_almost_eq(l.y, r.y, 0.0001, "converging swings the hands inward, never up or down")
	bms.free()

func test_stagger_separates_the_hands_ALONG_the_weapon_not_vertically() -> void:
	# ⭐The regression this pins, caught on screen: the stagger was first written as an antisymmetric PITCH, and
	# at a near-level hold a pitch moves a hand UP and DOWN — so it split the fists 0.23 m vertically instead of
	# offsetting them along the barrel. It is an antisymmetric shift of the shoulder anchors along +Z instead.
	var bms = _swap_with_arms()
	bms.arm_hold_stagger = 0.08
	_pose_holding(bms)
	var l: Vector3 = bms._arm_left.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())
	var r: Vector3 = bms._arm_right.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())
	assert_almost_eq(l.y, r.y, 0.0001, "the two hands stay at the SAME height — a stagger, not a tilt")
	assert_almost_eq(absf(l.z - r.z), 2.0 * bms.arm_hold_stagger, 0.0001,
		"and they are offset along the body's forward axis by twice the authored stagger — one hand leads")
	bms.free()

func test_zero_grip_terms_reproduce_the_plain_forward_reach() -> void:
	# Both knobs are opt-out: zeroed, the pose must be byte-identical to the parallel reach that shipped before.
	var bms = _swap_with_arms()
	bms.arm_hold_converge_deg = 0.0
	bms.arm_hold_stagger = 0.0
	_pose_holding(bms)
	var rot: Vector3 = bms.arm_rotation + Vector3(bms.arm_hold_pitch, 0.0, 0.0)
	assert_eq(bms._arm_left.transform, bms._arm_pose(rot),
		"zero converge + zero stagger is exactly the un-gripped arm pose")
	bms.free()

func test_hold_blend_scales_both_grip_terms_together() -> void:
	# Drawing / holstering fades the grip open and shut on one envelope, so the hands never snap together.
	var bms = _swap_with_arms()
	_pose_holding(bms, 0.0)
	var open_l: Vector3 = bms._arm_left.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())
	_pose_holding(bms, 0.5)
	var half_l: Vector3 = bms._arm_left.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())
	_pose_holding(bms, 1.0)
	var shut_l: Vector3 = bms._arm_left.transform * Vector3(0.0, 0.0, bms._arm_reach_measured())
	assert_lt(absf(half_l.x), absf(open_l.x), "half-closed is already inboard of the open reach")
	assert_lt(absf(shut_l.x), absf(half_l.x), "and fully closed is inboard of that — one monotonic envelope")
	bms.free()
