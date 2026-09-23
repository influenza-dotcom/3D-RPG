extends GutTest

## NpcLook (scripts/npc/npc_look.gd): the reusable per-NPC appearance resource. After the fold, an NPC's
## appearance is overridden SOLELY via its `look` resource -- the inline body/head/arm/leg fields were removed
## from npc.gd, and the shared default look lives on the BodyModelSwap child. Verifies that an untouched look overrides
## nothing, that the NPC no longer carries the inline fields, and that BodyModelSwap resolves a look over its own default.
## Built off-tree (no SceneTree entry) so no NPC _ready runs (CLAUDE.md).

const NPC_PATH := "res://scripts/npc/npc.gd"
const BMS_PATH := "res://scripts/components/body_model_swap.gd"

class _LookHost extends Node3D:
	var look: NpcLook = null

## First entry in get_property_list() whose name matches, else {}.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

func _part_node(parts: Array, key: String) -> Node3D:
	for entry in parts:
		if entry is Dictionary and entry.get("key", "") == key:
			return entry.get("node", null) as Node3D
	return null

func test_a_fresh_npc_look_overrides_nothing() -> void:
	# NpcLook's contract: a field left at its default means "no override for this part", so a designer can start a
	# look from New Resource, set ONE thing, and every other part keeps the BodyModelSwap child's shared default.
	# Driven through the real resolver (not by reading the defaults back), so a default that stops being the
	# resolver's "leave it" sentinel -- e.g. a grey default tint -- fails here because it would re-skin every NPC.
	var npc = load(NPC_PATH).new()
	var bms = load(BMS_PATH).new()
	npc.add_child(bms)  # off-tree: get_parent() without _ready/_rebuild
	var own_body := BoxMesh.new()
	var own_head := SphereMesh.new()
	var red := Color(1, 0, 0)
	bms.body_model = own_body
	bms.body_model_scale = 0.3
	bms.head_model = own_head
	bms.body_color = red
	bms.head_color = red
	bms.arm_color = red
	bms.leg_color = red
	npc.look = NpcLook.new()  # untouched look
	var body: Dictionary = bms._eff_body()
	var head: Dictionary = bms._eff_head()
	assert_eq(body["model"], own_body, "an untouched look keeps the child's body model")
	assert_almost_eq(float(body["scale"]), 0.3, 0.0001, "...and its body scale (a look scale only applies with a look model)")
	assert_eq(body["col"], red, "an untouched look keeps the child's body tint")
	assert_eq(head["model"], own_head, "an untouched look keeps the child's head model")
	assert_eq(head["col"], red, "an untouched look keeps the child's head tint")
	assert_eq(bms._eff_arm_color(), red, "an untouched look keeps the child's arm tint")
	assert_eq(bms._eff_leg_color(), red, "an untouched look keeps the child's leg tint")
	# Control: the SAME setup with one field set on the look does override that part (and only that part).
	var green := Color(0, 1, 0)
	npc.look.leg_color = green
	assert_eq(bms._eff_leg_color(), green, "control: a look that sets leg_color re-tints the legs")
	assert_eq(bms._eff_arm_color(), red, "...while the untouched arm tint still falls through to the child")
	npc.free()

func test_npc_look_model_fields_accept_scene_or_mesh() -> void:
	var lk := NpcLook.new()
	for field in ["body_model", "head_model"]:
		var prop := _property(lk, field)
		assert_eq(prop.get("hint", -1), PROPERTY_HINT_RESOURCE_TYPE,
			"NpcLook.%s uses a resource-type hint" % field)
		assert_eq(prop.get("hint_string", ""), "PackedScene,Mesh",
			"NpcLook.%s accepts .glb/.gltf/.blend PackedScene imports and .obj Mesh imports" % field)
	lk = null

func test_npc_appearance_is_only_the_look_resource() -> void:
	# The fold removed the 14 inline appearance fields from the NPC; `look` is now the sole per-instance override.
	var npc = load(NPC_PATH).new()
	assert_false(_property(npc, "look").is_empty(), "NPC must expose a `look` export")
	for gone in ["body_model", "body_texture", "body_color", "head_model", "head_model_scale", "arm_color", "leg_color"]:
		assert_true(_property(npc, gone).is_empty(),
			"inline appearance field '%s' must be gone from the NPC (folded into NpcLook)" % gone)
	npc.free()

