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
	# Never leave the temp save / authored test resources behind (and never write the real save).
	for f in [TMP_SAVE, TMP_QUEST, TMP_PERK]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_make_stats_builds_sheet_from_values() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.stat_values = {&"strength": 3, &"endurance": 2}
	var sheet = gs.make_stats()
	assert_eq(sheet.get_stat(&"strength"), 3, "a saved stat value carries into the built sheet")
	assert_eq(sheet.get_stat(&"endurance"), 2, "endurance carries through")
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
	sheet.endurance = 1
	p.stats = sheet
	p.unlock_mechanic(&"grapple")
	gs.capture(p)
	assert_eq(gs.money, 250, "captured the player's wallet")
	assert_eq(int(gs.stat_values[&"strength"]), 4, "captured strength off the live sheet")
	assert_eq(int(gs.stat_values[&"endurance"]), 1, "captured endurance")
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
	gs.stat_values = {&"strength": 2, &"persuasion": 1, &"gunplay": 0, &"endurance": 3, &"streetwise": 4}
	var unlocks: Array[StringName] = [&"grapple", &"laser_sight"]
	gs.unlocks = unlocks
	gs.set_respawn(Vector3(5.0, 6.0, 7.0), 2.0)
	gs.save_to_disk(TMP_SAVE)

	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the written save loads back")
	assert_true(gs2.loaded, "a successful load marks the profile present")
	assert_eq(gs2.money, 321, "money round-trips")
	assert_eq(int(gs2.stat_values[&"endurance"]), 3, "a stat round-trips through the [stats] section")
	assert_true(gs2.unlocks.has(&"grapple") and gs2.unlocks.has(&"laser_sight"), "unlocks round-trip (as StringNames)")
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
	gs.set_respawn(Vector3(1.0, 2.0, 3.0), 1.5)
	gs.has_inventory = true
	gs.inventory_stacks = [{"id": "pistol", "count": 1}]
	gs.equipped_index = 0
	gs.loaded = true
	gs.reset_for_new_game()
	assert_false(gs.loaded, "New Game marks no save loaded (the Player then seeds itself)")
	assert_eq(gs.money, GameSettings.economy.player_starting_money, "money back to the fresh-game default (the player_starting_money knob)")
	assert_true(gs.stat_values.is_empty(), "stat values cleared")
	assert_true(gs.unlocks.is_empty(), "unlocks cleared")
	assert_false(gs.has_inventory, "the saved bag is forgotten (a new game seeds the loadout)")
	assert_true(gs.inventory_stacks.is_empty(), "inventory stacks cleared")
	assert_eq(gs.equipped_index, -1, "no saved equip")
	assert_false(gs.has_respawn, "the respawn point is forgotten")
	assert_true(gs.reputation.is_empty(), "saved faction standings cleared on New Game")
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
