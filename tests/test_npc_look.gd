extends GutTest

## NpcLook (scripts/npc/npc_look.gd): the reusable per-NPC appearance resource. After the fold, an NPC's
## appearance is overridden SOLELY via its `look` resource -- the inline body/head/arm/leg fields were removed
## from npc.gd, and the shared default look lives on the BodyModelSwap child. Verifies the look's defaults, that
## the NPC no longer carries the inline fields, and that BodyModelSwap resolves a look over its own default.
## Built off-tree (no SceneTree entry) so no NPC _ready runs (CLAUDE.md).

const NPC_PATH := "res://scripts/npc/npc.gd"
const BMS_PATH := "res://scripts/components/body_model_swap.gd"

## First entry in get_property_list() whose name matches, else {}.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

func test_npc_look_defaults() -> void:
	var lk := NpcLook.new()
	assert_null(lk.body_model, "NpcLook.body_model defaults null (no body override)")
	assert_null(lk.head_model, "NpcLook.head_model defaults null (no head override)")
	assert_eq(lk.body_model_scale, 1.0, "NpcLook.body_model_scale defaults 1.0")
	assert_eq(lk.body_color, Color.WHITE, "NpcLook.body_color defaults WHITE (no tint)")
	assert_eq(lk.arm_color, Color.WHITE, "NpcLook.arm_color defaults WHITE")
	assert_eq(lk.leg_color, Color.WHITE, "NpcLook.leg_color defaults WHITE")
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
