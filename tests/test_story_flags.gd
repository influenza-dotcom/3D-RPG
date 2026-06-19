extends GutTest

## Slice 1 (story flags): GameState.set/get/has_flag + the [flags] save/load round-trip + the New-Game wipe,
## and the DialogueChoice flag-gate fields. Uses a FRESH GameState instance (load().new()), never the autoload,
## so it can't touch the user's real user://gamestate.cfg — same isolation pattern as test_game_save.gd. The
## consumer gates (DialogueView disable, Merchant refuse, Lock set-on-unlock) are thin wiring over this surface
## and are playtest-verified per the in-tree-behaviour convention.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const TMP_SAVE := "user://test_story_flags.cfg"

func after_each() -> void:
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))

func test_set_get_has_flag() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_false(gs.has_flag(&"met_boss"), "an unset flag is not present")
	assert_eq(gs.get_flag(&"met_boss"), false, "an unset bool flag reads false (the default fallback)")
	gs.set_flag(&"met_boss")
	assert_true(gs.has_flag(&"met_boss"), "a set flag is present")
	assert_eq(gs.get_flag(&"met_boss"), true, "set_flag's default value is true")
	gs.set_flag(&"raiders_killed", 3)
	assert_eq(gs.get_flag(&"raiders_killed"), 3, "an int flag holds its value")
	gs.free()

func test_stringname_string_key_parity() -> void:
	# The GDScript Dictionary String-vs-StringName hash trap: a StringName-set flag must be found by EITHER form.
	var gs = load(GAMESTATE_PATH).new()
	gs.set_flag(&"door_open")
	assert_true(gs.has_flag("door_open"), "a String lookup finds a StringName-set flag (coerced at the boundary)")
	assert_true(gs.has_flag(&"door_open"), "a StringName lookup finds it too")
	gs.free()

func test_flags_round_trip_through_save() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.set_flag(&"met_boss")
	gs.set_flag(&"raiders_killed", 5)
	gs.set_flag(&"vendor_name", "Marko")
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the flags-bearing save loads back")
	assert_eq(gs2.get_flag(&"met_boss"), true, "a bool flag survives a save")
	assert_eq(gs2.get_flag(&"raiders_killed"), 5, "an int flag survives a save")
	assert_eq(gs2.get_flag(&"vendor_name"), "Marko", "a string flag survives a save")
	gs.free()
	gs2.free()

func test_reset_for_new_game_clears_flags() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.set_flag(&"met_boss")
	gs.reset_for_new_game()
	assert_false(gs.has_flag(&"met_boss"), "New Game wipes all story flags")
	gs.free()

func test_dialogue_choice_flag_fields_default_inert() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.required_flag, &"", "no flag gate by default")
	assert_eq(c.required_flag_value, "true", "the default expected value is 'true' (matches set_flag's default)")
	c = null
