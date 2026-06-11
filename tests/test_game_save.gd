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
	gs.loaded = true
	gs.reset_for_new_game()
	assert_false(gs.loaded, "New Game marks no save loaded (the Player then seeds itself)")
	assert_eq(gs.money, 100, "money back to the fresh-game default")
	assert_true(gs.stat_values.is_empty(), "stat values cleared")
	assert_true(gs.unlocks.is_empty(), "unlocks cleared")
	assert_false(gs.has_respawn, "the respawn point is forgotten")
	gs.free()
