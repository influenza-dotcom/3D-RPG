extends GutTest

## ML-3 DifficultySettings: the live mults the combat/spawn/reward seams read (GameSettings.difficulty) + the
## Easy/Hard presets Settings.set_difficulty copies in. Tested on a FRESH DifficultySettings.new() so it never
## mutates the shared autoload resource (a global the rest of the suite reads). The Settings setter (clamp +
## apply + persist) mirrors every other Settings setter and is playtested.


func test_live_mults_default_to_normal() -> void:
	var d := DifficultySettings.new()
	assert_almost_eq(d.damage_taken_mult, 1.0, 0.0001, "Normal baseline: the player takes normal damage")
	assert_almost_eq(d.damage_dealt_mult, 1.0, 0.0001, "...deals normal damage")
	assert_almost_eq(d.enemy_count_mult, 1.0, 0.0001, "...normal enemy density")
	assert_almost_eq(d.loot_mult, 1.0, 0.0001, "...normal loot")
	assert_almost_eq(d.money_mult, 1.0, 0.0001, "...normal money")
	assert_almost_eq(d.xp_gain_mult, 1.0, 0.0001, "...normal xp — so the whole system is inert until a level is chosen")
	d = null


func test_apply_level_copies_presets_and_normal_resets() -> void:
	var d := DifficultySettings.new()
	d.apply_level(DifficultySettings.Level.EASY)
	assert_almost_eq(d.damage_taken_mult, d.easy_damage_taken_mult, 0.0001, "Easy copies the easy preset into the live mult")
	assert_almost_eq(d.enemy_count_mult, d.easy_enemy_count_mult, 0.0001, "...for every field")
	d.apply_level(DifficultySettings.Level.HARD)
	assert_almost_eq(d.damage_taken_mult, d.hard_damage_taken_mult, 0.0001, "Hard copies the hard preset")
	d.apply_level(DifficultySettings.Level.NORMAL)
	assert_almost_eq(d.damage_taken_mult, 1.0, 0.0001, "Normal resets every live mult to 1.0")
	assert_almost_eq(d.xp_gain_mult, 1.0, 0.0001, "...all of them")
	d.apply_level(999)  # out-of-range falls to Normal
	assert_almost_eq(d.damage_taken_mult, 1.0, 0.0001, "an unknown level falls to the Normal baseline")
	d = null


func test_preset_directions_are_sane() -> void:
	var d := DifficultySettings.new()
	assert_lt(d.easy_damage_taken_mult, 1.0, "Easy: take LESS damage")
	assert_gt(d.hard_damage_taken_mult, 1.0, "Hard: take MORE damage")
	assert_gt(d.easy_damage_dealt_mult, 1.0, "Easy: deal MORE damage")
	assert_lt(d.hard_damage_dealt_mult, 1.0, "Hard: deal LESS damage")
	assert_lt(d.easy_enemy_count_mult, 1.0, "Easy: FEWER enemies")
	assert_gt(d.hard_enemy_count_mult, 1.0, "Hard: MORE enemies")
	d = null


func test_gamesettings_exposes_difficulty_and_settings_has_setter() -> void:
	assert_true(GameSettings.difficulty is DifficultySettings, "GameSettings.difficulty is the live DifficultySettings the seams read")
	assert_true(Settings.has_method(&"set_difficulty"), "Settings exposes set_difficulty for the Options dropdown")
