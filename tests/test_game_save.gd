extends GutTest

## Disk autosave (GameState): the save PROFILE — capture off a player, make_stats back into a sheet, the
## ConfigFile round-trip, and the New-Game reset. Tested on FRESH off-tree GameState instances (load().new(),
## never the autoload singleton) and a TEMP save path, so a test run touches neither the real GameState nor the
## user's actual user://gamestate.cfg. The Player-side apply (stats before super, money/unlock/teleport after) is
## in-tree behaviour, playtested.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"
const TMP_SAVE := "user://test_gamestate_tmp.cfg"
const TMP_QUEST := "user://test_quest_tmp.tres"
const TMP_PERK := "user://test_perk_tmp.tres"


func after_each() -> void:
	# Never leave the temp save / authored test resources behind (and never write the real save). The atomic write
	# (H1) also produces .tmp / .bak siblings of the save path — clean those too.
	for f in [TMP_SAVE, TMP_SAVE + ".bak", TMP_SAVE + ".tmp", TMP_QUEST, TMP_PERK]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_make_stats_builds_sheet_from_values() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.stat_values = {&"strength": 3, &"endurance": 4, &"larceny": 2}
	var sheet = gs.make_stats()
	assert_eq(sheet.get_stat(&"strength"), 3, "a saved stat value carries into the built sheet")
	assert_eq(sheet.get_stat(&"endurance"), 4, "a saved endurance value carries into the built sheet")
	assert_eq(sheet.get_stat(&"larceny"), 2, "the merged larceny stat carries through")
	assert_eq(sheet.get_stat(&"gunplay"), 0, "an unsaved stat defaults to baseline 0")
	sheet = null
	gs.free()


# Persistence (rank 10): perks + quests round-trip by resource_path. Quests/perks are GameState state; a perk's
# bonuses + granted ability already ride in [stats] + [player].unlocks, so the [perks] section is a record-only
# ledger. The Player-side restore (a PerkManager re-created in _ready) is in-tree, playtested.

func test_quest_progress_round_trips() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var q := Quest.new()
	q.id = &"qtest"
	var o := QuestObjective.new()
	o.id = &"step"
	o.required_count = 3
	q.objectives.append(o)
	ResourceSaver.save(q, TMP_QUEST)  # give it a resource_path — persistence keys by path
	gs.start_quest(load(TMP_QUEST) as Quest)
	gs.advance_objective(&"qtest", &"step", 2)
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_true(gs2.is_quest_active(&"qtest"), "an active quest round-trips through the save")
	assert_eq(gs2.objective_progress(&"qtest", &"step"), 2, "its objective progress round-trips")
	gs.free()
	gs2.free()

## Save-fidelity (this batch): the day/night clock + active status effects survive a reload.

func test_clock_round_trips() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.time_of_day = 0.31
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_almost_eq(gs2.time_of_day, 0.31, 0.0001, "the day/night clock round-trips through the save")
	gs.free()
	gs2.free()

func test_clock_defaults_to_noon_for_old_save() -> void:
	# A save with no [clock] section (written before clock persistence) loads the noon default, not 0.
	var cfg := ConfigFile.new()
	cfg.set_value("player", "money", 5.0)
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	gs.time_of_day = 0.1  # sentinel != the 0.5 default, so the assert proves load() actually wrote the default
	gs.load_from_disk(TMP_SAVE)
	assert_almost_eq(gs.time_of_day, 0.5, 0.0001, "a [clock]-less save loads noon (0.5), not 0")
	gs.free()

func test_status_effects_round_trip() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.status_effects = [{"path": "res://x.tres", "remaining": 4.5}]
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_eq(gs2.status_effects.size(), 1, "the status-effect list round-trips through the save")
	assert_almost_eq(float(gs2.status_effects[0]["remaining"]), 4.5, 0.001, "with each effect's remaining time")
	gs.free()
	gs2.free()

func test_discovered_corpses_round_trip() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.mark_corpse_discovered("id:alley_body")
	gs.mark_corpse_discovered("")  # ignored, so corrupt/blank keys never enter the save
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_true(gs2.is_corpse_discovered("id:alley_body"), "discovered corpse markers round-trip through the save")
	assert_false(gs2.is_corpse_discovered(""), "blank corpse keys are never treated as discovered")
	gs.free()
	gs2.free()

func test_world_objects_round_trip() -> void:
	# The per-object world-state ledger (v1): a door's open/locked + a consumed pickup / destroyed prop's "gone",
	# keyed by level + object id, survives a save/load — the additive layer over the profile save.
	var gs = load(GAMESTATE_PATH).new()
	gs.record_object_state("res://levels/a.tres", "id:door1", {"open": true, "locked": false})
	gs.record_object_state("res://levels/a.tres", "id:crate1", {"gone": true})
	gs.record_object_state("res://levels/b.tres", "id:door2", {"open": false})
	gs.record_object_state("res://levels/a.tres", "", {"open": true})  # empty key ignored, like blank corpse keys
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_true(gs2.has_object_state("res://levels/a.tres", "id:door1"), "a door's world-state round-trips")
	assert_eq(gs2.object_state("res://levels/a.tres", "id:door1").get("open"), true, "the open bit survives the round-trip")
	assert_eq(gs2.object_state("res://levels/a.tres", "id:crate1").get("gone"), true, "a destroyed prop stays gone")
	assert_true(gs2.has_object_state("res://levels/b.tres", "id:door2"), "a DIFFERENT level's objects are kept separate (keyed by level)")
	assert_false(gs2.has_object_state("res://levels/a.tres", ""), "an empty object key is never recorded")
	assert_eq(gs2.object_state("res://levels/nope.tres", "id:x"), {}, "an unknown level/key reads empty {} (never null)")
	gs.free()
	gs2.free()

func test_world_objects_corrupt_section_degrades_to_empty() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("world_objects", "data", "not a dictionary")  # junk-typed value
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	gs.load_from_disk(TMP_SAVE)
	assert_false(gs.has_object_state("res://levels/a.tres", "id:door1"), "a junk [world_objects] section loads empty, not a crash")
	gs.free()

func test_reset_for_new_game_clears_world_objects() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.record_object_state("res://levels/a.tres", "id:door1", {"open": true})
	gs.reset_for_new_game()
	assert_false(gs.has_object_state("res://levels/a.tres", "id:door1"), "a new game forgets every world-object marker")
	gs.free()

func test_world_object_gone_bit_coerces_through_as_bool() -> void:
	# F-C45: CanPickUp / CanDestroy (and now MoneyPickUp / UpgradePickup) read their "gone" bit via GameState.as_bool
	# instead of bare truthiness — a hand-edited / legacy gamestate.cfg could store a STRING under the key, and a bare
	# non-empty-String test reads true (or bool(<String>) would crash). as_bool degrades non-numeric junk to the
	# fallback, so a String-valued gone bit does NOT falsely despawn a fresh pickup. Mirrors the flag coercion at :521.
	var gs = load(GAMESTATE_PATH).new()
	gs.record_object_state("res://levels/a.tres", "id:crate1", {"gone": "true"})  # String, not a real bool
	assert_false(gs.as_bool(gs.object_state("res://levels/a.tres", "id:crate1").get("gone", false)),
		"a String-valued gone bit degrades to false (never bool(<String>)), so the pickup/prop still spawns")
	gs.record_object_state("res://levels/a.tres", "id:crate2", {"gone": true})   # a well-typed bool still reads true
	assert_true(gs.as_bool(gs.object_state("res://levels/a.tres", "id:crate2").get("gone", false)),
		"a well-typed bool gone bit still reads true — behaviour-preserving for real saves")
	gs.free()