func test_body_model_swap_resolves_look_over_own_default() -> void:
	var npc = load(NPC_PATH).new()
	var bms = load(BMS_PATH).new()
	npc.add_child(bms)  # off-tree: establishes get_parent() WITHOUT entering the SceneTree, so no _ready/_rebuild
	# No look on the NPC: BodyModelSwap falls back to its OWN fields (where the shared default look now lives).
	bms.arm_color = Color(1, 0, 0)
	bms.body_color = Color(1, 0, 0)
	assert_eq(bms._eff_arm_color(), Color(1, 0, 0), "no look -> arm tint reads BodyModelSwap's own arm_color")
	assert_eq(bms._eff_body()["col"], Color(1, 0, 0), "no look -> body skin reads BodyModelSwap's own body_color")
	# A look on the NPC wins over the BodyModelSwap default.
	var lk := NpcLook.new()
	lk.arm_color = Color(0, 1, 0)
	lk.body_color = Color(0, 1, 0)
	npc.look = lk
	assert_eq(bms._eff_arm_color(), Color(0, 1, 0), "look assigned -> arm tint reads the look's arm_color")
	assert_eq(bms._eff_body()["col"], Color(0, 1, 0), "look assigned -> body skin reads the look's body_color")
	npc.free()

func test_body_model_swap_reads_host_sitting_toggle() -> void:
	var npc = load(NPC_PATH).new()
	var bms = load(BMS_PATH).new()
	npc.add_child(bms)
	assert_false(bms._host_sitting(), "default NPC.sitting false leaves the body swap standing")
	npc.sitting = true
	assert_true(bms._host_sitting(), "BodyModelSwap reads the host's is_sitting() hook for its seated pose")
	npc.free()

func test_seated_leg_pitch_swings_feet_forward() -> void:
	# The seated swing pre-multiplies about swap-space X on a down-hanging leg, and the rig's front is +Z
	# (npc.gd: "this model's front is +Z"), so the default pitch must send the feet toward +Z — out in front of
	# the seat. A positive pitch folds the legs backward through the seat (the "legs face the wrong way" bug).
	# leg_rotation mirrors the shipped enemy.tscn authoring (pure yaw — it can't change which way "down" hangs).
	var bms = load(BMS_PATH).new()
	bms.leg_rotation = Vector3(0, -90, 0)
	var foot: Vector3 = (bms._leg_pose(bms.seated_leg_pitch).basis * Vector3.DOWN).normalized()
	assert_gt(foot.z, 0.9, "seated legs must point their feet FORWARD (+Z), roughly flush with the seat, got %s" % foot)
	bms.free()

func test_head_rest_position_tracks_posture() -> void:
	# The head-look mount's neck-pivot hinge rebases on this seam every frame; it must report the SAME posture
	# offset _apply_head_transform places the head with, standing and seated, or the hinge re-pins the head at
	# the wrong height (the floating-seated-head / standing-head-in-torso bug).
	var npc = load(NPC_PATH).new()
	var bms = load(BMS_PATH).new()
	npc.add_child(bms)
	bms.head_position = Vector3(0.0, 0.615, 0.04)
	var standing: Vector3 = bms.head_rest_position()
	assert_eq(standing, Vector3(0.0, 0.615, 0.04), "standing: the rest is the authored head placement")
	npc.sitting = true
	var seated: Vector3 = bms.head_rest_position()
	assert_eq(seated, Vector3(0.0, 0.615, 0.04) + bms._posture_offset(),
		"seated: the rest rides the live posture offset (seated drop / ground snap)")
	assert_lt(seated.y, standing.y, "sitting drops the head rest with the body")
	npc.free()

