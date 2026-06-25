extends GutTest

## Smoke-validation for the authored SAMPLE resources (designer starting points + pipeline exercisers). Each must
## load as its declared class with sensible content — a failure here means a sample drifted from its script's
## schema (a renamed/removed @export, a broken ref). Cheap insurance for content that code-only tests never touch.

func test_sample_loot_table_loads_with_entries() -> void:
	var lt := load("res://resources/loot/sample_loot.tres") as LootTable
	assert_not_null(lt, "sample loot table loads as a LootTable")
	if lt != null:
		assert_gt(lt.entries.size(), 0, "it has loot entries")
		assert_not_null(lt.entries[0].item, "the first entry references a real item")

func test_sample_perks_load_with_prereq_chain() -> void:
	var base := load("res://resources/perks/tough_hide.tres") as Perk
	var gated := load("res://resources/perks/deadeye.tres") as Perk
	assert_not_null(base, "base perk loads")
	assert_not_null(gated, "gated perk loads")
	if base != null and gated != null:
		assert_true(gated.requires_perks.has(base.id), "deadeye is gated behind tough_hide (demonstrates the perk tree)")

func test_sample_status_effects_load() -> void:
	var poison := load("res://resources/status/poison.tres") as StatusEffect
	var adren := load("res://resources/status/adrenaline.tres") as StatusEffect
	assert_not_null(poison, "poison loads")
	assert_not_null(adren, "adrenaline loads")
	if poison != null:
		assert_gt(poison.damage_per_tick, 0.0, "poison ticks damage")
	if adren != null:
		assert_gt(adren.speed_multiplier, 1.0, "adrenaline hastens movement")

func test_sample_quest_loads_with_objectives_and_rewards() -> void:
	var q := load("res://resources/quests/clear_the_block.tres") as Quest
	assert_not_null(q, "sample quest loads")
	if q != null:
		assert_gt(q.objectives.size(), 0, "it has objectives")
		assert_gt(q.rewards.size(), 0, "it has item rewards")

func test_other_samples_load_as_their_class() -> void:
	assert_true(load("res://resources/encounters/raider_squad.tres") is SpawnDefinition, "encounter wave is a SpawnDefinition")
	assert_true(load("res://resources/schedules/townsperson_day.tres") is Schedule, "schedule loads")
	assert_true(load("res://resources/cutscenes/sample_cutscene.tres") is Cutscene, "cutscene loads")
	assert_true(load("res://resources/barks/raider_barks.tres") is BarkSet, "bark set loads")
	assert_true(load("res://resources/loadouts/pistol_starter.tres") is Loadout, "loadout loads")
	assert_true(load("res://resources/abilities/grapple_default.tres") is GrappleHookResource, "grapple resource loads")
	assert_true(load("res://resources/maps/sample_map.tres") is MapData, "map data loads")