func test_legacy_persuasion_stat_folds_into_streetwise_on_v1_load() -> void:
	# F-C43: the 2026-07-09 stat overhaul renamed "persuasion" to "streetwise". A <v2 save stored points under
	# "persuasion"; the stat-load loop only reads STAT_NAMES (no persuasion), so WITHOUT the version-gated migration
	# those points would silently vanish. The fold adds the legacy value into streetwise. Round-trip pattern of :105.
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)      # a pre-rename save
	cfg.set_value("stats", "persuasion", 5)  # the legacy stat key (not in STAT_NAMES, so the loop drops it)
	cfg.set_value("stats", "streetwise", 2)  # some streetwise already present
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the v1 save loads")
	assert_eq(gs.make_stats().get_stat(&"streetwise"), 7, "legacy persuasion (5) folds into streetwise (2) -> 7")
	gs.free()

	# A v2 save already carries the renamed stat and no persuasion key — the migration is version-gated OFF, so its
	# streetwise loads verbatim (no double-count / re-migration on an already-migrated file).
	var cfg2 := ConfigFile.new()
	cfg2.set_value("meta", "version", 2)
	cfg2.set_value("stats", "streetwise", 3)
	cfg2.save(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the v2 save loads")
	assert_eq(gs2.make_stats().get_stat(&"streetwise"), 3, "a v2 save's streetwise loads unchanged — no re-migration / double-count")
	gs2.free()


func test_legacy_stealth_and_pickpocket_fold_into_larceny_on_old_load() -> void:
	# v3 (2026-07-16): the "stealth" and "pickpocket" stats were consolidated into one "larceny" stat. A <v3 save
	# stored points under BOTH legacy keys; the stat-load loop only reads STAT_NAMES (which now carries larceny, not
	# stealth/pickpocket), so WITHOUT the version-gated migration those points would silently vanish. The fold sums
	# both legacy values into larceny. Mirrors the persuasion->streetwise fold above.
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 2)       # a pre-merge save (any version < 3)
	cfg.set_value("stats", "stealth", 5)      # legacy stealth (not in STAT_NAMES, so the loop drops it) ...
	cfg.set_value("stats", "pickpocket", 2)   # ... plus legacy pickpocket ...
	cfg.set_value("stats", "gunplay", 4)      # ... and a neighbour stat that must survive untouched
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the pre-merge save loads")
	assert_eq(gs.make_stats().get_stat(&"larceny"), 7, "legacy stealth (5) + pickpocket (2) fold into larceny -> 7")
	assert_eq(gs.make_stats().get_stat(&"gunplay"), 4, "a neighbour stat is untouched by the merge migration")
	gs.free()

	# A current-version save carries larceny directly and no legacy keys — the fold is version-gated OFF, so its
	# larceny loads verbatim (no double-count / re-migration on an already-merged file).
	var cfg2 := ConfigFile.new()
	cfg2.set_value("meta", "version", GameState.SAVE_VERSION)
	cfg2.set_value("stats", "larceny", 6)
	cfg2.save(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the merged save loads")
	assert_eq(gs2.make_stats().get_stat(&"larceny"), 6, "a current save's larceny loads unchanged — no re-migration / double-count")
	gs2.free()


## v5 (2026-08-08): the NEGATIVE-WALLET fold. Saves written before the ATM carried the New Game implant bill as a
## negative `money`; the wallet is cash-only now, so on a PRE-v5 file a negative one can only be that legacy debt and
## it is moved onto the signed Ledger account, where a terminal can actually repay it. It is ADDITIVE (a pre-ATM save
## could already owe on the account too), and it is a proper version-gated migration exactly like the two stat folds
## above — a separate `if`, so an ancient save still runs every fold it needs in ONE load.
func test_pre_v5_negative_wallet_folds_onto_the_account_exactly_once() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 4)          # the last schema that could carry debt in the wallet
	cfg.set_value("player", "money", -250.0)     # the old shape: the implant bill hiding in the wallet ...
	cfg.set_value("player", "account", -10.0)    # ... on top of an account that already owed something
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the v4 save loads")
	assert_almost_eq(gs.money, 0.0, 0.001, "the negative wallet is emptied — cash can no longer be negative")
	assert_almost_eq(gs.account, -260.0, 0.001, "the debt is ADDED to the account (-10 + -250), never assigned over it")
	# Keep playing -> autosave: the re-save stamps the current SAVE_VERSION, so the fold is gated OFF on the next load.
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the re-saved profile loads")
	assert_eq(gs2.save_version, GameState.SAVE_VERSION, "re-saving stamps the current SAVE_VERSION (the fold won't re-run)")
	assert_almost_eq(gs2.account, -260.0, 0.001, "the fold ran exactly ONCE — a reload can never double-charge the debt")
	assert_almost_eq(gs2.money, 0.0, 0.001, "...and the emptied wallet stays empty")
	gs.free()
	gs2.free()


## ⭐WHY that fold needed a version gate at all, and the half a "it's idempotent by construction" argument missed: a
## CURRENT run can reach a negative wallet honestly — DialogueChoice.give_money is documented as taking a NEGATIVE
## amount for a fee and Character.add_money does not clamp — so an ungated fold would quietly convert a cash shortfall
## into interest-bearing BANK debt on the next load. At v5+ the wallet's sign means what it says and is left alone.
func test_a_current_version_save_never_folds_a_negative_wallet() -> void:
	assert_gte(GameState.SAVE_VERSION, 5, "the negative-wallet fold is gated at <v5, so the current schema must be at least 5 for this to test anything")
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", GameState.SAVE_VERSION)
	cfg.set_value("player", "money", -40.0)   # a genuine in-run shortfall, NOT legacy implant debt
	cfg.set_value("player", "account", 0.0)
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the current-schema save loads")
	assert_almost_eq(gs.account, 0.0, 0.001, "a v5+ negative wallet is NOT folded — the ledger account is untouched")
	assert_almost_eq(gs.money, -40.0, 0.001, "...and the shortfall stays where it happened, in the wallet")
	gs.free()


func test_world_save_id_key_for() -> void:
	# WorldSaveId is the shared per-object key: an authored save_id is the WHOLE key (stable across moves/renames);
	# a blank id falls back to a level|path|position key. Off-tree (no add_child) so the position is zeroed, not errored.
	var WorldSaveIdScript = load("res://scripts/world/world_save_id.gd")
	var n := Node3D.new()
	n.name = "TestDoor"
	assert_eq(WorldSaveIdScript.key_for(n, &"my_door"), "id:my_door", "an authored save_id is the whole key")
	var fallback: String = WorldSaveIdScript.key_for(n, &"")
	assert_ne(fallback, "id:my_door", "a blank save_id does NOT produce an id: key")
	assert_true(fallback.contains("TestDoor"), "the blank-id fallback includes the node path so keys stay distinct")
	n.free()

func test_disk_load_arms_clock_apply_once() -> void:
	# A genuine disk-load arms the one-shot clock-apply flag, so the Player pushes the saved clock onto the live
	# WorldClock — but consumed ONCE, so a later death-respawn reload (no disk load) won't rewind the clock.
	var gs = load(GAMESTATE_PATH).new()
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_true(gs2.consume_clock_apply(), "a disk-load arms the clock-apply flag")
	assert_false(gs2.consume_clock_apply(), "...and it's a one-shot (a respawn reload won't re-apply / rewind the clock)")
	gs.free()
	gs2.free()

func test_holster_forgiveness_tutorial_state_is_seen_and_reminder_is_one_shot() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_false(gs.holster_forgiveness_tutorial_seen(), "a fresh run has not seen the holster-forgiveness tutorial")
	gs.mark_holster_forgiveness_tutorial_seen()
	assert_true(gs.holster_forgiveness_tutorial_seen(), "marking the tutorial seen uses the story-flag ledger")
	gs.queue_holster_forgiveness_tutorial_reminder()
	assert_true(gs.consume_holster_forgiveness_tutorial_reminder(),
		"a death to the provoking NPC queues one reminder for the next live player")
	assert_false(gs.consume_holster_forgiveness_tutorial_reminder(),
		"the reminder is consume-once, so a HUD rebuild or later spawn does not repeat it")
	gs.free()

const START_MENU_PATH := "res://scripts/ui/start_menu.gd"

func test_profile_active_cleared_by_reset() -> void:
	# P0-2: reset_for_new_game drops the in-memory-authoritative flag; character creation re-sets it.
	var gs = load(GAMESTATE_PATH).new()
	gs.profile_active = true
	gs.reset_for_new_game()
	assert_false(gs.profile_active, "a New Game clears profile_active until character creation stamps the real run")
	gs.free()

func test_profile_active_set_by_disk_load() -> void:
	# P0-2: a disk load makes the run authoritative in memory (alongside `loaded`), so a later CHECKPOINT_FRESH
	# death reload applies the run instead of reseeding a default build.
	var gs = load(GAMESTATE_PATH).new()
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_false(gs2.profile_active, "a fresh instance is not yet an authoritative run")
	gs2.load_from_disk(TMP_SAVE)
	assert_true(gs2.profile_active, "a disk load marks the run authoritative in memory")
	assert_true(gs2.loaded, "...and still sets loaded")
	gs.free()
	gs2.free()

func test_profile_active_wired_into_death_and_creation_paths() -> void:
	# P0-2 is an in-tree apply (Player._ready can't run in a unit test), so pin the wiring by source: the
	# CHECKPOINT_FRESH death branch must promote loaded from profile_active, and character creation must set it.
	var player_src := FileAccess.get_file_as_string(PLAYER_PATH)
	assert_true(player_src.contains("GameState.profile_active"), "player.gd death path reads profile_active")
	assert_true(player_src.contains("GameState.loaded = true"), "player.gd CHECKPOINT_FRESH promotes loaded")
	var menu_src := FileAccess.get_file_as_string(START_MENU_PATH)
	assert_true(menu_src.contains("GameState.profile_active = true"), "character creation marks the run authoritative")

func test_new_game_arms_clock_apply() -> void:
	# New Game arms the flag too (with time_of_day reset to noon) so the Player pushes noon onto the WorldClock
	# autoload, which free-ran while the menu was up.
	var gs = load(GAMESTATE_PATH).new()
	gs.reset_for_new_game()
	assert_almost_eq(gs.time_of_day, 0.5, 0.0001, "New Game resets the clock to noon")
	assert_true(gs.consume_clock_apply(), "New Game arms the clock-apply flag")
	gs.free()

