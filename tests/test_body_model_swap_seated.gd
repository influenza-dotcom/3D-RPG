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

func test_seated_arms_hold_a_drawn_gun_instead_of_resting_in_the_lap() -> void:
	# The armed half of "sitting doesn't mesh with hostile NPCs": hostiles are the NPCs that keep a gun OUT
	# (WeaponStance's always_out), and the seated pose used to ignore it entirely — hands folded into the lap
	# while the rifle hovered beside them. The preferred seated pitch is the STANDING hold angle when the gun is
	# up, because the hand anchor rides the same seated drop (NPC._sync_muzzle_to_posture).
	var host := _GunHost.new()
	var bms = _shipped_seated_swap()
	host.add_child(bms)
	bms.seated_arm_pitch = -25.0
	bms.arm_hold_pitch = -65.0
	assert_almost_eq(bms._seated_preferred_arm_pitch(), -25.0, 0.0001,
		"gun holstered -> the seated arms rest in the authored lap pose")
	host.gun_out = true
	assert_almost_eq(bms._seated_preferred_arm_pitch(), -65.0, 0.0001,
		"gun DRAWN -> the seated arms take the weapon-hold pitch so the hands land on the gun")
	host.free()

func test_seated_gun_hold_respects_the_stealth_telegraph_gates() -> void:
	# arms_hold_when_drawn OFF is the wary/stealth telegraph: the gun stays drawn but the arms stay DOWN until the
	# foe is close AND genuinely sensed. Seated must read identically to standing or a seated enemy would telegraph
	# "I've noticed you" from across the room while a standing one doesn't.
	var host := _GunHost.new()
	var bms = _shipped_seated_swap()
	host.add_child(bms)
	bms.seated_arm_pitch = -25.0
	bms.arm_hold_pitch = -65.0
	bms.arms_hold_when_drawn = false
	bms.arm_raise_range = 10.0
	host.gun_out = true
	host.distance = 25.0
	assert_almost_eq(bms._seated_preferred_arm_pitch(), -25.0, 0.0001,
		"telegraph mode, foe far away -> hands stay in the lap even with the gun drawn")
	host.distance = 4.0
	host.sensed = false
	assert_almost_eq(bms._seated_preferred_arm_pitch(), -25.0, 0.0001,
		"telegraph mode, foe close but NOT sensed -> still the lap (never aim at a player it hasn't noticed)")
	host.sensed = true
	assert_almost_eq(bms._seated_preferred_arm_pitch(), -65.0, 0.0001,
		"telegraph mode, foe close AND sensed -> the hands come up onto the gun")
	host.free()

func test_lower_arms_puts_a_seated_armed_speaker_hands_in_its_lap() -> void:
	# lower_arms() runs from NPC.set_in_dialogue, possibly BEFORE DialogueManager publishes the speaker — so it
	# must clamp seated_arm_pitch directly rather than route through the gun-aware preferred pitch, or an armed
	# NPC you strike up a conversation with would hold its rifle up for the whole (world-paused) chat.
	var host := _GunHost.new()
	var bms = _shipped_seated_swap()
	host.add_child(bms)
	bms.seated_arm_pitch = -25.0
	bms.arm_hold_pitch = -65.0
	bms.arm_scale = 1.0
	bms._arm_reach = 0.6
	host.gun_out = true
	bms.lower_arms()
	assert_almost_eq(bms._mode_pitch, bms._seated_pitch_clamped(bms.seated_arm_pitch), 0.001,
		"a seated ARMED speaker still drops to the clamped lap pitch, not the weapon hold")
	host.free()

