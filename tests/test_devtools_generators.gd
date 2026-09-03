extends GutTest

## Unit tests for the CYBER SUNDAY "New" tab's PURE scaffolders (content_scaffold.gd). Only the statics are
## exercised -- they build Resources via .new() with no EditorInterface / ResourceSaver / scene-tree, so they run
## headless. The tab itself (content_dock.gd) is editor GLUE: its _init builds widgets only and every EditorInterface
## call lives in a button handler, so constructing it is harmless -- but PRESSING a generator writes a real file into
## res://, so nothing here presses one. What IS pinned instead is every value those handlers depend on, including the
## two shared name rules (slugify / titleize) that the tab's refusals are worded around.

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


# --- Item (non-weapon) -----------------------------------------------------------------------------------------

func test_build_item_consumable_is_usable_and_not_a_weapon() -> void:
	var it := Scaffold.build_item("Med Kit", true)
	assert_eq(it.category, Item.Category.CONSUMABLE, "consumable=true should seed a CONSUMABLE item")
	assert_true(it.is_consumable(), "a consumable item should report is_consumable()")
	assert_false(it.is_weapon(), "a non-weapon item must never be WEAPON category / carry a WeaponData")
	assert_null(it.weapon, "a non-weapon item must leave the weapon slot null")
	assert_gt(it.heal_amount, 0.0, "a seeded consumable should heal something so it's immediately useful")
	it = null

func test_build_item_junk_is_misc() -> void:
	var it := Scaffold.build_item("Scrap Metal", false)
	assert_eq(it.category, Item.Category.MISC, "consumable=false should seed a MISC (junk) item")
	assert_false(it.is_consumable(), "junk should not be consumable")
	assert_false(it.is_weapon(), "junk should not be a weapon")
	it = null

func test_build_item_id_equals_slugified_filename() -> void:
	# The dock saves to <id>.tres, so id == the slug of the name keeps the lookup key == the filename base.
	var it := Scaffold.build_item("Plasma Rifle!", true)
	assert_eq(it.id, StringName("plasma_rifle"), "item id should equal the slugified name (filename base rule)")
	assert_false(it.display_name.is_empty(), "the item should get a seeded display name")
	it = null


# --- LootTable -------------------------------------------------------------------------------------------------

func test_build_loot_table_is_empty_but_rollable() -> void:
	var lt := Scaffold.build_loot_table()
	assert_eq(lt.entries.size(), 0, "a starter loot table should begin with no entries for the designer to fill")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var dropped: Array = lt.roll(rng)
	assert_eq(dropped.size(), 0, "rolling an empty loot table should yield nothing and never error")
	lt = null
	rng = null


# --- Perk ------------------------------------------------------------------------------------------------------

func test_build_perk_id_equals_arg_and_collections_empty() -> void:
	var p := Scaffold.build_perk(&"steady_hands")
	assert_eq(p.id, StringName("steady_hands"), "the perk id must equal the supplied id (id == filename rule)")
	assert_false(p.display_name.is_empty(), "the perk should get a seeded display name")
	assert_eq(p.stat_bonuses.size(), 0, "a starter perk should begin with no stat bonuses")
	assert_eq(p.combat_bonuses.size(), 0, "a starter perk should begin with no combat bonuses")
	assert_eq(p.requires_perks.size(), 0, "a starter perk should have no prerequisites")
	p = null

func test_build_perk_empty_bonuses_pass_validate() -> void:
	# An empty stat_bonuses has no unknown keys, so the seeded perk is immediately unlockable (validate() true).
	var p := Scaffold.build_perk(&"clean_slate")
	assert_true(p.validate(), "a perk with empty stat_bonuses should pass validate() (no unknown stat keys)")
	p = null


# --- StatusEffect ----------------------------------------------------------------------------------------------

func test_build_status_effect_id_equals_arg() -> void:
	var se := Scaffold.build_status_effect(&"poison")
	assert_eq(se.id, StringName("poison"), "the status effect id must equal the supplied id (id == filename rule)")
	assert_false(se.display_name.is_empty(), "the status effect should get a seeded display name")
	se = null

func test_build_status_effect_is_inert_by_default() -> void:
	# Seeded neutral: no periodic damage and a 1.0 speed multiplier, so attaching it does nothing surprising.
	var se := Scaffold.build_status_effect(&"marked")
	assert_eq(se.damage_per_tick, 0.0, "a seeded status effect should deal no damage until the designer sets it")
	assert_eq(se.speed_multiplier, 1.0, "a seeded status effect should not alter move speed by default")
	assert_gt(se.duration, 0.0, "a seeded status effect should have a positive (timed) duration")
	assert_eq(se.stat_modifiers.size(), 0, "a starter status effect should begin with no stat modifiers")
	se = null


# --- SpawnDefinition (encounter) -------------------------------------------------------------------------------

func test_build_spawn_definition_carries_scene_and_seeds() -> void:
	var scene := PackedScene.new()
	var sd := Scaffold.build_spawn_definition(scene)
	assert_eq(sd.npc_scene, scene, "the definition should carry the supplied npc_scene (the dock loads + passes it)")
	assert_gte(sd.count, 1, "a starter encounter should spawn at least one NPC")
	assert_true(sd.auto_aggro, "a starter encounter should auto-aggro by default")
	assert_null(sd.profile, "the profile override stays null for the designer to stamp an archetype")
	sd = null
	scene = null

