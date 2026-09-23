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
##
## The HOLD itself is posed by the production gait, `_animate_limbs`, driven directly under a duck-typed armed host
## (`_process` would need the tree). Never pose the arms by hand here: a test that composes the hold pitch, the aim
## swing, the converge and the stagger itself grades its own arithmetic, not the pose the NPC actually wears.

const SWAP_PATH := "res://scripts/components/body_model_swap.gd"

## One gait frame long enough that every eased arm term (the slowest rate in _animate_limbs is 10/s) lands on its
## target: the settled hold, with no easing left in it.
const SETTLE_DELTA: float = 10.0
## One ordinary render frame, for the tests that watch the easing itself.
const FRAME_DELTA: float = 1.0 / 60.0

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


## Minimal duck-typed host that reports an aim elevation. BodyModelSwap reads `aim_pitch_degrees()` off its
## PARENT by name, so a bare Node3D carrying it is all the arm rig needs.
class _AimHost extends Node3D:
	var pitch_deg: float = 0.0
	func aim_pitch_degrees() -> float:
		return pitch_deg


## An NPC-shaped host with its weapon drawn: `is_holding_gun()` is what raises the arms onto the weapon in
## _animate_limbs. No is_on_floor / velocity / is_fists_out, so the gait reads it as a grounded, standing, armed body.
class _ArmedHost extends _AimHost:
	var gun_out: bool = true
	func is_holding_gun() -> bool:
		return gun_out


## Parent `bms` under an armed host (freeing the host frees the swap).
func _armed(bms: Node) -> _ArmedHost:
	var host := _ArmedHost.new()
	host.add_child(bms)
	return host


## Run the real gait until the hold has settled.
func _settle(bms: Node) -> void:
	bms._animate_limbs(SETTLE_DELTA, false)


## Both hand tips (swap-local), [left, right], at the arms' current pose.
func _hands(bms: Node) -> Array[Vector3]:
	var tip := Vector3(0.0, 0.0, bms._arm_reach_measured())
	return [bms._arm_left.transform * tip, bms._arm_right.transform * tip]


## The two grip terms READ BACK off the posed arms: x = the LEFT arm's inward yaw about UP (degrees) and y = how far
## ahead of the right hand the left one leads, per hand (metres). The arm's own rotation here is a pure pitch, so its
## hand axis has no X component and the yaw of (hand - shoulder anchor) in the XZ plane IS the applied converge;
## the fore/aft split of the two mirrored hands is twice the applied stagger whatever the pitch or converge.
func _grip_terms(bms: Node) -> Vector2:
	var h := _hands(bms)
	var stagger: float = (h[0].z - h[1].z) * 0.5
	var from_shoulder: Vector3 = h[0] - (bms.arm_position + Vector3(0.0, 0.0, stagger))
	return Vector2(rad_to_deg(atan2(from_shoulder.x, from_shoulder.z)), stagger)


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
	# arm_hold_pitch now decides WHERE THE WEAPON IS, not just how the arms look: two armed NPCs that differ only in
	# their authored hold angle, posed by the real gait.
	var low = _swap_with_arms(-40.0)
	var high = _swap_with_arms(-90.0)
	var low_host := _armed(low)
	var high_host := _armed(high)
	_settle(low)
	_settle(high)
	assert_gt((high.weapon_grip_position() as Vector3).y, (low.weapon_grip_position() as Vector3).y,
		"a hold pitch nearer level (-90) lifts the hands, and the weapon hanging off them")
	low_host.free()
	high_host.free()

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

