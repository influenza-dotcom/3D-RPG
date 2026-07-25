extends GutTest

## Pins the seated GROUND-SNAP contracts on BodyModelSwap (seated_snap_to_ground): the drop math that lands the
## hips flush on the probed surface (with the authored seated_visual_offset as the no-probe fallback), and the
## arm floor-clamp (seated_pitch_to_clear) that auto-raises the seated arm pitch so the hands rest above the
## surface instead of hanging through the floor. The probe itself (a physics ray) is in-tree/runtime and stays
## manual-playtest; everything here fakes its cached result (_seat_ground_valid/_seat_ground_y) and checks pure
## math. Built off-tree (.new(), no add_child -> no _ready/_rebuild), headless-safe (CLAUDE.md).

const NPC_PATH := "res://scripts/npc/npc.gd"
const BMS_PATH := "res://scripts/components/body_model_swap.gd"

## The shipped enemy.tscn seated geometry, so the numbers below mean something: hip (leg_position) at y -0.265,
## shoulder (arm_position) at y 0.155, ground probed 1.0 below the NPC origin.
func _shipped_seated_swap() -> Node:
	var bms = load(BMS_PATH).new()
	bms.arm_position = Vector3(-0.27, 0.155, -0.05)
	bms.leg_position = Vector3(0.095, -0.265, -0.02)
	bms.seated_hip_clearance = 0.06
	bms.seated_hand_clearance = 0.05
	bms._seat_ground_valid = true
	bms._seat_ground_y = -1.0
	return bms

# --- seated_pitch_to_clear (pure static clamp math) -------------------------------------------------------------

func test_pitch_clamp_keeps_preferred_when_room_is_ample() -> void:
	var got := BodyModelSwap.seated_pitch_to_clear(-25.0, 1.0, 0.6)
	assert_almost_eq(got, -25.0, 0.0001, "reach 0.6 into 1.0 of room already clears -> the authored pitch survives")

func test_pitch_clamp_raises_the_arm_to_clear_the_floor() -> void:
	# reach 0.6 hanging at -25 drops cos(25)*0.6 = 0.54 into 0.3 of room -> must raise to acos(0.3/0.6) = 60.
	var got := BodyModelSwap.seated_pitch_to_clear(-25.0, 0.3, 0.6)
	assert_almost_eq(got, -60.0, 0.001, "too little room -> pitch raises to exactly clear (acos(room/reach))")
	assert_gt(absf(got), 25.0, "the clamp only ever RAISES past the authored pitch, never lowers")

func test_pitch_clamp_pins_horizontal_with_no_room() -> void:
	assert_almost_eq(BodyModelSwap.seated_pitch_to_clear(-25.0, 0.0, 0.6), -90.0, 0.0001,
		"zero room below the shoulder pins the arm horizontal")
	assert_almost_eq(BodyModelSwap.seated_pitch_to_clear(-25.0, -0.2, 0.6), -90.0, 0.0001,
		"a shoulder already below the surface pins the arm horizontal too")

func test_pitch_clamp_preserves_the_authored_swing_direction() -> void:
	var got := BodyModelSwap.seated_pitch_to_clear(14.0, 0.0, 0.6)
	assert_almost_eq(got, 90.0, 0.0001, "a positive (backward-authored) pitch clamps positive — sign is the author's")

func test_pitch_clamp_is_a_noop_with_no_measurable_arm() -> void:
	assert_almost_eq(BodyModelSwap.seated_pitch_to_clear(-25.0, 0.1, 0.0), -25.0, 0.0001,
		"zero reach (no arm model measured) leaves the authored pitch alone")

# --- _seated_drop_y (ground-snap drop) --------------------------------------------------------------------------

func test_seated_drop_lands_the_hip_on_the_probed_surface() -> void:
	var bms = _shipped_seated_swap()
	# Hip must land at ground + clearance: -1.0 + 0.06 = -0.94; the hip sits at leg_position.y, so the drop is
	# -0.94 - (-0.265) = -0.675 — far deeper than the fixed -0.28 chair offset ever reached.
	assert_almost_eq(bms._seated_drop_y(), -0.675, 0.0001,
		"probe hit -> the drop puts leg_position.y at seated_hip_clearance above the surface")
	bms.free()

func test_seated_drop_falls_back_to_the_authored_offset_without_a_probe() -> void:
	var bms = _shipped_seated_swap()
	bms._seat_ground_valid = false
	assert_almost_eq(bms._seated_drop_y(), bms.seated_visual_offset.y, 0.0001,
		"no probe hit (editor / miss / snap off) -> the authored seated_visual_offset.y drop")
	bms.free()

