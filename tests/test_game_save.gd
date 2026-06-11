extends GutTest

## Disk autosave (GameState): the save PROFILE — capture off a player, make_stats back into a sheet, the
## ConfigFile round-trip, and the New-Game reset. Tested on FRESH off-tree GameState instances (load().new(),
## never the autoload singleton) and a TEMP save path, so a test run touches neither the real GameState nor the
## user's actual user://gamestate.cfg. The Player-side apply (stats before super, money/unlock/teleport after) is
## in-tree behaviour, playtested.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"
const TMP_SAVE := "user://test_gamestate_tmp.cfg"


func after_each() -> void:
	# Never leave the temp save behind (and never write the real one).
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)


func test_make_stats_builds_sheet_from_values() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.stat_values = {&"strength": 3, &"endurance": 2}
	var sheet := gs.make_stats()
	assert_eq(sheet.get_stat(&"strength"), 3, "a saved stat value carries into the built sheet")
	assert_eq(sheet.get_stat(&"endurance"), 2, "endurance carries through")
	assert_eq(sheet.get_stat(&"gunplay"), 0, "an unsaved stat defaults to baseline 0")
	sheet = null
	gs.free()


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
	assert_eq(gs.money, 100, "junk money -> the fresh-game default")
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
	assert_eq(gs.money, 100, "money back to the fresh-game default")
	assert_true(gs.stat_values.is_empty(), "stat values cleared")
	assert_true(gs.unlocks.is_empty(), "unlocks cleared")
	assert_false(gs.has_inventory, "the saved bag is forgotten (a new game seeds the loadout)")
	assert_true(gs.inventory_stacks.is_empty(), "inventory stacks cleared")
	assert_eq(gs.equipped_index, -1, "no saved equip")
	assert_false(gs.has_respawn, "the respawn point is forgotten")
	gs.free()