## Level identity (P1): a save reloads the level you saved IN, not GameRoot's exported default.

func test_current_level_round_trips() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.current_level_path = "res://resources/levels/SomeLevel.tres"
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_eq(gs2.current_level_path, "res://resources/levels/SomeLevel.tres", "the active level path round-trips through the save")
	gs.free()
	gs2.free()

func test_no_level_section_loads_empty_path() -> void:
	# A save written before level-identity persisted (no [level] section) loads "" -> GameRoot uses its export.
	var cfg := ConfigFile.new()
	cfg.set_value("player", "money", 1.0)
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	gs.current_level_path = "sentinel"  # set first, so the assert proves load() actually wrote the field
	gs.load_from_disk(TMP_SAVE)
	assert_eq(gs.current_level_path, "", "a [level]-less save loads an empty path (fall back to GameRoot's export)")
	gs.free()

func test_perk_ledger_round_trips() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.perk_paths = ["res://resources/perks/example.tres"]
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_eq(gs2.perk_paths.size(), 1, "the perk ledger round-trips through the save")
	assert_eq(str(gs2.perk_paths[0]), "res://resources/perks/example.tres", "the perk path is preserved")
	gs.free()
	gs2.free()

func test_perk_manager_record_only_round_trip() -> void:
	var perk := Perk.new()
	perk.id = &"ptest"
	ResourceSaver.save(perk, TMP_PERK)
	var pm := PerkManager.new()
	pm.unlock_perk(load(TMP_PERK) as Perk)  # off-tree (host null) -> records only, no stat/ability apply
	assert_eq(pm.unlocked_paths(), [TMP_PERK], "unlocked_paths reports the perk's resource_path")
	var pm2 := PerkManager.new()
	pm2.restore_paths([TMP_PERK])
	assert_true(pm2.has_perk(&"ptest"), "restore_paths re-records the perk in the ledger")
	pm.free()
	pm2.free()


func test_capture_reads_player_money_stats_unlocks() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var p = load(PLAYER_PATH).new()  # off-tree (no _ready): empty unlock set, default money, no sheet
	p.money = 250
	var sheet := CharacterStats.new()
	sheet.strength = 4
	sheet.endurance = 2
	sheet.larceny = 1
	p.stats = sheet
	p.unlock_mechanic(&"grapple")
	gs.capture(p)
	assert_eq(gs.money, 250, "captured the player's wallet")
	assert_eq(int(gs.stat_values[&"strength"]), 4, "captured strength off the live sheet")
	assert_eq(int(gs.stat_values[&"endurance"]), 2, "captured endurance off the live sheet")
	assert_eq(int(gs.stat_values[&"larceny"]), 1, "captured the merged larceny stat off the live sheet")
	assert_true(gs.unlocks.has(&"grapple"), "captured the unlocked mechanic")
	sheet = null
	p.free()
	gs.free()


func test_autosave_skips_offtree_player() -> void:
	# The central guard that stops a test run clobbering the real save: autosave from an OFF-TREE player (a bare
	# unit-test player) returns BEFORE capture/save_to_disk, so it never touches disk. We prove it by the capture
	# being skipped — gs.money keeps its sentinel instead of taking the player's. (This is what protects the
	# bonfire / level-up / pickup tests, which call the autosaving methods on bare players.)
	var gs = load(GAMESTATE_PATH).new()
	var p = load(PLAYER_PATH).new()
	p.money = 250
	gs.money = 100  # sentinel
	assert_false(p.is_inside_tree(), "precondition: the bare test player is off-tree")
	gs.autosave(p)
	assert_eq(gs.money, 100, "off-tree autosave is a no-op — no capture, so no save_to_disk (no clobber)")
	p.free()
	gs.free()


func test_save_load_round_trip_via_temp_path() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 321
	gs.player_name = "Rae Vandel"
	# agility is NEGATIVE: character creation lets a stat go sub-baseline (a real weakness), so the save must carry it.
	gs.stat_values = {&"strength": 2, &"endurance": 5, &"gunplay": 1, &"agility": -3, &"streetwise": 4, &"larceny": 3}
	var unlocks: Array[StringName] = [&"grapple", &"fall_immunity"]
	gs.unlocks = unlocks
	gs.set_respawn(Vector3(5.0, 6.0, 7.0), 2.0)
	gs.save_to_disk(TMP_SAVE)

	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the written save loads back")
	assert_true(gs2.loaded, "a successful load marks the profile present")
	assert_eq(int(gs2.stat_values[&"larceny"]), 3, "a stat round-trips through the [stats] section")
	assert_eq(int(gs2.stat_values[&"endurance"]), 5, "endurance round-trips through the [stats] section")
	assert_eq(str(gs2.player_name), "Rae Vandel", "the character name round-trips through the [player] section")
	assert_eq(int(gs2.stat_values[&"agility"]), -3, "a NEGATIVE stat round-trips (character creation allows sub-baseline builds)")
	var rebuilt: CharacterStats = gs2.make_stats()
	assert_eq(rebuilt.agility, -3, "make_stats rebuilds the negative allocation onto a CharacterStats sheet")
	assert_eq(rebuilt.endurance, 5, "make_stats rebuilds endurance onto a CharacterStats sheet")
	assert_true(rebuilt.move_speed_mult() < 1.0, "the negative agility inverts its derived effect (slower than baseline)")
	assert_true(gs2.unlocks.has(&"grapple") and gs2.unlocks.has(&"fall_immunity"), "unlocks round-trip (as StringNames)")
	assert_true(gs2.has_respawn, "the respawn flag round-trips")
	assert_almost_eq(gs2.respawn_position, Vector3(5.0, 6.0, 7.0), Vector3(0.001, 0.001, 0.001), "respawn position round-trips")
	assert_almost_eq(gs2.respawn_yaw, 2.0, 0.001, "respawn yaw round-trips")
	gs.free()
	gs2.free()


func test_inventory_round_trips_via_temp_path() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.has_inventory = true
	gs.inventory_stacks = [{"id": "pistol", "count": 1}, {"id": "ammo_pistol", "count": 12}]
	gs.equipped_index = 0
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the save with a bag loads back")
	assert_true(gs2.has_inventory, "the [inventory] section marks a saved bag")
	assert_eq(gs2.inventory_stacks.size(), 2, "both stacks round-trip")
	assert_eq(str(gs2.inventory_stacks[0]["id"]), "pistol", "stack order + ids round-trip")
	assert_eq(int(gs2.inventory_stacks[1]["count"]), 12, "stack counts round-trip")
	assert_eq(gs2.equipped_index, 0, "which stack was drawn round-trips")
	gs.free()
	gs2.free()


func test_inventory_placement_round_trips_via_temp_path() -> void:
	# T2: a saved stack also carries its grid placement (x, y, w, h) so the Tetris layout survives a reload. The
	# extra keys are additive — old {id, count} saves (test above) still load fine; these just gain placement.
	var gs = load(GAMESTATE_PATH).new()
	gs.has_inventory = true
	gs.inventory_stacks = [{"id": "pistol", "count": 1, "x": 2, "y": 1, "w": 2, "h": 1}]
	gs.equipped_index = 0
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the placement-bearing save loads back")
	var st: Dictionary = gs2.inventory_stacks[0]
	assert_eq(int(st["x"]), 2, "placement x round-trips")
	assert_eq(int(st["y"]), 1, "placement y round-trips")
	assert_eq(int(st["w"]), 2, "footprint w round-trips")
	assert_eq(int(st["h"]), 1, "footprint h round-trips")
	gs.free()
	gs2.free()


func test_entry_has_placement_detects_valid_numeric_placement() -> void:
	# The save-restore glue that decides "place at the saved cell" vs "auto-place". Keys are Strings (ConfigFile's),
	# and ALL of x/y/w/h must be present + numeric; an old/partial/junk entry degrades to auto-place — and must
	# never int() a non-number (that would error the restore). This is the spot the String-vs-StringName key bug hid.
	var p = load(PLAYER_PATH).new()
	assert_true(p._entry_has_placement({"x": 1, "y": 2, "w": 2, "h": 1}), "a full numeric placement is honoured")
	assert_false(p._entry_has_placement({"id": "pistol", "count": 1}), "an old, placement-less entry -> auto-place")
	assert_false(p._entry_has_placement({"x": 1, "y": 2}), "a partial placement (no w/h) -> auto-place")
	assert_false(p._entry_has_placement({"x": [1], "y": 2, "w": 1, "h": 1}), "a junk-typed coord -> auto-place (no int() crash)")
	p.free()


