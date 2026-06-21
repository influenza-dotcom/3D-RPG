extends GutTest

## Authoring config-warnings: the inspector flags "multiple sources of truth" conflicts (the dual-source friction
## the user hit). Pure off-tree — each host is built via .new(), fields set, and _get_configuration_warnings()
## asserted. (game_root / body_model_swap warnings need tree/child context, so they're playtest-verified.)

const NPC_PATH := "res://scripts/npc/npc.gd"

func _has(w, sub) -> bool:
	for s in w:
		if sub in s:
			return true
	return false


func test_npc_no_warnings_at_defaults() -> void:
	var n = load(NPC_PATH).new()
	assert_eq(n._get_configuration_warnings().size(), 0, "a fresh NPC has no dual-source warnings (no false positives)")
	n.free()


func test_npc_faction_id_vs_faction_slot() -> void:
	var n = load(NPC_PATH).new()
	n.faction_id = "townsfolk"
	n.faction = Faction.new()
	assert_true(_has(n._get_configuration_warnings(), "faction_id"), "faction_id + a faction resource both set -> warn (faction_id wins)")
	n.free()


func test_npc_disposition_inert_under_faction() -> void:
	var n = load(NPC_PATH).new()
	n.faction = Faction.new()
	n.disposition = Disposition.Kind.FRIENDLY  # non-default, but a faction is set + override off -> ignored
	assert_true(_has(n._get_configuration_warnings(), "disposition"), "a set faction makes a non-default disposition inert -> warn")
	n.disposition_overrides_faction = true
	assert_false(_has(n._get_configuration_warnings(), "disposition"), "...ticking disposition_overrides_faction clears it")
	n.free()


func test_npc_profile_clobber_warns() -> void:
	var n = load(NPC_PATH).new()
	n.profile = NpcData.new()
	assert_true(_has(n._get_configuration_warnings(), "OVERWRITES"), "a profile with fills_blanks OFF warns it clobbers inline fields")
	n.profile_fills_blanks_only = true
	assert_false(_has(n._get_configuration_warnings(), "OVERWRITES"), "...fills_blanks ON clears the clobber warning")
	n.free()


func test_npc_inline_loot_vs_profile() -> void:
	var n = load(NPC_PATH).new()
	n.profile = NpcData.new()
	n.profile_fills_blanks_only = true  # isolate the loot warning from the clobber one
	n.loot = LootTable.new()
	assert_true(_has(n._get_configuration_warnings(), "loot"), "inline loot + a profile -> warn (profile's loot wins)")
	n.free()