func test_apply_body_transform_consumes_the_snapped_drop() -> void:
	# The TORSO must ride the same _posture_offset() seam as the head/arms/legs. The regression this pins: the
	# body position used the raw authored seated_visual_offset while everything else ground-snapped, leaving the
	# torso floating ~0.4 m over its own hips on every runtime sitter. _body is stubbed with a bare Node3D (no
	# _rebuild off-tree), which is all _apply_body_transform needs.
	var npc = load(NPC_PATH).new()
	var bms = _shipped_seated_swap()
	npc.add_child(bms)
	var body := Node3D.new()
	bms.add_child(body)
	bms._body = body
	npc.sitting = true
	bms._apply_body_transform()
	assert_almost_eq(body.position.y, -0.675, 0.0001,
		"the seated torso drops by the ground-snapped offset, exactly like the limbs (never the raw authored Y)")
	npc.free()

func test_posture_offset_snaps_y_and_keeps_authored_xz() -> void:
	var npc = load(NPC_PATH).new()
	var bms = _shipped_seated_swap()
	npc.add_child(bms)
	npc.sitting = true
	var off: Vector3 = bms._posture_offset()
	assert_almost_eq(off.y, -0.675, 0.0001, "seated offset Y comes from the ground snap")
	assert_almost_eq(off.x, bms.seated_visual_offset.x, 0.0001, "authored X survives the snap")
	assert_almost_eq(off.z, bms.seated_visual_offset.z, 0.0001, "authored Z survives the snap")
	npc.sitting = false
	assert_eq(bms._posture_offset(), Vector3.ZERO, "standing hosts get no posture offset at all")
	npc.free()

# --- _seated_arm_pitch_eff (the two combined) -------------------------------------------------------------------

func test_seated_arm_pitch_raises_off_the_measured_reach() -> void:
	var bms = _shipped_seated_swap()
	bms.seated_arm_pitch = -25.0
	bms.arm_scale = 1.0
	bms._arm_reach = 0.6  # pre-measured (no _arm_left off-tree, so _arm_reach_measured returns this as-is)
	# Shoulder after the -0.675 drop: 0.155 - 0.675 = -0.52; room above the clearance plane (-0.95):
	# -0.52 - (-1.0 + 0.05) = 0.43 -> needed pitch acos(0.43/0.6). NOTE the 0.43 is constant BY CONSTRUCTION of
	# the snap (arm_position.y - leg_position.y + hip_clearance - hand_clearance — the probed ground cancels out),
	# so every probe-valid sitter lands on this same clamped angle; that contract is documented on
	# seated_arm_pitch, and this test enshrines it deliberately.
	var want := -rad_to_deg(acos(0.43 / 0.6))
	assert_almost_eq(bms._seated_arm_pitch_eff(), want, 0.001,
		"the effective seated pitch raises the hands to seated_hand_clearance above the probed surface")
	assert_gt(absf(bms._seated_arm_pitch_eff()), 25.0, "the ground-level seat forces a steeper pitch than the authored -25")
	bms.free()

func test_seated_arm_pitch_stays_authored_without_a_probe() -> void:
	var bms = _shipped_seated_swap()
	bms._seat_ground_valid = false
	bms.seated_arm_pitch = -25.0
	assert_almost_eq(bms._seated_arm_pitch_eff(), -25.0, 0.0001,
		"no probe (editor / snap off) -> the authored seated_arm_pitch, unclamped")
	bms.free()

func test_lower_arms_holds_the_seated_pose_for_a_seated_speaker() -> void:
	# Dialogue pauses the world and freezes the gait, so lower_arms' static write IS the pose for the whole
	# conversation — a seated speaker must land on the seated (floor-cleared) pitch, not the standing hang.
	var npc = load(NPC_PATH).new()
	var bms = _shipped_seated_swap()
	npc.add_child(bms)
	bms.seated_arm_pitch = -25.0
	bms.arm_scale = 1.0
	bms._arm_reach = 0.6
	npc.sitting = true
	bms.lower_arms()
	assert_almost_eq(bms._mode_pitch, bms._seated_arm_pitch_eff(), 0.001,
		"a seated speaker's arms settle on the seated floor-cleared pitch")
	npc.sitting = false
	bms.lower_arms()
	assert_eq(bms._mode_pitch, 0.0, "a standing speaker still drops the arms to the by-the-side rest")
	npc.free()