func test_player_restores_grid_placement_end_to_end() -> void:
	# E2E through the REAL Player restore glue: _restore_saved_inventory -> _entry_has_placement -> restore_stack
	# -> grid.place. It reads the global GameState autoload (what the live restore reads), so snapshot + restore
	# those fields, exactly as the reputation test treats the Reputation autoload. A bare off-tree player has no
	# _ready, so we hand it a grid-enabled bag directly.
	var saved_stacks = GameState.inventory_stacks
	var saved_equip := GameState.equipped_index
	var p = load(PLAYER_PATH).new()
	p.inventory = CharacterInventory.new()
	p.inventory.enable_grid(6, 6)
	GameState.inventory_stacks = [{"id": "pistol", "count": 1, "x": 3, "y": 2, "w": 1, "h": 1}]
	GameState.equipped_index = -1
	p._restore_saved_inventory()
	var rows: Array = p.inventory.placed_contents()
	assert_eq(rows.size(), 1, "the saved stack restored into the bag")
	assert_eq(rows[0]["x"], 3, "restored at the SAVED grid x (proves placement is honoured, not auto-placed to 0,0)")
	assert_eq(rows[0]["y"], 2, "restored at the saved grid y")
	GameState.inventory_stacks = saved_stacks  # leave the autoload as we found it
	GameState.equipped_index = saved_equip
	p.inventory.free()
	p.free()

func test_player_restores_saved_weapon_delta_end_to_end() -> void:
	var template := ItemDb.item_by_id(&"pistol")
	assert_not_null(template, "the authored pistol item is registered")
	var base_damage: float = template.weapon.damage
	var saved_stacks = GameState.inventory_stacks
	var saved_equip := GameState.equipped_index
	var p = load(PLAYER_PATH).new()
	p.inventory = CharacterInventory.new()
	GameState.inventory_stacks = [{
		"id": "pistol",
		"count": 1,
		"weapon_delta": {"damage": base_damage + 7.0}
	}]
	GameState.equipped_index = -1
	p._restore_saved_inventory()
	var rows: Array = p.inventory.contents()
	assert_eq(rows.size(), 1, "the saved weapon restored into the bag")
	var restored: Item = rows[0]["item"]
	assert_true(restored.weapon != template.weapon, "a delta-bearing weapon gets its own WeaponData copy")
	assert_almost_eq(restored.weapon.damage, base_damage + 7.0, 0.001, "the saved per-instance damage delta is applied")
	assert_almost_eq(template.weapon.damage, base_damage, 0.001, "the registered template stays untouched")
	GameState.inventory_stacks = saved_stacks
	GameState.equipped_index = saved_equip
	p.inventory.free()
	p.free()

func test_weapon_delta_round_trips_via_disk() -> void:
	# The end-to-end restore above is in-memory; this guards the SERIALIZATION — the per-instance weapon_delta is a
	# nested Dict of scalars inside an inventory stack, so prove it survives the ConfigFile save -> disk -> load cycle
	# (same shape as the placement keys x/y/w/h, whose disk round-trip is proven above).
	var gs = load(GAMESTATE_PATH).new()
	gs.has_inventory = true
	gs.inventory_stacks = [{"id": "pistol", "count": 1, "weapon_delta": {"damage": 42.0}}]
	gs.equipped_index = -1
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the weapon-delta-bearing save loads back")
	var st: Dictionary = gs2.inventory_stacks[0]
	assert_true(st.has("weapon_delta"), "the weapon_delta key survives the disk round-trip")
	var delta: Dictionary = st["weapon_delta"]
	assert_almost_eq(float(delta["damage"]), 42.0, 0.001, "the per-instance weapon damage delta survives ConfigFile serialization")
	gs.free()
	gs2.free()


func test_save_without_inventory_section_seeds_on_load() -> void:
	# Back-compat: a save written BEFORE inventory persisted (like any existing user save) has no [inventory]
	# section — loading it must report has_inventory false so the Player seeds its authored loadout.
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 50
	gs.save_to_disk(TMP_SAVE)  # has_inventory false -> no [inventory] section written
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the bag-less save still loads")
	assert_false(gs2.has_inventory, "no [inventory] section -> no saved bag -> the Player seeds instead")
	assert_eq(gs2.equipped_index, -1, "no saved equip either")
	gs.free()
	gs2.free()


func test_capture_without_backpack_leaves_inventory_absent() -> void:
	# A bare off-tree player never ran _ready, so it has NO CharacterInventory — capture must leave the
	# inventory fields untouched (has_inventory false) rather than crash or stamp an empty bag.
	var gs = load(GAMESTATE_PATH).new()
	var p = load(PLAYER_PATH).new()
	p.money = 10
	gs.capture(p)
	assert_false(gs.has_inventory, "no backpack on the player -> no bag captured")
	p.free()
	gs.free()

func test_capture_inventory_writes_weapon_delta_only_when_modified() -> void:
	var template := ItemDb.item_by_id(&"pistol")
	assert_not_null(template, "the authored pistol item is registered")
	assert_true(ItemDb.weapon_delta_for(ItemDb.restore_item(&"pistol")).is_empty(), "an unmodified restored weapon writes no delta")
	var p = load(PLAYER_PATH).new()
	p.inventory = CharacterInventory.new()
	var weapon_item := ItemDb.restore_item(&"pistol").clone_unique()
	weapon_item.weapon.damage = template.weapon.damage + 3.0
	p.inventory.add(weapon_item, 1)
	var gs = load(GAMESTATE_PATH).new()
	gs.capture(p)
	assert_true(gs.inventory_stacks[0].has("weapon_delta"), "modified weapon stats serialize as an additive delta")
	assert_almost_eq(float(gs.inventory_stacks[0]["weapon_delta"]["damage"]), template.weapon.damage + 3.0, 0.001, "the changed damage value is saved")
	p.inventory.free()
	p.free()
	gs.free()


func test_item_db_restores_by_id() -> void:
	# ItemDb (autoload) is the save's id resolver: ammo/consumables restore the SHARED template (stacking
	# works by template identity), weapons restore a FRESH unique item, unknown ids restore null (skipped).
	var ammo := ItemDb.item_by_id(&"ammo_pistol")
	assert_not_null(ammo, "the authored ammo_pistol item is registered by id")
	assert_eq(ItemDb.restore_item(&"ammo_pistol"), ammo, "ammo restores the shared template itself")
	var pistol_template := ItemDb.item_by_id(&"pistol")
	assert_not_null(pistol_template, "the authored pistol item is registered by id")
	var restored := ItemDb.restore_item(&"pistol")
	assert_not_null(restored, "a weapon id restores an item")
	assert_true(restored != pistol_template, "a restored weapon is a FRESH unique item, not the template")
	assert_eq(restored.weapon, pistol_template.weapon, "...wrapping the same shared WeaponData")
	assert_null(ItemDb.restore_item(&"no_such_item_xyz"), "an unknown id restores null (the loader skips it)")
	restored = null


func test_load_tolerates_corrupt_save_values() -> void:
	# A hand-edited save can hold ANY type under any key — ConfigFile.load still returns OK for a structurally
	# valid file, so the TYPE guards must catch the junk. This load runs AT BOOT (the autoload's _ready): junk
	# must degrade to defaults (empty bag, fists, default money/respawn), never crash the boot or restore loop.
	var cfg := ConfigFile.new()
	cfg.set_value("player", "money", [1, 2, 3])             # int() on an Array errors un-guarded
	cfg.set_value("player", "unlocks", "not an array")       # `as Array` would yield null -> crash the for
	cfg.set_value("respawn", "has", "yes")                   # bool() on a String errors un-guarded
	cfg.set_value("respawn", "position", "over there")       # typed Vector3 assignment hard-fails un-guarded
	cfg.set_value("inventory", "stacks", "not an array")     # the restore loop calls .size() on this
	cfg.set_value("inventory", "equipped", "junk")
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the structurally-valid file still loads")
	assert_eq(gs.money, GameSettings.economy.player_starting_money, "junk money -> the fresh-game default (the player_starting_money knob)")
	assert_true(gs.unlocks.is_empty(), "junk unlocks -> none")
	assert_false(gs.has_respawn, "junk respawn flag -> no respawn")
	assert_eq(gs.respawn_position, Vector3.ZERO, "junk position -> origin default")
	assert_true(gs.has_inventory, "the [inventory] section is present, junk or not")
	assert_not_null(gs.inventory_stacks, "junk stacks degrade to an empty Array, never null")
	assert_eq(gs.inventory_stacks.size(), 0, "junk stacks -> an empty bag")
	assert_eq(gs.equipped_index, -1, "a junk equipped index -> bare fists")
	gs.free()