func test_aiming_up_lifts_the_held_grip_and_aiming_down_drops_it() -> void:
	# The sign is easy to get backwards: this rig raises an arm with a MORE NEGATIVE pitch (arm_air_pitch -160 is
	# straight up), while a positive aim elevation means UP. Judged where the player sees it — the height of the
	# grip the NPC hangs its gun from — after the real gait has posed the arms.
	var bms = _swap_with_arms(-78.0)
	var host := _armed(bms)
	host.pitch_deg = 0.0
	_settle(bms)
	var level_y: float = (bms.weapon_grip_position() as Vector3).y
	host.pitch_deg = 30.0
	_settle(bms)
	var up_y: float = (bms.weapon_grip_position() as Vector3).y
	host.pitch_deg = -30.0
	_settle(bms)
	var down_y: float = (bms.weapon_grip_position() as Vector3).y
	assert_gt(up_y, level_y, "a foe ABOVE must lift the hands and the gun hanging off them, not drop them")
	assert_lt(down_y, level_y, "a foe BELOW must lower the hands and the gun")
	# CONTROL: the same rig with the aim follow opted out holds the level grip at the same +30 elevation, so the
	# rise above really is the aim swing and not left-over easing.
	bms.arm_aim_follow = 0.0
	host.pitch_deg = 30.0
	_settle(bms)
	assert_almost_eq((bms.weapon_grip_position() as Vector3).y, level_y, 0.0001,
		"arm_aim_follow 0 must keep the grip at the level-hold height whatever the host's aim elevation")
	host.free()


# --- the two-handed GRIP: converge + stagger ------------------------------------------------------------
# The rig's shoulders are 0.54 m apart and its arms reach ~0.69 m, so a straight forward hold leaves the two
# fists that far apart with the weapon floating between them — "the hands aren't holding it". Converge swings
# them inward onto the weapon; stagger offsets one ALONG the barrel so they read as a foregrip and a trigger hand.

func test_converge_brings_the_hands_together_on_the_centreline() -> void:
	var bms = _swap_with_arms()
	var host := _armed(bms)
	bms.arm_hold_stagger = 0.0
	bms.arm_hold_converge_deg = 0.0
	_settle(bms)
	var open := _hands(bms)
	var apart_open: float = open[0].distance_to(open[1])
	bms.arm_hold_converge_deg = 24.0
	_settle(bms)
	var closed := _hands(bms)
	var apart_closed: float = closed[0].distance_to(closed[1])
	assert_lt(apart_closed, apart_open * 0.5,
		"converging must close the fists onto the weapon, not merely narrow the stance a little")
	assert_almost_eq((bms.weapon_grip_position() as Vector3).x, 0.0, 0.0001,
		"and the grip stays on the body centreline — the converge is symmetric, so the weapon does not drift sideways")
	host.free()

func test_converge_is_a_yaw_not_a_pitch_so_the_hands_stay_level() -> void:
	# The converge is PRE-multiplied about UP, so it only swings each hand sideways in the horizontal plane. Turned
	# about any other axis (a pitch, or a roll of the already-pitched arm) it would lift or drop the whole hold. The
	# right arm is the left one mirrored, so the two hands ALWAYS match each other's height — "level" is therefore
	# judged against the SAME settled hold with the converge zeroed, not left hand against right.
	var bms = _swap_with_arms()
	var host := _armed(bms)
	var shipped_converge: float = bms.arm_hold_converge_deg
	bms.arm_hold_stagger = 0.0
	bms.arm_hold_converge_deg = 0.0
	_settle(bms)
	var open := _hands(bms)
	bms.arm_hold_converge_deg = shipped_converge
	_settle(bms)
	var closed := _hands(bms)
	# CONTROL: the converge really moved the hands, so the height checks below compare two different poses.
	assert_gt(closed[0].x, open[0].x + 0.1,
		"control: the shipped converge swings the left hand inward toward the centreline")
	assert_lt(closed[1].x, open[1].x - 0.1, "control: ...and the right hand inward from the other side")
	assert_almost_eq(closed[0].y, open[0].y, 0.0001,
		"converging swings the left hand inward, never up or down — the hold stays at the height the pitch put it")
	assert_almost_eq(closed[1].y, open[1].y, 0.0001, "...and the right hand keeps its height too")
	host.free()

func test_stagger_separates_the_hands_along_the_weapon_not_vertically() -> void:
	# ⭐The regression this pins, caught on screen: the stagger was first written as an antisymmetric PITCH, and
	# at a near-level hold a pitch moves a hand UP and DOWN — so it split the fists 0.23 m vertically instead of
	# offsetting them along the barrel. It is an antisymmetric shift of the shoulder anchors along +Z instead.
	var bms = _swap_with_arms()
	var host := _armed(bms)
	bms.arm_hold_stagger = 0.08
	_settle(bms)
	var h := _hands(bms)
	assert_almost_eq(h[0].y, h[1].y, 0.0001, "the two hands stay at the SAME height — a stagger, not a tilt")
	assert_almost_eq(absf(h[0].z - h[1].z), 2.0 * bms.arm_hold_stagger, 0.0001,
		"and they are offset along the body's forward axis by twice the authored stagger — one hand leads")
	host.free()