func test_build_spawn_definition_tolerates_null_scene() -> void:
	# A null scene is tolerated (the definition is just inert until assigned) — the builder must not crash.
	var sd := Scaffold.build_spawn_definition(null)
	assert_null(sd.npc_scene, "a null npc_scene is allowed (inert until the designer assigns one)")
	sd = null


# --- Schedule --------------------------------------------------------------------------------------------------

func test_build_schedule_has_day_and_night_destinations() -> void:
	var s := Scaffold.build_schedule()
	assert_eq(s.entries.size(), 2, "a starter schedule should demonstrate a day + night entry")
	assert_eq(s.destination_for(1), StringName("market"), "by day (phase 1) the NPC heads to the market group")
	assert_eq(s.destination_for(0), StringName("home"), "by night (phase 0) the NPC heads to the home group")
	s = null


# --- Cutscene --------------------------------------------------------------------------------------------------

func test_build_cutscene_seeds_distinct_action_types() -> void:
	var c := Scaffold.build_cutscene()
	assert_gte(c.actions.size(), 2, "a starter cutscene should seed at least two actions")
	var types := {}
	for a in c.actions:
		types[a.type] = true
	assert_gte(types.size(), 2, "the starter actions should show more than one action TYPE so the pattern is clear")
	c = null


# --- BarkSet ---------------------------------------------------------------------------------------------------

func test_build_bark_set_seeds_some_and_inherits_rest() -> void:
	var b := Scaffold.build_bark_set()
	assert_gt(b.spot.size(), 0, "the spot category should seed a placeholder line")
	assert_gt(b.hurt.size(), 0, "the hurt category should seed a placeholder line")
	assert_eq(b.greet.size(), 0, "unfilled categories stay empty so the NPC inherits its built-in default lines")
	b = null


# --- Loadout ---------------------------------------------------------------------------------------------------

func test_build_loadout_is_empty_but_valid() -> void:
	var l := Scaffold.build_loadout()
	assert_eq(l.weapons.size(), 0, "a starter loadout begins with no weapons (falls back to the SwapWeapons defaults)")
	assert_gt(l.starting_clips_per_caliber, 0, "a starter loadout should grant some spare clips")
	assert_gte(l.money, 0.0, "a starter loadout should seed non-negative starting money")
	l = null


# --- GrappleHookResource ---------------------------------------------------------------------------------------

func test_build_grapple_resource_has_sane_defaults() -> void:
	var g := Scaffold.build_grapple_resource()
	assert_not_null(g, "the grapple resource should build")
	assert_gt(g.max_range, 0.0, "a grapple resource should have a positive reach")
	assert_gt(g.hook_speed, 0.0, "a grapple resource should have a positive hook speed")
	g = null


# --- MapData ---------------------------------------------------------------------------------------------------

func test_build_map_data_has_nonzero_bounds() -> void:
	var m := Scaffold.build_map_data()
	assert_gt(m.world_bounds.size.x, 0.0, "map bounds must have a positive width so projection never divides by zero")
	assert_gt(m.world_bounds.size.y, 0.0, "map bounds must have a positive height")
	m = null


# --- ThrowableData ---------------------------------------------------------------------------------------------

func test_build_throwable_names_itself_and_keeps_the_resource_defaults() -> void:
	var t := Scaffold.build_throwable("oil drum")
	assert_eq(t.display_name, "Oil Drum", "the throwable is named from the typed name (titleized)")
	assert_gt(t.max_hp, 0, "a starter throwable keeps the resource's own breakable hit points")
	assert_null(t.mesh, "the model slot stays empty on purpose -- the Throwable scene keeps whatever mesh it ships")
	t = null


# --- the shared name rules -------------------------------------------------------------------------------------
# slugify / titleize are the ONE naming seam every generator routes through (the New tab, Blueprints and New Level
# all call them): slugify decides the FILE NAME, titleize the display name. The New tab's refusal -- "it needs at
# least one letter or digit" -- is worded around slugify returning "", so that empty return is a CONTRACT here, not
# an implementation detail of the loop.

func test_slugify_makes_a_file_safe_snake_case_base() -> void:
	assert_eq(Scaffold.slugify("Plasma Rifle!"), "plasma_rifle", "spaces and punctuation collapse to one underscore")
	assert_eq(Scaffold.slugify("  Raider Camp  "), "raider_camp", "surrounding whitespace is trimmed off first")
	assert_eq(Scaffold.slugify("Mk 2"), "mk_2", "digits are kept as-is")

func test_slugify_returns_empty_when_there_is_no_letter_or_digit() -> void:
	assert_eq(Scaffold.slugify("!!!"), "", "punctuation alone leaves no name to build a file from")
	assert_eq(Scaffold.slugify("   "), "", "whitespace alone leaves no name either")

func test_titleize_reads_any_spelling_back_as_a_display_name() -> void:
	assert_eq(Scaffold.titleize("raider_camp"), "Raider Camp", "an id reads back as a display name")
	assert_eq(Scaffold.titleize("ghoul"), "Ghoul", "a bare word is capitalised")
