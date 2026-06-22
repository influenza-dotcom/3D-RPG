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
	assert_eq(NpcInspector.conflicts(both).size(), 1, "both faction_id + faction set is a conflict")
	var one := NpcData.new()
	one.faction_id = "raiders"
	assert_eq(NpcInspector.conflicts(one).size(), 0, "only faction_id set -> no conflict")
