extends GutTest

## NpcLook (scripts/npc/npc_look.gd): the reusable per-NPC appearance resource. After the fold, an NPC's
## appearance is overridden SOLELY via its `look` resource -- the inline body/head/arm/leg fields were removed
## from npc.gd, and the shared default look lives on the BodyModelSwap child. Verifies the look's defaults, that
## the NPC no longer carries the inline fields, and that BodyModelSwap resolves a look over its own default.
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

func test_npc_look_defaults() -> void:
	var lk := NpcLook.new()
	assert_null(lk.body_model, "NpcLook.body_model defaults null (no body override)")
	assert_null(lk.head_model, "NpcLook.head_model defaults null (no head override)")
	assert_eq(lk.body_model_scale, 1.0, "NpcLook.body_model_scale defaults 1.0")
	assert_eq(lk.body_color, Color.WHITE, "NpcLook.body_color defaults WHITE (no tint)")
	assert_eq(lk.arm_color, Color.WHITE, "NpcLook.arm_color defaults WHITE")
	assert_eq(lk.leg_color, Color.WHITE, "NpcLook.leg_color defaults WHITE")
	lk = null

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
	# instance and the rest transform is observable.
	var host := _LookHost.new()
	var bms = load(BMS_PATH).new()
	bms.arm_model = BoxMesh.new()
	bms.arm_rotation = Vector3(10.0, 0.0, 0.0)  # a non-trivial authored rest pose to compare against
	host.add_child(bms)
	add_child_autofree(host)
	# Pretend the gait had raised the arms (gun-hold pitch + walk swing + fists sway + a mid strike flail).
	bms._mode_pitch = bms.arm_hold_pitch
	bms._swing_blend = 1.0
	bms._fists_sway = 8.0
	bms._strike_t = 1.0
	bms.lower_arms()
	assert_eq(bms._mode_pitch, 0.0, "lower_arms clears the weapon-hold pitch so the arms aren't held forward")
	assert_eq(bms._swing_blend, 0.0, "lower_arms clears the walk-swing blend")
	assert_eq(bms._fists_sway, 0.0, "lower_arms clears the fists-out sway")
	assert_eq(bms._strike_t, 0.0, "lower_arms clears any in-flight strike flail")
	var arm_l := _part_node(bms.character_parts(), "arm_l") as Node3D
	assert_not_null(arm_l, "the mesh arm_model instanced a left arm")
	if arm_l != null:
		assert_true(arm_l.transform.is_equal_approx(bms._arm_pose(bms.arm_rotation)),
			"lower_arms snaps the left arm to its authored by-side rest pose")

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