func test_zeroed_grip_knobs_hold_the_hands_in_a_plain_parallel_reach() -> void:
	# Both knobs are opt-out: zeroed, a drawn weapon is held the way it was before the grip existed — each hand
	# straight out in front of its own shoulder, side by side, neither leading.
	var bms = _swap_with_arms()
	var host := _armed(bms)
	bms.arm_hold_converge_deg = 0.0
	bms.arm_hold_stagger = 0.0
	_settle(bms)
	var h := _hands(bms)
	assert_almost_eq(h[0].x, bms.arm_position.x, 0.0001,
		"zero converge: the left hand must reach straight ahead of the left shoulder, not swing inward")
	assert_almost_eq(h[1].x, -bms.arm_position.x, 0.0001, "...and the right hand ahead of the right shoulder")
	assert_almost_eq(h[0].z, h[1].z, 0.0001, "zero stagger: neither hand leads the other along the weapon")
	# CONTROL: the shipped knobs on the same armed rig DO move both, so the checks above can tell the grip apart.
	bms.arm_hold_converge_deg = 24.0
	bms.arm_hold_stagger = 0.08
	_settle(bms)
	var gripped := _hands(bms)
	assert_gt(gripped[0].x, bms.arm_position.x + 0.1, "with the shipped converge the left hand swings in toward the centreline")
	assert_gt(gripped[0].z - gripped[1].z, 0.1, "with the shipped stagger the left hand leads the right")
	host.free()

func test_drawing_eases_both_grip_terms_closed_on_one_envelope() -> void:
	# Drawing / holstering fades the grip open and shut on ONE envelope, so the hands never snap together and the
	# lead hand never arrives before the hands have closed. Watched frame by frame through the real gait.
	var bms = _swap_with_arms()
	var host := _armed(bms)
	host.gun_out = false
	_settle(bms)  # holstered: grip fully open
	host.gun_out = true
	var frames: Array[Vector2] = []
	for _i in 20:
		bms._animate_limbs(FRAME_DELTA, false)
		frames.append(_grip_terms(bms))
	_settle(bms)
	var closed := _grip_terms(bms)
	assert_gt(closed.x, 1.0, "harness: the settled hold must show a real converge yaw")
	assert_gt(closed.y, 0.01, "harness: the settled hold must show a real stagger")
	var prev := -1.0
	for i in frames.size():
		var converge_frac: float = frames[i].x / closed.x
		var stagger_frac: float = frames[i].y / closed.y
		assert_almost_eq(converge_frac, stagger_frac, 0.001,
			"frame %d after drawing: the converge (%.3f closed) and the stagger (%.3f closed) must ease on the same envelope" % [i + 1, converge_frac, stagger_frac])
		assert_gt(converge_frac, prev, "frame %d: the hands keep closing on the weapon every frame after the draw" % (i + 1))
		prev = converge_frac
	var first: float = frames[0].x / closed.x
	assert_gt(first, 0.0, "one frame after drawing, the hands have started to close")
	assert_lt(first, 0.5, "...but must not SNAP shut in a single frame")
	assert_gt(prev, 0.9, "a third of a second after drawing, the grip is essentially closed")
	# Holstering opens them on the same eased envelope rather than snapping them apart.
	host.gun_out = false
	bms._animate_limbs(FRAME_DELTA, false)
	var opening := _grip_terms(bms)
	assert_lt(opening.x / closed.x, 1.0, "one frame after holstering, the hands have started to open")
	assert_gt(opening.x / closed.x, 0.5, "...but must not snap open in a single frame")
	assert_almost_eq(opening.x / closed.x, opening.y / closed.y, 0.001,
		"and the lead hand falls back on the same envelope the converge opens on")
	host.free()