func test_seated_pose_hides_the_blob_shadow() -> void:
	# Sitting lifts the body onto a chair, so the blob-shadow Decal under it reads as a detached puddle: the
	# posture transition hides a host child named "Shadow" (the Player.tscn / enemy.tscn idiom) and standing
	# restores it. Off-tree: _sync_shadow resolves the sibling via get_node_or_null, no SceneTree needed.
	var npc = load(NPC_PATH).new()
	var bms = load(BMS_PATH).new()
	npc.add_child(bms)
	var shadow := Node3D.new()
	shadow.name = "Shadow"
	npc.add_child(shadow)
	npc.sitting = true
	bms._sync_posture_transforms(true)
	assert_false(shadow.visible, "sitting down hides the host's blob-shadow decal")
	npc.sitting = false
	bms._sync_posture_transforms(false)
	assert_true(shadow.visible, "standing back up restores the blob shadow")
	npc.free()

func test_seated_body_pitch_is_a_forward_lean_not_a_roll() -> void:
	# The seated torso lean must stay sagittal whatever yaw the body model is authored with ((0, -90, 0) on the
	# shipped torso). Euler-ADDING the pitch to rotation_degrees rotated about the model's pre-yaw X axis, which
	# on that yawed torso read as a sideways roll instead of a lean.
	var bms = load(BMS_PATH).new()
	var up: Vector3 = bms._body_posture_basis(Vector3(0, -90, 0), true) * Vector3.UP
	assert_gt(up.z, 0.05, "seated torso should tip its top toward +Z (a forward lean), got %s" % up)
	assert_almost_eq(up.x, 0.0, 0.001, "the seated lean must not roll the torso sideways, got %s" % up)
	var standing_up: Vector3 = bms._body_posture_basis(Vector3(0, -90, 0), false) * Vector3.UP
	assert_almost_eq(standing_up.y, 1.0, 0.0001, "standing keeps the authored upright rotation")
	bms.free()

func test_body_model_swap_model_fields_accept_scene_or_mesh() -> void:
	var bms = load(BMS_PATH).new()
	for field in ["body_model", "head_model", "arm_model", "leg_model"]:
		var prop := _property(bms, field)
		assert_eq(prop.get("hint", -1), PROPERTY_HINT_RESOURCE_TYPE,
			"BodyModelSwap.%s uses a resource-type hint" % field)
		assert_eq(prop.get("hint_string", ""), "PackedScene,Mesh",
			"BodyModelSwap.%s accepts both scene models and .obj mesh imports" % field)
	bms.free()

func test_body_model_swap_instances_mesh_models_from_look() -> void:
	var host := _LookHost.new()
	var bms = load(BMS_PATH).new()
	var lk := NpcLook.new()
	var body_mesh := BoxMesh.new()
	var head_mesh := SphereMesh.new()
	lk.body_model = body_mesh
	lk.head_model = head_mesh
	host.look = lk
	host.add_child(bms)
	add_child_autofree(host)
	var parts: Array = bms.character_parts()
	var torso := _part_node(parts, "torso") as MeshInstance3D
	var head := _part_node(parts, "head") as MeshInstance3D
	assert_not_null(torso, "NpcLook body_model can be a Mesh resource, like an imported .obj")
	assert_not_null(head, "NpcLook head_model can be a Mesh resource, like an imported .obj")
	if torso != null:
		assert_eq(torso.mesh, body_mesh, "the torso MeshInstance3D uses the look's body mesh resource")
	if head != null:
		assert_eq(head.mesh, head_mesh, "the head MeshInstance3D uses the look's head mesh resource")