func test_bool_coercion_survives_string_valued_flags() -> void:
	# Flags round-trip as their raw Variant (get_flag), so a hand-edited gamestate.cfg can store a flag as a
	# String. Bool consumers now read flags through get_flag_bool -> as_bool, which guards the bool() constructor:
	# Godot 4 has NO bool(<String>) constructor, so a bare bool(get_flag(...)) would crash with "Nonexistent
	# 'bool' constructor". A junk-typed flag must degrade to the fallback. Door.unlock_flag and
	# TutorialPrompt.seen_flag depend on this; Settings._cfg_bool guards the same hazard for settings.cfg.
	var cfg := ConfigFile.new()
	cfg.set_value("flags", "unlock_flag", "true")   # String under a flag key -> bool() would crash un-guarded
	cfg.set_value("flags", "seen_intro", 1)          # numeric flags still coerce (int 1 -> true)
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the structurally-valid file loads")
	assert_false(gs.get_flag_bool(&"unlock_flag"), "a String flag -> the default fallback, no bool() crash")
	assert_true(gs.get_flag_bool(&"unlock_flag", true), "explicit true fallback honored for a String flag")
	assert_true(gs.get_flag_bool(&"seen_intro"), "a numeric-1 flag coerces to true")
	assert_false(gs.get_flag_bool(&"never_set"), "a missing flag -> the fallback")
	# as_bool directly: non-numeric Variants degrade to the fallback (bool() never reached), numerics coerce.
	assert_false(gs.as_bool("true", false), "as_bool(String) -> fallback, never bool(String)")
	assert_true(gs.as_bool("false", true), "as_bool ignores String content and returns the fallback")
	assert_false(gs.as_bool([], false), "as_bool(Array) -> fallback")
	assert_false(gs.as_bool(null, false), "as_bool(null) -> fallback")
	assert_true(gs.as_bool(1, false), "as_bool(int 1) -> true")
	assert_false(gs.as_bool(0.0, true), "as_bool(float 0.0) -> false")
	assert_true(gs.as_bool(true, false), "as_bool(bool) passes through")
	gs.free()


func test_load_missing_file_reports_unloaded() -> void:
	# The Continue gate / fresh-game path: loading a path with no file fails and leaves the profile unloaded.
	var gs = load(GAMESTATE_PATH).new()
	assert_false(gs.load_from_disk("user://definitely_not_a_real_save_42.cfg"), "loading a missing file fails")
	assert_false(gs.loaded, "and the profile stays unloaded (a fresh game)")
	gs.free()


func test_reset_for_new_game_clears_profile() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 999
	gs.stat_values = {&"strength": 5}
	var unlocks: Array[StringName] = [&"grapple"]
	gs.unlocks = unlocks
	var switched_off: Array[StringName] = [&"air_dash"]
	gs.disabled_unlocks = switched_off
	gs.set_respawn(Vector3(1.0, 2.0, 3.0), 1.5)
	gs.has_inventory = true
	gs.inventory_stacks = [{"id": "pistol", "count": 1}]
	gs.equipped_index = 0
	gs.loaded = true
	gs.reset_for_new_game()
	assert_false(gs.loaded, "New Game marks no save loaded (the Player then seeds itself)")
	assert_eq(gs.money, GameSettings.economy.player_starting_money, "money back to the fresh-game default (the player_starting_money knob) — the implant screen re-debits it AFTER this reset")
	assert_true(gs.stat_values.is_empty(), "stat values cleared")
	assert_true(gs.unlocks.is_empty(), "unlocks cleared")
	assert_true(gs.disabled_unlocks.is_empty(), "switched-off implants cleared too (a fresh run has nothing installed)")
	assert_false(gs.has_inventory, "the saved bag is forgotten (a new game seeds the loadout)")
	assert_true(gs.inventory_stacks.is_empty(), "inventory stacks cleared")
	assert_eq(gs.equipped_index, -1, "no saved equip")
	assert_false(gs.has_respawn, "the respawn point is forgotten")
	assert_true(gs.reputation.is_empty(), "saved faction standings cleared on New Game")
	gs.free()

## H1 (atomic autosave): the write goes temp -> rename, rotates the prior good save to .bak, and never strands a .tmp.
## A crash mid-write can no longer corrupt the ONLY save (this is a one-slot design) — worst case is the last write.
func test_save_is_atomic_keeps_bak_and_leaves_no_tmp() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 100.0
	gs.save_to_disk(TMP_SAVE)  # first write: no prior save exists, so nothing to rotate
	assert_true(FileAccess.file_exists(TMP_SAVE), "the save file is written")
	assert_false(FileAccess.file_exists(TMP_SAVE + ".tmp"), "the temp file is renamed away, never left behind")
	assert_false(FileAccess.file_exists(TMP_SAVE + ".bak"), "the FIRST save has no prior good file to rotate -> no .bak yet")
	gs.money = 200.0
	gs.save_to_disk(TMP_SAVE)  # second write: the money=100 save rotates to .bak, the new one swaps in
	assert_false(FileAccess.file_exists(TMP_SAVE + ".tmp"), "still no stray temp after the second write")
	assert_true(FileAccess.file_exists(TMP_SAVE + ".bak"), "the prior good save is rotated to .bak")
	var bak := ConfigFile.new()
	assert_eq(bak.load(TMP_SAVE + ".bak"), OK, "the .bak is a complete, loadable file")
	assert_almost_eq(float(bak.get_value("player", "money", 0.0)), 100.0, 0.001, "the .bak holds the PREVIOUS write (money=100)")
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_almost_eq(gs2.money, 200.0, 0.001, "the primary holds the newest write (money=200)")
	gs.free()
	gs2.free()


## H1 recovery: if the primary save is missing (a crash struck the tiny rename window), load falls back to the .bak
## instead of reporting a fresh game — so the prior checkpoint is still recoverable.
func test_load_recovers_from_bak_when_primary_missing() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 77.0
	gs.save_to_disk(TMP_SAVE)
	# Simulate a crash mid-swap: the good bytes survive only as .bak, the primary is gone.
	DirAccess.copy_absolute(TMP_SAVE, TMP_SAVE + ".bak")
	DirAccess.remove_absolute(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "a missing primary recovers from the .bak")
	assert_true(gs2.loaded, "the recovered profile is marked loaded (Continue still offered)")
	assert_almost_eq(gs2.money, 77.0, 0.001, "the .bak's contents are restored")
	gs.free()
	gs2.free()


## H1 recovery ordering: a crash AFTER the temp write but BEFORE the rename leaves a COMPLETE .tmp (the newest write)
## alongside an older .bak. Recovery must prefer the .tmp (newest) over the .bak (previous good).
func test_load_prefers_tmp_over_bak_on_missing_primary() -> void:
	var newest := ConfigFile.new()
	newest.set_value("player", "money", 20.0)  # the interrupted NEWEST write, sitting in .tmp
	newest.save(TMP_SAVE + ".tmp")
	var older := ConfigFile.new()
	older.set_value("player", "money", 10.0)    # the previous good checkpoint, in .bak
	older.save(TMP_SAVE + ".bak")
	# no primary on disk (the rename never completed)
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "recovers from siblings when the primary is missing")
	assert_almost_eq(gs.money, 20.0, 0.001, "prefers the .tmp (newest interrupted write) over the older .bak (10)")
	gs.free()


# --- H1 recovery, the REJECTION half ---------------------------------------------------------------------------
## The tests above cover a MISSING primary. These cover a primary that is still THERE and still parses — the case
## `ConfigFile.load() == OK` cannot see. ConfigFile returns OK for a zero-length file (zero sections) and for any
## fragment cut at a line boundary, so gating the ladder on the Error alone accepted a shredded primary as a pristine
## profile: `loaded`/`profile_active` true, every field silently at its default, and the .tmp/.bak that still held
## the run never even consulted. The ladder therefore asks a second question per rung — does this file LOOK like one
## of ours (GameState._cfg_is_profile / PROFILE_SECTIONS) — and each rung parses into its OWN ConfigFile so a
## rejected one can never leave residue behind for the fallback to be merged on top of.

## Overwrite `path` with EXACTLY `text` ("" truncates it to zero bytes). The corruption these tests simulate is a
## partial/empty file on disk, which no ConfigFile call can produce — it has to be stored as raw bytes.
func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)  # WRITE truncates an existing file
	assert_not_null(f, "the test fixture must be writable at %s" % path)
	if f != null:
		f.store_string(text)
		f.close()


func test_zero_length_primary_falls_through_to_the_bak() -> void:
	# The crash-during-create shape: the primary exists but holds nothing. It must be SKIPPED, not loaded as an
	# empty-but-valid profile (which is how a real run gets silently replaced by a default character).
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 512.0
	gs.player_name = "Bak Holder"
	gs.save_to_disk(TMP_SAVE)
	DirAccess.copy_absolute(TMP_SAVE, TMP_SAVE + ".bak")  # the previous good checkpoint survives beside it
	_write_raw(TMP_SAVE, "")
	var probe := ConfigFile.new()
	assert_eq(probe.load(TMP_SAVE), OK, "precondition: a 0-byte file parses OK — the Error alone can never catch this")
	assert_true(probe.get_sections().is_empty(), "precondition: ...with zero sections, indistinguishable from a fresh profile once you read keys")
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "a zero-length primary falls through to the .bak instead of loading as an empty profile")
	assert_almost_eq(gs2.money, 512.0, 0.001, "...and the .bak's wallet is what loads (a default 0/knob here would BE the bug)")
	assert_eq(str(gs2.player_name), "Bak Holder", "...character and all")
	gs.free()
	gs2.free()


