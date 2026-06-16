extends GutTest

## NpcLook (scripts/npc/npc_look.gd): a reusable per-NPC appearance .tres. Verifies it mirrors the NPC's inline
## defaults, that assigning one HIDES the NPC's inline appearance fields in the inspector (the look owns them),
## and that BodyModelSwap resolves the look's fields over the inline ones (look-first) while staying identical
## when no look is assigned. Built off-tree (no add_child to a SceneTree) so no NPC _ready runs (CLAUDE.md).

const NPC_PATH := "res://scripts/npc/npc.gd"
const BMS_PATH := "res://scripts/components/body_model_swap.gd"

const LOOK_FIELDS := ["body_model", "body_model_scale", "body_model_position", "body_model_rotation",
	"body_texture", "body_color", "head_model", "head_model_scale", "head_model_position",
	"head_model_rotation", "head_texture", "head_color", "arm_color", "leg_color"]

## First entry in get_property_list() whose name matches, else {}.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

func test_npc_look_defaults_mirror_inline_fields() -> void:
	var lk := NpcLook.new()
	assert_null(lk.body_model, "NpcLook.body_model defaults null (no body override)")
	assert_null(lk.head_model, "NpcLook.head_model defaults null (no head override)")
	assert_eq(lk.body_model_scale, 1.0, "NpcLook.body_model_scale mirrors the inline default 1.0")
	assert_eq(lk.body_color, Color.WHITE, "NpcLook.body_color mirrors the inline default WHITE (no tint)")
	assert_eq(lk.arm_color, Color.WHITE, "NpcLook.arm_color defaults WHITE")
	assert_eq(lk.leg_color, Color.WHITE, "NpcLook.leg_color defaults WHITE")
	lk = null

func test_assigning_a_look_hides_the_inline_fields() -> void:
	var npc = load(NPC_PATH).new()
	# No look assigned -> the inline appearance fields are editable in the inspector.
	assert_true(int(_property(npc, "body_model").get("usage", 0)) & PROPERTY_USAGE_EDITOR != 0,
		"with no look, body_model must be shown in the inspector")
	# Assign a look -> every inline appearance field is hidden (still stored, just not shown).
	npc.look = NpcLook.new()
	for f in LOOK_FIELDS:
		var p := _property(npc, f)
		assert_false(p.is_empty(), "NPC must still expose '%s' (stored, just hidden)" % f)
		assert_eq(int(p.get("usage", 0)) & PROPERTY_USAGE_EDITOR, 0,
			"with a look assigned, inline field '%s' must be hidden from the inspector" % f)
	# faction_id stays a disk-backed dropdown regardless of the look.
	assert_eq(int(_property(npc, "faction_id").get("hint", -1)), PROPERTY_HINT_ENUM_SUGGESTION,
		"faction_id stays a dropdown when a look is assigned")
	npc.free()

func test_body_model_swap_resolves_look_over_inline() -> void:
	var npc = load(NPC_PATH).new()
	var bms = load(BMS_PATH).new()
	npc.add_child(bms)  # off-tree: establishes get_parent() WITHOUT entering the SceneTree, so no _ready/_rebuild
	# No look: BodyModelSwap reads the NPC's inline fields (unchanged legacy behaviour).
	npc.arm_color = Color(1, 0, 0)
	npc.body_color = Color(1, 0, 0)
	assert_eq(bms._eff_arm_color(), Color(1, 0, 0), "no look -> arm tint reads the NPC's inline arm_color")
	assert_eq(bms._eff_body()["col"], Color(1, 0, 0), "no look -> body skin reads the NPC's inline body_color")
	# With a look: the look's fields win over the inline ones.
	var lk := NpcLook.new()
	lk.arm_color = Color(0, 1, 0)
	lk.body_color = Color(0, 1, 0)
	npc.look = lk
	assert_eq(bms._eff_arm_color(), Color(0, 1, 0), "look assigned -> arm tint reads the look's arm_color")
	assert_eq(bms._eff_body()["col"], Color(0, 1, 0), "look assigned -> body skin reads the look's body_color")
	npc.free()
