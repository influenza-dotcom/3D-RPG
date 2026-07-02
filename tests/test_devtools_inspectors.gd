extends GutTest

## The two inspector add-ons (step 7): the pure logic (LootTable Monte-Carlo tally, NpcData conflict detection)
## is correct. The preloads also compile-check the whole scripts. (EditorInspectorPlugin can't be instantiated in
## a headless run, so _can_handle / the injected cards are editor-only and user-verified, not unit-tested here.)

const LootInspector := preload("res://addons/cybersunday_tools/inspectors/loottable_inspector.gd")
const NpcInspector := preload("res://addons/cybersunday_tools/inspectors/npcdata_inspector.gd")


func test_loot_tally_counts_a_guaranteed_drop() -> void:
	var it := Item.new()
	var e := LootEntry.new()
	e.item = it
	e.chance = 1.0
	e.min_count = 2
	e.max_count = 2
	var lt := LootTable.new()
	var rows: Array[LootEntry] = [e]
	lt.entries = rows
	var t := LootInspector.tally(lt, 500, 7)
	assert_true(t.has(it), "the guaranteed item appears in the tally")
	assert_eq(int(t[it]["hits"]), 500, "chance 1.0 drops on every roll")
	assert_eq(int(t[it]["total"]), 1000, "2 per drop × 500 rolls")


func test_loot_tally_skips_a_zero_chance_entry() -> void:
	var it := Item.new()
	var e := LootEntry.new()
	e.item = it
	e.chance = 0.0
	var lt := LootTable.new()
	var rows: Array[LootEntry] = [e]
	lt.entries = rows
	assert_true(LootInspector.tally(lt, 200, 3).is_empty(), "chance 0 never drops -> empty tally")


func test_npcdata_flags_double_faction_and_passes_single() -> void:
	var both := NpcData.new()
	both.faction_id = "raiders"
	both.faction = Faction.new()
	assert_eq(NpcInspector.conflicts(both).size(), 1, "both faction_id + faction set is a conflict (disposition stays default HOSTILE, override off -> only the one warning)")
	var one := NpcData.new()
	one.faction_id = "raiders"
	assert_eq(NpcInspector.conflicts(one).size(), 0, "only faction_id set -> no conflict")


func test_npcdata_flags_inert_disposition_under_faction_cleared_by_tick() -> void:
	# M8: a faction is set + the standalone disposition was changed off HOSTILE + the override is OFF -> the disposition
	# is inert (mirror of npc.gd's node-side warning). Ticking disposition_overrides_faction clears it.
	var nd := NpcData.new()
	nd.faction_id = "raiders"
	nd.disposition = Disposition.Kind.FRIENDLY  # a deliberate non-default that a faction would ignore
	assert_gt(NpcInspector.conflicts(nd).size(), 0, "a non-default disposition under a faction (override off) is flagged as inert")
	nd.disposition_overrides_faction = true
	assert_eq(NpcInspector.conflicts(nd).size(), 0, "ticking disposition_overrides_faction clears the inert-disposition warning")


func test_npcdata_flags_pointless_override_without_faction() -> void:
	# M8: the override is ticked but there's no faction to override -> the disposition is used regardless (the flag is pointless).
	var nd := NpcData.new()
	nd.disposition_overrides_faction = true  # no faction_id, no faction
	var msgs := NpcInspector.conflicts(nd)
	assert_eq(msgs.size(), 1, "a ticked override with no faction is exactly one (pointless) warning")
	assert_true(String(msgs[0]).contains("nothing to override"), "the warning names the pointless override")