func test_a_truncated_primary_with_no_recognisable_section_falls_through() -> void:
	# A file cut at a LINE BOUNDARY still parses — this one is sliced down to a single mid-file section — so only the
	# "does it look like one of our saves" gate can reject it. [reputation] is a real save section but deliberately
	# NOT a PROFILE_SECTIONS sentinel, so this is exactly the shape the sentinel list exists to refuse.
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 640.0
	gs.reputation = {"faction_alpha": 12.0}  # guarantees a [reputation] section to slice out
	gs.save_to_disk(TMP_SAVE)
	DirAccess.copy_absolute(TMP_SAVE, TMP_SAVE + ".bak")
	var text := FileAccess.get_file_as_string(TMP_SAVE)
	var start := text.find("[reputation]")
	assert_gte(start, 0, "precondition: the written save carries a [reputation] section to slice")
	var stop := text.find("\n[", start + 1)
	assert_gte(stop, 0, "precondition: another section follows it, so the slice ends on a line boundary")
	_write_raw(TMP_SAVE, text.substr(start, stop - start + 1))
	var probe := ConfigFile.new()
	assert_eq(probe.load(TMP_SAVE), OK, "precondition: the truncated primary still PARSES")
	assert_true(probe.has_section("reputation"), "precondition: ...and still carries a real save section, just not a sentinel one")
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the shredded primary is skipped and the .bak loads")
	assert_almost_eq(gs2.money, 640.0, 0.001, "...restoring the wallet the fragment no longer carried")
	gs.free()
	gs2.free()


func test_recovery_never_merges_the_rejected_primary_onto_the_fallback() -> void:
	# ⭐THE FRANKEN-PROFILE GUARD. ConfigFile.load() does NOT clear what the instance already holds, so ONE shared
	# ConfigFile across the ladder let a rejected primary's keys survive underneath the fallback's — the .bak's money
	# sitting beside the dead primary's level/clock/status, a blended save that loads without a single warning.
	# Every field below is authored DIFFERENTLY in the two files, so a blend cannot pass by luck.
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 100.0
	gs.player_name = "Bak Run"
	gs.time_of_day = 0.25
	gs.current_level_path = "res://levels/bak.tres"
	gs.reputation = {"faction_alpha": 11.0}
	gs.save_to_disk(TMP_SAVE)
	DirAccess.copy_absolute(TMP_SAVE, TMP_SAVE + ".bak")
	# The rejected primary: parses fine, carries a CONFLICTING value for every field the .bak sets — plus a [status]
	# section the .bak never wrote at all (the sharpest tell, since a blend has nothing to overwrite it with).
	var rogue := ConfigFile.new()
	rogue.set_value("reputation", "faction_alpha", 999.0)
	rogue.set_value("clock", "time_of_day", 0.99)
	rogue.set_value("level", "path", "res://levels/rogue.tres")
	rogue.set_value("status", "effects", [{"path": "res://fx/rogue.tres", "remaining": 9.0}])
	assert_eq(rogue.save(TMP_SAVE), OK, "the rogue primary writes")
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the ladder rejects the rogue primary and recovers from the .bak")
	assert_almost_eq(gs2.money, 100.0, 0.001, "the .bak's wallet loads")
	assert_eq(str(gs2.player_name), "Bak Run", "...and its character")
	assert_almost_eq(gs2.time_of_day, 0.25, 0.0001, "the clock is the .bak's 0.25, NOT the rejected primary's 0.99")
	assert_eq(str(gs2.current_level_path), "res://levels/bak.tres", "the level identity is purely the .bak's")
	assert_almost_eq(float(gs2.reputation.get("faction_alpha", 0.0)), 11.0, 0.01, "a faction standing present in BOTH files takes the .bak's value")
	assert_true(gs2.status_effects.is_empty(), "a section the .bak never wrote does not leak in from the rejected primary — the loaded profile is ONE file's")
	gs.free()
	gs2.free()


func test_a_tail_truncated_primary_falls_through_to_a_complete_bak() -> void:
	# save_to_disk writes [meta]/[player] FIRST and [perks]/[quests] LAST, so a truncated write keeps its HEAD:
	# money and stats survive while perks and quests vanish. The section sentinel alone cannot catch that — the
	# file genuinely IS one of ours — so save_to_disk stamps [eof] as its final section and the ladder demands it.
	# Losing one write to the .bak is strictly better than resuming a run with its perks and quests silently gone.
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 777.0
	gs.skill_points = 4  # rides [perks], written near the END of the file — the part a truncation eats
	gs.save_to_disk(TMP_SAVE)
	# An older but WHOLE checkpoint in .bak — whole meaning it carries the [eof] marker a finished write leaves.
	var older := ConfigFile.new()
	older.set_value("meta", "version", GameState.SAVE_VERSION)
	older.set_value("player", "money", 111.0)
	older.set_value("perks", "points", 9)
	older.set_value("eof", "complete", true)
	assert_eq(older.save(TMP_SAVE + ".bak"), OK, "the older checkpoint writes")
	var text := FileAccess.get_file_as_string(TMP_SAVE)
	var cut := text.find("\n[stats]")
	assert_gte(cut, 0, "precondition: [stats] follows the [meta]/[player] head, so there is a line boundary to cut on")
	assert_true(text.contains("[eof]"), "precondition: a COMPLETE save carries the terminal marker...")
	_write_raw(TMP_SAVE, text.substr(0, cut + 1))
	assert_false(FileAccess.get_file_as_string(TMP_SAVE).contains("[eof]"), "...and truncating it takes the marker with it")
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the ladder still produces a profile")
	assert_almost_eq(gs2.money, 111.0, 0.001, "but from the COMPLETE .bak, not the truncated primary (777)")
	assert_eq(gs2.skill_points, 9, "so the perks the truncation ate come back with it")
	gs.free()
	gs2.free()


func test_a_marker_less_primary_is_kept_when_no_sibling_is_complete() -> void:
	# BACKWARDS COMPATIBILITY, pinned. Every save written before the [eof] marker existed lacks it, and so does
	# every hand-built fixture in this file. Demanding the marker unconditionally would have erased those profiles
	# outright, so the ladder only prefers a sibling that verifiably HAS one — with no such sibling it keeps the
	# primary and reads it exactly as it did before the marker. This is the case that must never get stricter.
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "version", GameState.SAVE_VERSION)
	legacy.set_value("player", "money", 250.0)
	legacy.set_value("perks", "points", 3)
	assert_eq(legacy.save(TMP_SAVE), OK, "the marker-less legacy save writes")
	assert_false(FileAccess.get_file_as_string(TMP_SAVE).contains("[eof]"), "precondition: it carries no terminal marker")
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "a marker-less save with no complete sibling still loads")
	assert_almost_eq(gs.money, 250.0, 0.001, "and it is read in full")
	assert_eq(gs.skill_points, 3, "including the sections a truncation would have eaten")
	gs.free()


func test_a_marker_less_bak_still_rescues_an_unusable_primary() -> void:
	# The other half of the compatibility rule, and the sharper edge of it. The marker ARBITRATES between rungs; it
	# must never CONDEMN one on its own. A player whose save predates the marker still has a pre-marker .bak, so if
	# requiring the marker could veto that rung, the first real corruption would turn a fully recoverable run into
	# "no save found" — strictly worse than the behaviour this whole ladder was hardened to fix.
	var older := ConfigFile.new()
	older.set_value("meta", "version", GameState.SAVE_VERSION)
	older.set_value("player", "money", 432.0)
	assert_eq(older.save(TMP_SAVE + ".bak"), OK, "the marker-less legacy .bak writes")
	_write_raw(TMP_SAVE, "")  # the primary is shredded to zero bytes
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the unusable primary still falls through to the marker-less .bak")
	assert_almost_eq(gs.money, 432.0, 0.001, "and the legacy checkpoint is read")
	gs.free()


func test_the_ladder_still_accepts_a_sparse_legacy_save() -> void:
	# The counterweight to every rejection above: the sentinel list is deliberately WIDER than [meta]/[player],
	# because a legitimately sparse file is a real save. A pre-versioning profile has no [meta] at all (the
	# test_legacy_save_without_meta_reads_version_0 fixture), and hand-authored migration fixtures can carry a
	# single section. Refusing those would be a worse bug than the shredded-primary one the gate exists to catch.
	var cfg := ConfigFile.new()
	cfg.set_value("player", "money", 61.0)  # [player] and nothing else: a save written before versioning
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "a [meta]-less legacy save is a REAL save — the sentinel gate must not reject it")
	assert_almost_eq(gs.money, 61.0, 0.001, "...and its wallet loads")
	assert_eq(gs.save_version, 0, "...still reading as version 0, so every migration below still runs on it")
	gs.free()
	var flags_only := ConfigFile.new()
	flags_only.set_value("flags", "seen_intro", 1)  # the sparsest shape in the suite (see test_bool_coercion_...)
	flags_only.save(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "a single-section [flags] fixture is still recognised as a profile")
	assert_true(gs2.get_flag_bool(&"seen_intro"), "...and its flags load")
	gs2.free()


