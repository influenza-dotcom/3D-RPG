extends GutTest

## NpcHeadLookMount's PURE aim math (the off-tree-safe core of the Fallout-style head tracking). The actual head
## rotation, the rig-forward-axis sign, and the look feel are manual-playtest (gated behind
## GameSettings.npc_ai.head_look = false until then) -- exactly the A/B idiom the stealth / GOAP slices use. Here
## we pin the yaw/pitch decomposition, the cone gate, and the easing, none of which touch the tree.
##
## preload (path-based) instead of the bare NpcHeadLookMount class_name, so the suite resolves the static helpers
## even before the editor has scanned the script into its class cache (avoids the new-class_name GUT cascade).

const HL := preload("res://scripts/components/npc_head_look_mount.gd")

const EPS := 0.0001


func test_aim_offsets_dead_ahead_is_neutral() -> void:
	var o := HL.aim_offsets(Vector3.ZERO, Vector3(0.0, 0.0, 5.0), 0.0)
	assert_almost_eq(o.x, 0.0, EPS, "a target straight ahead (+Z) needs no head yaw")
	assert_almost_eq(o.y, 0.0, EPS, "a level target needs no head pitch")


func test_aim_offsets_side_target_yaws() -> void:
	# Target on the +X side, body facing +Z: yaw = atan2(5, 0) = +90 deg.
	var o := HL.aim_offsets(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), 0.0)
	assert_almost_eq(rad_to_deg(o.x), 90.0, 0.01, "a target to the right yaws the head +90 deg")


func test_aim_offsets_yaw_is_relative_to_body() -> void:
	# Body already faces +X (yaw 90 deg) and the target is at +X -> the head needs no offset (body is aligned).
	var o := HL.aim_offsets(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), deg_to_rad(90.0))
	assert_almost_eq(o.x, 0.0, 0.001, "head yaw is measured RELATIVE to the body's facing, not world axes")


func test_aim_offsets_pitch_up_and_down() -> void:
	var up := HL.aim_offsets(Vector3.ZERO, Vector3(0.0, 5.0, 5.0), 0.0)
	assert_gt(up.y, 0.0, "a target above eye level pitches the head UP (+)")
	var down := HL.aim_offsets(Vector3.ZERO, Vector3(0.0, -5.0, 5.0), 0.0)
	assert_lt(down.y, 0.0, "a target below eye level pitches the head DOWN (-)")


func test_in_cone_passes_inside() -> void:
	assert_true(
		HL.in_cone(5.0, deg_to_rad(10.0), deg_to_rad(5.0), 12.0, deg_to_rad(70.0), deg_to_rad(35.0)),
		"in range and inside both cones -> the head may track it")


func test_in_cone_rejects_out_of_range_or_cone() -> void:
	assert_false(HL.in_cone(20.0, 0.0, 0.0, 12.0, deg_to_rad(70.0), deg_to_rad(35.0)),
		"past look_range -> neutral (head doesn't track a far target)")
	assert_false(HL.in_cone(5.0, deg_to_rad(80.0), 0.0, 12.0, deg_to_rad(70.0), deg_to_rad(35.0)),
		"past the yaw cone -> neutral (the body must turn first, head won't crane)")
	assert_false(HL.in_cone(5.0, 0.0, deg_to_rad(50.0), 12.0, deg_to_rad(70.0), deg_to_rad(35.0)),
		"past the pitch cone -> neutral")


func test_ease_toward_converges_to_target_and_neutral() -> void:
	var v := 0.0
	for _i in 300:
		v = HL.ease_toward(v, 1.0, 6.0, 1.0 / 60.0)
	assert_almost_eq(v, 1.0, 0.001, "the exponential ease converges to its target angle")
	for _i in 300:
		v = HL.ease_toward(v, 0.0, 6.0, 1.0 / 60.0)
	assert_almost_eq(v, 0.0, 0.001, "and eases back to neutral when the target clears")


func test_ease_toward_is_frame_rate_independent() -> void:
	# Same total time, different step counts -> near-identical result (the 1 - exp(-k*dt) shape).
	var a := 0.0
	for _i in 60:
		a = HL.ease_toward(a, 1.0, 6.0, 1.0 / 60.0)
	var b := 0.0
	for _i in 120:
		b = HL.ease_toward(b, 1.0, 6.0, 1.0 / 120.0)
	assert_almost_eq(a, b, 0.02, "easing over the same wall-clock converges alike at 60 vs 120 fps")


# --- resolve_look_point: the perception-TRUTHFUL priority (the "look without seeing" fix) ----------------------
# The brain (npc.gd.head_look_point) resolves the four channel bools from live perception, then this pure static
# picks the point. These pin the ordering AND, crucially, that a channel is IGNORED when its bool is false — so an
# NPC never points its head at a foe/player it can't currently sense.

const FOE := Vector3(1.0, 0.0, 0.0)
const LKP := Vector3(2.0, 0.0, 0.0)      # last-known position
const PLR := Vector3(3.0, 0.0, 0.0)      # player look point
const RAD := Vector3(4.0, 0.0, 0.0)      # radio position


func test_resolve_seen_foe_wins() -> void:
	# ALERTED (foe_visible) outranks everything, including a lower-priority player glance.
	var p: Variant = HL.resolve_look_point(true, FOE, true, LKP, true, PLR, true, RAD)
	assert_eq(p, FOE, "a foe we currently SEE is the head's top priority")


func test_resolve_aware_but_unseen_looks_at_last_known_not_foe() -> void:
	# The stealth fix: a foe is in range (aware) but NOT currently seen (foe_visible false, e.g. we lost the line
	# and dropped to INVESTIGATING). The head must look at the last-known spot, NEVER snap to a live foe point.
	var p: Variant = HL.resolve_look_point(false, FOE, true, LKP, true, PLR, true, RAD)
	assert_eq(p, LKP, "aware-but-unseen looks at the last spot we sensed, not a foe we can't see")


func test_resolve_idle_glances_at_seen_player() -> void:
	# No foe, not aware, but the caller confirmed we can genuinely see a nearby player -> the ambient glance.
	var p: Variant = HL.resolve_look_point(false, FOE, false, LKP, true, PLR, true, RAD)
	assert_eq(p, PLR, "an idle NPC glances at a player it can actually see")


func test_resolve_unseen_player_is_ignored() -> void:
	# THE core "look without seeing" gate: the player channel is OFF (can_glance false, because the brain's
	# can_see_node failed — wall / behind the back / out of range). The head must fall through to the radio, never
	# to the player point.
	var p: Variant = HL.resolve_look_point(false, FOE, false, LKP, false, PLR, true, RAD)
	assert_eq(p, RAD, "a player we can't see is IGNORED — the head does not track it")


func test_resolve_nothing_to_look_at_is_null() -> void:
	# Every channel off -> null (distinct from the world origin) so the head eases back to neutral.
	var p: Variant = HL.resolve_look_point(false, FOE, false, LKP, false, PLR, false, RAD)
	assert_null(p, "with nothing sensed, the head has no look target (eases to neutral)")


func test_resolve_radio_is_lowest_priority() -> void:
	# The radio only wins when no foe, no awareness, and no visible player claim the head.
	assert_eq(HL.resolve_look_point(false, FOE, false, LKP, false, PLR, true, RAD), RAD,
		"radio wins only when nothing else does")
	assert_eq(HL.resolve_look_point(false, FOE, true, LKP, false, PLR, true, RAD), LKP,
		"awareness outranks the radio")
