extends GutTest

## Unit tests for the CYBER SUNDAY "Content" dock's PURE scaffolders (content_scaffold.gd). Only the statics are
## exercised — they build Resources via .new() with no EditorInterface / ResourceSaver / scene-tree, so they run
## headless. The dock itself (content_dock.gd) is editor glue (EditorInterface / EditorInspector) and is NOT
## instantiated here — those classes are unavailable in a headless run and would crash the suite.

const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")


# --- Quest -----------------------------------------------------------------------------------------------------

func test_build_quest_seeds_id_and_default_single_objective() -> void:
	var q := Scaffold.build_quest(&"rescue_kyle", 1)
	assert_eq(q.id, StringName("rescue_kyle"), "the quest id should equal the supplied id")
	assert_eq(q.objectives.size(), 1, "objective_count 1 should seed exactly one objective")
	assert_eq(q.objectives[0].type, QuestObjective.Type.FLAG, "the default seeded objective should be a FLAG objective")
	assert_true(q.reward_money > 0.0, "a starter quest should carry a non-zero money reward")
	q = null

func test_build_quest_respects_objective_count() -> void:
	var q := Scaffold.build_quest(&"three_steps", 3)
	assert_eq(q.objectives.size(), 3, "objective_count 3 should seed three objectives")
	q = null

func test_build_quest_clamps_objective_count_to_at_least_one() -> void:
	var q := Scaffold.build_quest(&"zero_req", 0)
	assert_gte(q.objectives.size(), 1, "objective_count 0 should clamp up to at least one objective")
	q = null

func test_build_quest_objective_ids_are_unique() -> void:
	var q := Scaffold.build_quest(&"many", 4)
	var seen := {}
	for o in q.objectives:
		assert_false(seen.has(o.id), "objective ids must be unique within the quest (dup: %s)" % o.id)
		seen[o.id] = true
	assert_eq(seen.size(), 4, "four objectives should yield four distinct ids")
	q = null


# --- NPC archetype ---------------------------------------------------------------------------------------------

func test_build_npc_sets_faction_id_and_weapon() -> void:
	var w := WeaponData.new()
	var d := Scaffold.build_npc("raider", w)
	assert_eq(d.faction_id, "raiders", "the raider preset should pick the raiders faction id")
	assert_eq(d.weapon_data, w, "the NPC archetype should be equipped with the supplied weapon")
	d = null
	w = null

func test_build_npc_never_sets_both_faction_id_and_faction() -> void:
	# NpcData's EITHER/OR rule: a profile is driven by faction_id XOR the faction resource slot, never both.
	for preset in ["raider", "townsperson", "sniper", "shopkeeper"]:
		var d := Scaffold.build_npc(preset, null)
		assert_ne(d.faction_id, "", "preset '%s' should set a faction_id" % preset)
		assert_null(d.faction, "preset '%s' must leave the faction resource slot null (either/or rule)" % preset)
		d = null

func test_build_npc_presets_differ_in_perception() -> void:
	# The sniper is eagle-eyed: a longer sight range than the raider, proving per-preset tuning landed.
	var sniper := Scaffold.build_npc("sniper", null)
	var raider := Scaffold.build_npc("raider", null)
	assert_gt(sniper.sight_range, raider.sight_range, "the sniper should see further than the raider")
	sniper = null
	raider = null

func test_build_npc_threat_response_in_range() -> void:
	var d := Scaffold.build_npc("townsperson", null)
	assert_gte(d.threat_response, 0, "threat_response maps onto NPC.ThreatResponse (0=Fight,1=Flee)")
	assert_lte(d.threat_response, 1, "threat_response should be 0 or 1")
	d = null


# --- Weapon + Item pair ----------------------------------------------------------------------------------------

func test_build_weapon_and_item_cross_link_resolves() -> void:
	var pair := Scaffold.build_weapon_and_item("Plasma Rifle")
	var weapon: WeaponData = pair["weapon"]
	var item: Item = pair["item"]
	assert_not_null(weapon, "the pair should include a WeaponData")
	assert_not_null(item, "the pair should include an Item")
	assert_eq(item.category, Item.Category.WEAPON, "the item should be WEAPON category")
	assert_eq(item.weapon, weapon, "the item's weapon must point at the returned WeaponData (cross-link)")
	assert_true(item.is_weapon(), "is_weapon() should be true for the scaffolded weapon item")
	weapon = null
	item = null

func test_build_weapon_and_item_calibers_match() -> void:
	var pair := Scaffold.build_weapon_and_item("Ion Blaster")
	var weapon: WeaponData = pair["weapon"]
	var item: Item = pair["item"]
	assert_eq(item.caliber, weapon.caliber, "item caliber must mirror the weapon caliber so ammo lines up")
	assert_ne(weapon.caliber, StringName(""), "the scaffolded weapon should have a non-empty caliber")
	weapon = null
	item = null


# --- Faction ---------------------------------------------------------------------------------------------------

func test_build_faction_id_equals_arg() -> void:
	var f := Scaffold.build_faction(&"merchants_guild")
	assert_eq(f.id, StringName("merchants_guild"), "the faction id must equal the supplied id (id == filename rule)")
	assert_false(f.display_name.is_empty(), "the faction should get a seeded display name")
	f = null


# --- Dialogue --------------------------------------------------------------------------------------------------

func test_build_dialogue_seeds_greeting_and_goodbye() -> void:
	var dr := Scaffold.build_dialogue(&"old_man")
	assert_gte(dr.lines.size(), 2, "a seeded conversation should have at least a greeting + goodbye")
	assert_lte(dr.lines.size(), 3, "the starter conversation should stay small (2-3 lines)")
	for line in dr.lines:
		assert_false(line.has_choices(), "seeded lines should be linear (no branch choices) for a clean starting point")
		assert_false(line.text.is_empty(), "each seeded dialogue line should carry placeholder text")
	dr = null