func test_lower_arms_drops_to_rest_and_clears_raised_state() -> void:
	# Entering dialogue calls BodyModelSwap.lower_arms() (via NPC.set_in_dialogue) so an NPC you talk to always
	# puts its arms DOWN — the world pauses for the chat, which halts the gait, so a raised gun-hold / fists-out /
	# airborne pose would otherwise freeze up for the whole conversation. lower_arms clears every raised-arm state
	# and snaps the arms to their by-side rest pose. Built in-tree with a mesh arm_model so the arms actually
	# instance and the rest transform is observable. The rest pose is whatever the build itself laid the arms at,
	# captured BEFORE the arms are raised — so the final check can only pass if lower_arms writes the arms back.
	var host := _LookHost.new()
	var bms = load(BMS_PATH).new()
	bms.arm_model = BoxMesh.new()
	bms.arm_rotation = Vector3(10.0, 0.0, 0.0)  # a non-trivial authored rest pose to compare against
	host.add_child(bms)
	add_child_autofree(host)
	var arm_l := _part_node(bms.character_parts(), "arm_l") as Node3D
	var arm_r := _part_node(bms.character_parts(), "arm_r") as Node3D
	assert_true(arm_l != null and arm_r != null, "the mesh arm_model instanced both arms")
	if arm_l == null or arm_r == null:
		return
	var rest_l: Transform3D = arm_l.transform
	var rest_r: Transform3D = arm_r.transform
	# The gait had raised the arms: the state it keeps (gun-hold pitch + walk swing + fists sway + a mid strike
	# flail + a closed two-handed grip) AND the pose it last wrote — the arms held forward at the gun-hold pitch,
	# through the rig's own pose builder. The world is paused in dialogue, so no gait frame will ever undo it.
	bms._mode_pitch = bms.arm_hold_pitch
	bms._swing_blend = 1.0
	bms._fists_sway = 8.0
	bms._strike_t = 1.0
	bms._hold_blend = 1.0
	var raised: Transform3D = bms._arm_pose(bms.arm_rotation + Vector3(bms.arm_hold_pitch, 0.0, 0.0))
	arm_l.transform = raised
	arm_r.transform = raised
	assert_false(arm_l.transform.is_equal_approx(rest_l), "precondition: the left arm is really raised off its rest pose")
	bms.lower_arms()
	assert_eq(bms._mode_pitch, 0.0, "lower_arms clears the weapon-hold pitch so the arms aren't held forward")
	assert_eq(bms._swing_blend, 0.0, "lower_arms clears the walk-swing blend")
	assert_eq(bms._fists_sway, 0.0, "lower_arms clears the fists-out sway")
	assert_eq(bms._strike_t, 0.0, "lower_arms clears any in-flight strike flail")
	assert_eq(bms._hold_blend, 0.0, "lower_arms opens the two-handed grip, so the hands don't stay closed on a lowered gun")
	assert_true(arm_l.transform.is_equal_approx(rest_l),
		"lower_arms snaps the raised left arm back to the rest pose the rig was built with")
	assert_true(arm_r.transform.is_equal_approx(rest_r),
		"...and the raised right arm too — the whole conversation plays out with both arms down")

func test_body_model_swap_instances_mesh_models_for_limbs() -> void:
	var host := _LookHost.new()
	var bms = load(BMS_PATH).new()
	var arm_mesh := BoxMesh.new()
	var leg_mesh := CapsuleMesh.new()
	bms.arm_model = arm_mesh
	bms.leg_model = leg_mesh
	host.add_child(bms)
	add_child_autofree(host)
	var parts: Array = bms.character_parts()
	var arm_l := _part_node(parts, "arm_l") as MeshInstance3D
	var arm_r := _part_node(parts, "arm_r") as MeshInstance3D
	var leg_l := _part_node(parts, "leg_l") as MeshInstance3D
	var leg_r := _part_node(parts, "leg_r") as MeshInstance3D
	assert_not_null(arm_l, "BodyModelSwap arm_model can be a Mesh resource")
	assert_not_null(arm_r, "a Mesh arm_model still mirrors into a right arm")
	assert_not_null(leg_l, "BodyModelSwap leg_model can be a Mesh resource")
	assert_not_null(leg_r, "a Mesh leg_model still mirrors into a right leg")
	if arm_l != null:
		assert_eq(arm_l.mesh, arm_mesh, "left arm uses the assigned arm mesh")
	if arm_r != null:
		assert_eq(arm_r.mesh, arm_mesh, "right arm uses the assigned arm mesh")
	if leg_l != null:
		assert_eq(leg_l.mesh, leg_mesh, "left leg uses the assigned leg mesh")
	if leg_r != null:
		assert_eq(leg_r.mesh, leg_mesh, "right leg uses the assigned leg mesh")