func test_posture_offset_public_seam_matches_the_applied_offset() -> void:
	# The seam host-owned nodes glue themselves to the visible body with (NPC._sync_muzzle_to_posture keeps the
	# held gun on it). It must report EXACTLY what the parts are placed with, or the gun drifts off the hands.
	var npc = load(NPC_PATH).new()
	var bms = _shipped_seated_swap()
	npc.add_child(bms)
	npc.sitting = true
	assert_eq(bms.posture_offset(), bms._posture_offset(),
		"posture_offset() is the public read of the same offset every swapped part rides")
	assert_almost_eq(bms.posture_offset().y, -0.675, 0.0001, "and it carries the ground-snapped seated drop")
	npc.sitting = false
	assert_eq(bms.posture_offset(), Vector3.ZERO, "standing -> no offset, so the gun sits at its authored anchor")
	npc.free()

func test_editor_preview_seat_plane_comes_from_the_host_capsule() -> void:
	# WYSIWYG for the seated pose. There is no stepped physics in the editor viewport, so the preview used to show
	# only the fixed seated_visual_offset (-0.28) while the game probed the real ground (~-0.675 on the shipped
	# rig) — a floor-sitter you placed looked like it was hovering in a sitting pose, the "seated body is
	# misaligned" report. A settled capsule rests ON its support, so its BOTTOM is the same plane the ray finds.
	# IN-TREE (global_position/global_basis), on a bare Node3D host — never an NPC, whose _ready must not run.
	var host := _SeatHost.new()
	add_child_autofree(host)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.95
	col.shape = cap
	col.position = Vector3(-0.0104, -0.0284, 0.0221)  # the shipped enemy.tscn CollisionShape placement
	host.add_child(col)
	var bms = load(BMS_PATH).new()
	bms.arm_position = Vector3(-0.27, 0.155, -0.05)
	bms.leg_position = Vector3(0.095, -0.265, -0.02)
	bms.seated_hip_clearance = 0.06
	host.add_child(bms)
	assert_almost_eq(bms._seat_plane_y(), -1.0034, 0.01,
		"with no probe the seat plane is the capsule bottom (~1 m below the origin on the shipped rig)")
	assert_almost_eq(bms._seated_drop_y(), bms._seat_plane_y() + 0.06 + 0.265, 0.0001,
		"so the preview drop lands the hip on that plane, exactly like the runtime probe")
	assert_lt(bms._seated_drop_y(), bms.seated_visual_offset.y,
		"which is much deeper than the old fixed preview offset — that gap WAS the misalignment")
	bms.seated_snap_to_ground = false
	assert_almost_eq(bms._seated_drop_y(), bms.seated_visual_offset.y, 0.0001,
		"snap OFF still hands the drop back to the author, capsule or not")

## Minimal in-tree host for the capsule-derived seat plane: BodyModelSwap only needs a parent that reports
## is_sitting() and carries a CollisionShape3D. Deliberately NOT an NPC (CLAUDE.md: no NPC._ready in a test).
class _SeatHost extends Node3D:
	var sitting: bool = true
	func is_sitting() -> bool:
		return sitting

func test_seated_snap_off_keeps_the_authored_drop() -> void:
	# seated_snap_to_ground OFF means "I'm authoring this drop myself" — neither the probe nor the capsule-bottom
	# estimate may override it, or a deliberately hand-placed pose (legs dangling off a ledge) snaps flat.
	var bms = _shipped_seated_swap()
	bms._seat_ground_valid = false
	bms.seated_snap_to_ground = false
	assert_almost_eq(bms._seated_drop_y(), bms.seated_visual_offset.y, 0.0001,
		"snap off -> the authored seated_visual_offset.y stands, in the editor and at runtime alike")
	bms.free()

## Minimal duck-typed host for the seated gun-hold gates: BodyModelSwap reads these off its PARENT by name, so a
## bare Node3D with them is all the pose needs (and it never runs NPC._ready — see CLAUDE.md).
class _GunHost extends Node3D:
	var sitting: bool = true
	var gun_out: bool = false
	var distance: float = 1.0
	var sensed: bool = true
	func is_sitting() -> bool:
		return sitting
	func is_holding_gun() -> bool:
		return gun_out
	func aim_distance() -> float:
		return distance
	func has_sensed_foe() -> bool:
		return sensed

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