## H1b: every save stamps [meta].version = SAVE_VERSION, and a load reads it back into save_version.
func test_save_stamps_meta_version() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.save_to_disk(TMP_SAVE)
	var cfg := ConfigFile.new()
	cfg.load(TMP_SAVE)
	assert_eq(int(cfg.get_value("meta", "version", -1)), GameState.SAVE_VERSION, "the save stamps the current schema version under [meta].version")
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_eq(gs2.save_version, GameState.SAVE_VERSION, "load reads the stamped version back into save_version")
	gs.free()
	gs2.free()


## H1b back-compat: a save written before versioning (no [meta] section) reads version 0 (a future migration can
## detect + upgrade it) — never a crash, and nothing is gated on it yet.
func test_legacy_save_without_meta_reads_version_0() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "money", 5.0)  # a pre-versioning save: no [meta] section
	cfg.save(TMP_SAVE)
	var gs = load(GAMESTATE_PATH).new()
	gs.save_version = 999  # sentinel, so the assert proves load() actually wrote the field
	gs.load_from_disk(TMP_SAVE)
	assert_eq(gs.save_version, 0, "a [meta]-less save reads version 0")
	gs.free()


func test_agility_persists() -> void:
	# Regression: agility used to be omitted from STAT_NAMES, so a leveled agility was silently dropped on save.
	var gs = load(GAMESTATE_PATH).new()
	gs.stat_values = {&"agility": 3}
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_eq(int(gs2.stat_values.get(&"agility", 0)), 3, "agility now survives the disk round-trip")
	gs.free()
	gs2.free()

func test_reputation_round_trips_through_save() -> void:
	# Faction standings (the global Reputation autoload) get snapshotted by capture and survive save/load.
	Reputation.reset()
	var f := Faction.new()
	f.id = &"test_rep_faction"
	Reputation.add_reputation(f, 40.0)  # no player in a unit test -> unscaled -> +40
	var gs = load(GAMESTATE_PATH).new()
	var player = load(PLAYER_PATH).new()
	gs.capture(player)
	assert_almost_eq(float(gs.reputation.get("test_rep_faction", 0.0)), 40.0, 0.01, "capture snapshots live standing")
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_almost_eq(float(gs2.reputation.get("test_rep_faction", 0.0)), 40.0, 0.01, "standing survives the disk round-trip")
	player.free()
	gs.free()
	gs2.free()
	f = null
	Reputation.reset()  # global autoload — leave it clean for other tests


# --- Whole-profile no-data-loss round-trip (the save-schema regression canary) --------------------------------
## The single test that fails the moment a persisted field is wired into save_to_disk but not load_from_disk (or
## vice versa): populate EVERY directly-assertable profile field, write the ConfigFile, load it into a FRESH
## instance, and assert every field survives byte-for-byte. The section-scoped tests above each guard ONE part of
## the schema; this is the whole-profile canary ("save -> load -> verify exact field round-trip, no data loss").
## Quests need a resource_path to round-trip, so a temp Quest .tres is authored inline; the perk ledger is plain
## Strings/ints and round-trips without a resource. Level IDENTITY + the respawn-level-match GATE live on GameRoot
## (test_level_flow.gd / test_level_boot_lifecycle.gd), so only current_level_path is asserted here.
func test_full_profile_round_trips_no_data_loss() -> void:
	var gs = load(GAMESTATE_PATH).new()
	# --- populate every persisted field (varied values incl. a NEGATIVE stat + a NEGATIVE standing) ---
	gs.money = 4321.5
	gs.player_name = "Neon Vega"
	gs.appearance = {"head": "head_punk", "body": "body_heavy", "skin": Color(0.8, 0.6, 0.5), "arm": Color(0.2, 0.2, 0.25), "leg": Color(0.1, 0.15, 0.2)}
	gs.xp = 1234.0
	gs.level = 7
	var unlocks: Array[StringName] = [&"grapple", &"double_jump", &"fall_immunity"]
	gs.unlocks = unlocks
	gs.stat_values = {&"strength": 4, &"endurance": 6, &"gunplay": 2, &"agility": -3, &"streetwise": 5, &"larceny": 1}
	gs.reputation = {"faction_alpha": 55.0, "faction_beta": -22.5}
	gs.flags = {"met_boss": true, "coins_found": 12, "codeword": "swordfish"}  # bool / int / String values all round-trip
	gs.mark_corpse_discovered("id:alley_body")
	gs.mark_corpse_discovered("id:rooftop_body")
	gs.record_object_state("res://levels/downtown.tres", "id:door_north", {"open": true, "locked": false})
	gs.record_object_state("res://levels/sewers.tres", "id:crate_7", {"gone": true})
	gs.time_of_day = 0.73
	gs.status_effects = [{"path": "res://fx/poison.tres", "remaining": 4.5}, {"path": "res://fx/haste.tres", "remaining": 1.25}]
	gs.current_level_path = "res://resources/levels/DownTown.tres"
	gs.set_respawn(Vector3(12.0, 3.0, -8.0), 1.75)
	gs.has_inventory = true
	gs.inventory_stacks = [
		{"id": "pistol", "count": 1, "x": 0, "y": 0, "w": 2, "h": 1, "weapon_delta": {"damage": 19.0}},
		{"id": "ammo_pistol", "count": 24},
	]
	gs.equipped_index = 0
	gs.perk_paths = ["res://resources/perks/quick_hands.tres", "res://resources/perks/deadeye.tres"]
	gs.perk_grants = {"deadeye": "aim_snap"}
	gs.skill_points = 3
	gs.points_earned = 9
	# An ACTIVE quest with partial progress (needs a resource_path — persistence keys quests by path).
	var q := Quest.new()
	q.id = &"qcanary"
	var o := QuestObjective.new()
	o.id = &"collect"
	o.required_count = 5
	q.objectives.append(o)
	ResourceSaver.save(q, TMP_QUEST)
	gs.start_quest(load(TMP_QUEST) as Quest)
	gs.advance_objective(&"qcanary", &"collect", 3)  # 3 of 5 -> stays active, progress must survive

	gs.save_to_disk(TMP_SAVE)

	# --- load into a FRESH instance and assert nothing was lost ---
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the fully-populated profile loads back")
	assert_almost_eq(gs2.money, 4321.5, 0.001, "money round-trips")
	assert_eq(str(gs2.player_name), "Neon Vega", "player_name round-trips")
	assert_eq(str(gs2.appearance.get("head", "")), "head_punk", "appearance head round-trips")
	assert_eq(str(gs2.appearance.get("body", "")), "body_heavy", "appearance body round-trips")
	assert_true(gs2.appearance.has("skin") and (gs2.appearance["skin"] as Color).is_equal_approx(Color(0.8, 0.6, 0.5)), "appearance skin colour round-trips")
	assert_true(gs2.appearance.has("arm") and (gs2.appearance["arm"] as Color).is_equal_approx(Color(0.2, 0.2, 0.25)), "appearance arm colour round-trips")
	assert_true(gs2.appearance.has("leg") and (gs2.appearance["leg"] as Color).is_equal_approx(Color(0.1, 0.15, 0.2)), "appearance leg colour round-trips")
	assert_almost_eq(gs2.xp, 1234.0, 0.001, "xp round-trips")
	assert_eq(gs2.level, 7, "level round-trips")
	assert_true(gs2.unlocks.has(&"grapple") and gs2.unlocks.has(&"double_jump") and gs2.unlocks.has(&"fall_immunity"), "every unlock round-trips (as StringNames)")
	assert_eq(gs2.unlocks.size(), 3, "no phantom / dropped unlocks")
	for n in GameState.STAT_NAMES:
		assert_eq(int(gs2.stat_values.get(n, 999)), int(gs.stat_values[n]), "stat '%s' round-trips (the loop covers EVERY stat incl. the negative agility)" % n)
	assert_almost_eq(float(gs2.reputation.get("faction_alpha", 0.0)), 55.0, 0.01, "a positive faction standing round-trips")
	assert_almost_eq(float(gs2.reputation.get("faction_beta", 0.0)), -22.5, 0.01, "a NEGATIVE faction standing round-trips")
	assert_eq(gs2.get_flag(&"met_boss"), true, "a bool flag round-trips as a bool")
	assert_eq(int(gs2.get_flag(&"coins_found")), 12, "an int flag round-trips as an int")
	assert_eq(str(gs2.get_flag(&"codeword")), "swordfish", "a String flag round-trips as a String")
	assert_true(gs2.is_corpse_discovered("id:alley_body") and gs2.is_corpse_discovered("id:rooftop_body"), "both corpse markers round-trip")
	assert_eq(gs2.object_state("res://levels/downtown.tres", "id:door_north").get("open"), true, "a door's open bit round-trips")
	assert_eq(gs2.object_state("res://levels/downtown.tres", "id:door_north").get("locked"), false, "a door's locked bit round-trips")
	assert_eq(gs2.object_state("res://levels/sewers.tres", "id:crate_7").get("gone"), true, "a destroyed prop's gone bit round-trips (kept separate per level)")
	assert_almost_eq(gs2.time_of_day, 0.73, 0.0001, "the day/night clock round-trips")
	assert_eq(gs2.status_effects.size(), 2, "both status effects round-trip")
	assert_almost_eq(float(gs2.status_effects[0]["remaining"]), 4.5, 0.001, "the first effect's remaining time round-trips")
	assert_eq(str(gs2.current_level_path), "res://resources/levels/DownTown.tres", "the active level path round-trips")
	assert_true(gs2.has_respawn, "the respawn flag round-trips")
	assert_almost_eq(gs2.respawn_position, Vector3(12.0, 3.0, -8.0), Vector3(0.001, 0.001, 0.001), "the respawn position round-trips")
	assert_almost_eq(gs2.respawn_yaw, 1.75, 0.001, "the respawn yaw round-trips")
	assert_true(gs2.has_inventory, "the bag flag round-trips")
	assert_eq(gs2.inventory_stacks.size(), 2, "both inventory stacks round-trip")
	assert_eq(str(gs2.inventory_stacks[0]["id"]), "pistol", "stack order + ids round-trip")
	assert_eq(int(gs2.inventory_stacks[0]["x"]), 0, "a stack's grid placement round-trips")
	assert_true(gs2.inventory_stacks[0].has("weapon_delta"), "the per-instance weapon delta survives the round-trip")
	assert_almost_eq(float(gs2.inventory_stacks[0]["weapon_delta"]["damage"]), 19.0, 0.001, "the weapon delta's value round-trips")
	assert_eq(int(gs2.inventory_stacks[1]["count"]), 24, "a second stack's count round-trips")
	assert_eq(gs2.equipped_index, 0, "the drawn-weapon index round-trips")
	assert_eq(gs2.perk_paths.size(), 2, "the perk ledger round-trips")
	assert_eq(str(gs2.perk_grants.get("deadeye", "")), "aim_snap", "the perk-grant ledger round-trips")
	assert_eq(gs2.skill_points, 3, "unspent skill points round-trip")
	assert_eq(gs2.points_earned, 9, "cumulative earned points round-trip")
	assert_true(gs2.is_quest_active(&"qcanary"), "the active quest round-trips")
	assert_eq(gs2.objective_progress(&"qcanary", &"collect"), 3, "the quest's partial objective progress round-trips")
	q = null
	o = null
	gs.free()
	gs2.free()


## A schema-SHAPE guard complementary to the round-trip above: a fully-populated profile must stamp every expected
## [section] in the ConfigFile. If a save section is ever dropped (a removed set_value), this fails with the exact
## missing section — including the case a symmetric round-trip can hide (a field whose in-memory default happens to
## equal what was written). Sections written only-when-non-empty are populated here so all should be present.
func test_save_writes_all_expected_sections() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.money = 10.0
	gs.player_name = "X"
	gs.appearance = {"head": "h"}          # -> [appearance] (else omitted)
	var unlocks: Array[StringName] = [&"grapple"]
	gs.unlocks = unlocks
	gs.stat_values = {&"strength": 1}
	gs.reputation = {"f": 1.0}             # -> [reputation]
	gs.flags = {"k": true}                 # -> [flags]
	gs.mark_corpse_discovered("id:c")      # -> [world]
	gs.record_object_state("res://l.tres", "id:o", {"gone": true})  # -> [world_objects]
	gs.status_effects = [{"path": "res://fx.tres", "remaining": 1.0}]  # -> [status]
	gs.current_level_path = "res://lvl.tres"  # -> [level]
	gs.has_inventory = true
	gs.inventory_stacks = [{"id": "pistol", "count": 1}]  # -> [inventory]
	gs.set_respawn(Vector3.ONE, 0.0)
	gs.save_to_disk(TMP_SAVE)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP_SAVE), OK, "the save file loads as a ConfigFile")
	# [perks] is always stamped (points/earned write unconditionally); the rest are populated above.
	for section in ["meta", "player", "appearance", "stats", "reputation", "flags", "world", "world_objects", "respawn", "clock", "status", "level", "inventory", "perks"]:
		assert_true(cfg.has_section(section), "the save stamps the [%s] section" % section)
	gs.free()


## The full "load an old save, keep playing, autosave" LIFECYCLE across BOTH stat migrations: a v1 file's legacy
## persuasion folds into streetwise (C43) AND its legacy stealth+pickpocket fold into larceny (v3) in ONE load —
## the two folds are separate `if` branches, so an ancient save runs every fold it needs — WITHOUT disturbing its
## neighbour fields (money / respawn / inventory). RE-SAVING stamps the current SAVE_VERSION so each migration is
## one-shot — a second load neither re-runs it nor double-counts. Extends the isolated fold tests to the round-trip
## the shipping game performs on every Continue-then-autosave.
func test_old_save_migrates_and_resave_stamps_current_version() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("player", "money", 812.0)
	cfg.set_value("stats", "persuasion", 4)   # legacy stat (dropped by the STAT_NAMES loop) ...
	cfg.set_value("stats", "streetwise", 3)   # ... folded into an existing streetwise
	cfg.set_value("stats", "stealth", 5)      # legacy stealth ...
	cfg.set_value("stats", "pickpocket", 2)   # ... plus legacy pickpocket, both folded into larceny (5 + 2 = 7)
	cfg.set_value("stats", "strength", 6)     # a neighbour stat that must survive untouched
	cfg.set_value("respawn", "has", true)
	cfg.set_value("respawn", "position", Vector3(9.0, 1.0, 2.0))
	cfg.set_value("inventory", "stacks", [{"id": "pistol", "count": 1}])
	cfg.set_value("inventory", "equipped", 0)
	cfg.save(TMP_SAVE)

	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the v1 save loads")
	assert_eq(gs.save_version, 1, "the loaded schema version is recorded as v1")
	assert_eq(int(gs.stat_values[&"streetwise"]), 7, "legacy persuasion (4) folds into streetwise (3) -> 7")
	assert_eq(int(gs.stat_values[&"larceny"]), 7, "legacy stealth (5) + pickpocket (2) fold into larceny -> 7 (same load)")
	assert_eq(int(gs.stat_values[&"strength"]), 6, "a neighbour stat is untouched by the migrations")
	assert_almost_eq(gs.money, 812.0, 0.001, "money is untouched by the migration")
	assert_true(gs.has_respawn, "the respawn survives the migration load")
	assert_true(gs.has_inventory, "the inventory survives the migration load")

	# Continue playing -> autosave: re-write, then re-load. The re-save stamps the CURRENT schema version, so both
	# migrations are version-gated OFF on the next load and the folded stats stay put (no re-fold / double-count).
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the re-saved profile loads")
	assert_eq(gs2.save_version, GameState.SAVE_VERSION, "re-saving stamps the current SAVE_VERSION (the migrations won't re-run)")
	assert_eq(int(gs2.stat_values[&"streetwise"]), 7, "streetwise stays 7 on reload — the one-shot migration did NOT re-run / double-count")
	assert_eq(int(gs2.stat_values[&"larceny"]), 7, "larceny stays 7 on reload — the merge fold is one-shot too")
	assert_eq(int(gs2.stat_values[&"strength"]), 6, "the neighbour stat is still intact after the re-save cycle")
	gs.free()
	gs2.free()


## "Corpse markers survive across saves": the discovery ledger is set by mark_corpse_discovered (NOT captured off
## the player), so it must survive (a) more than one save/load cycle and (b) a capture() — a mid-run autosave
## re-captures the player but must NOT wipe the accumulated markers. test_discovered_corpses_round_trip covers a
## single hop; this guards the repeated-autosave reality.
func test_corpse_markers_survive_multiple_save_cycles_and_capture() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.mark_corpse_discovered("id:body_a")
	gs.mark_corpse_discovered("id:body_b")
	gs.save_to_disk(TMP_SAVE)

	# cycle 1: load into gs2
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the first load succeeds")
	# a capture() (as a mid-run autosave would do) must leave the markers in place ...
	var p = load(PLAYER_PATH).new()
	p.money = 5
	gs2.capture(p)
	assert_true(gs2.is_corpse_discovered("id:body_a"), "capture() does not wipe the corpse ledger")
	# ... then a second re-save + reload (cycle 2) still carries both markers
	gs2.save_to_disk(TMP_SAVE)
	var gs3 = load(GAMESTATE_PATH).new()
	assert_true(gs3.load_from_disk(TMP_SAVE), "the second load succeeds")
	assert_true(gs3.is_corpse_discovered("id:body_a"), "corpse marker A survives two save/load cycles + a capture")
	assert_true(gs3.is_corpse_discovered("id:body_b"), "corpse marker B survives two save/load cycles + a capture")
	p.free()
	gs.free()
	gs2.free()
	gs3.free()
