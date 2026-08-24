extends GutTest

## The persistent named bookmarks behind the console's `mark <name>` / `goto <name>` / `marks` — the PURE file
## half only (DebugActionsPlayer.mark_key / marks_read / marks_write / marks_erase / marks_levels), driven on a
## scratch ConfigFile saved to user://test_debug_marks.cfg and deleted after every test. No player, no
## GameState, no `run()`: the commands themselves move a live Player and read GameState.current_level_path, and
## the statics take the ConfigFile + level section EXPLICITLY for exactly this reason. The real MARKS_PATH is
## never written here — a TRIPWIRE pins that (md5 before/after), because a static that silently reached for the
## real path would delete a developer's bookmarks the next time the suite ran.

# Preloaded by PATH into an untyped const — the class_name may not be in the editor cache yet (the cascade
# debug_overlay.gd:9-11 documents). Same idiom as tests/test_debug_commands.gd:14.
const PlayerActions := preload("res://scripts/components/debug_actions_player.gd")

const SCRATCH := "user://test_debug_marks.cfg"
## Level identities as the commands see them: GameState.current_level_path is the LevelData res:// path — full of
## `:` and `/` and `.`, which is the point of using them here (a ConfigFile section must survive them verbatim).
const LEVEL_A := "res://resources/levels/alive.tres"
const LEVEL_B := "res://resources/levels/TestLevel.tres"

var _real_before := "missing"


func before_each() -> void:
	_real_before = _md5_or_missing(String(PlayerActions.MARKS_PATH))
	_remove_scratch()


func after_each() -> void:
	_remove_scratch()
	# THE TRIPWIRE: nothing in this file may touch the developer's real bookmarks.
	assert_eq(_md5_or_missing(String(PlayerActions.MARKS_PATH)), _real_before,
		"the real %s must be untouched by this test" % String(PlayerActions.MARKS_PATH))


func _remove_scratch() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


func _md5_or_missing(path: String) -> String:
	return FileAccess.get_md5(path) if FileAccess.file_exists(path) else "missing"


## Save `cfg` to the scratch path and read it back into a FRESH ConfigFile — the only honest round trip.
func _round_trip(cfg: ConfigFile) -> ConfigFile:
	assert_eq(cfg.save(SCRATCH), OK, "the scratch ConfigFile must save")
	var back := ConfigFile.new()
	assert_eq(back.load(SCRATCH), OK, "the scratch ConfigFile must load back")
	return back


# --- the constants the commands ride on -------------------------------------------------------------------

func test_marks_path_is_a_user_file_separate_from_the_scratch_and_the_saves() -> void:
	var path := String(PlayerActions.MARKS_PATH)
	assert_true(path.begins_with("user://"), "bookmarks live under user:// (never a project file), got %s" % path)
	assert_ne(path, SCRATCH, "the scratch path must never be the real one")
	assert_string_contains(path, "debug_marks")
	assert_false(path.contains("gamestate") or path.contains("save"),
		"the marks file must never collide with a save path (the Saves tab / recovery ladder must not see it): %s" % path)


func test_value_keys_are_the_documented_four() -> void:
	var keys: PackedStringArray = PlayerActions.MARKS_VALUE_KEYS
	assert_eq(keys, PackedStringArray(["x", "y", "z", "yaw"]), "the on-disk mark shape is {x, y, z, yaw}")


# --- mark_key ---------------------------------------------------------------------------------------------

func test_mark_key_normalises_case_padding_and_spaces() -> void:
	assert_eq(PlayerActions.mark_key("Roof"), "roof", "lowercased")
	assert_eq(PlayerActions.mark_key("  roof  "), "roof", "trimmed")
	assert_eq(PlayerActions.mark_key("My Spot"), "my_spot", "inner spaces become underscores")
	assert_eq(PlayerActions.mark_key("  Back Alley Door "), "back_alley_door", "all three at once")
	assert_eq(PlayerActions.mark_key("already_fine"), "already_fine", "a clean key is unchanged")
	assert_eq(PlayerActions.mark_key(""), "", "blank stays blank (the commands treat it as no name)")
	assert_eq(PlayerActions.mark_key("   "), "", "whitespace-only is blank too")


# --- write / read round trip ------------------------------------------------------------------------------

## Dyadic values (-29.5, 4.25, -15.125, 1.5) ON PURPOSE: they are exact in float32 AND print in few digits, so
## the assertion pins "the file round-trips a mark exactly" independent of how many digits the engine's text
## writer chooses to emit for a float (VariantWriter has historically used %lg = 6 significant digits — a value
## like 123.4567 would come back 123.457, so a pin on an arbitrary float would test the writer, not the helpers).
func test_write_then_read_round_trips_pos_and_yaw_exactly() -> void:
	var cfg := ConfigFile.new()
	var pos := Vector3(-29.5, 4.25, -15.125)
	var yaw := 1.5
	PlayerActions.marks_write(cfg, LEVEL_A, "spot", pos, yaw)
	var back := _round_trip(cfg)
	var here: Dictionary = PlayerActions.marks_read(back, LEVEL_A)
	assert_eq(here.size(), 1, "one mark filed under the level")
	assert_true(here.has("spot"), "keyed by the normalised name")
	var m: Dictionary = here["spot"]
	assert_eq(m[&"pos"], pos, "position round-trips exactly")
	assert_eq(float(m[&"yaw"]), yaw, "yaw round-trips exactly")
	assert_true(m[&"pos"] is Vector3, "marks_read hands back a Vector3, not the raw dict")
	back = null
	cfg = null


## The ON-DISK shape is pinned separately from the read helper: a developer hand-edits this file, so the value
## must stay a plain {x, y, z, yaw} of numbers under the level's res:// path as the section.
func test_on_disk_shape_is_a_dictionary_of_four_floats_under_the_level_section() -> void:
	var cfg := ConfigFile.new()
	PlayerActions.marks_write(cfg, LEVEL_A, "spot", Vector3(1.0, 2.0, 3.0), 0.5)
	var back := _round_trip(cfg)
	assert_true(back.has_section(LEVEL_A), "the section IS the level identity, verbatim (res:// path and all)")
	assert_true(back.has_section_key(LEVEL_A, "spot"), "the key is the mark name")
	var raw = back.get_value(LEVEL_A, "spot")
	assert_true(raw is Dictionary, "the value is a Dictionary")
	var d: Dictionary = raw
	for k in PlayerActions.MARKS_VALUE_KEYS:
		assert_true(d.has(k), "value carries \"%s\"" % k)
	assert_eq(d.size(), 4, "and nothing else")
	assert_eq(float(d["x"]), 1.0, "x")
	assert_eq(float(d["y"]), 2.0, "y")
	assert_eq(float(d["z"]), 3.0, "z")
	assert_eq(float(d["yaw"]), 0.5, "yaw")
	back = null
	cfg = null


func test_write_normalises_the_name_and_overwrites_the_same_key() -> void:
	var cfg := ConfigFile.new()
	PlayerActions.marks_write(cfg, LEVEL_A, "  My Spot ", Vector3(1.0, 1.0, 1.0), 0.0)
	PlayerActions.marks_write(cfg, LEVEL_A, "my_spot", Vector3(2.0, 2.0, 2.0), 0.25)
	var here: Dictionary = PlayerActions.marks_read(cfg, LEVEL_A)
	assert_eq(here.size(), 1, "\"  My Spot \" and \"my_spot\" are the SAME mark")
	var m: Dictionary = here["my_spot"]
	assert_eq(m[&"pos"], Vector3(2.0, 2.0, 2.0), "the later write wins")
	assert_eq(float(m[&"yaw"]), 0.25, "yaw too")
	cfg = null


func test_write_refuses_a_blank_level_or_name() -> void:
	var cfg := ConfigFile.new()
	PlayerActions.marks_write(cfg, "", "spot", Vector3.ZERO, 0.0)
	PlayerActions.marks_write(cfg, LEVEL_A, "   ", Vector3.ZERO, 0.0)
	assert_true(cfg.get_sections().is_empty(), "a blank level or a blank name files nothing (the commands refuse earlier, this is the backstop)")
	cfg = null


func test_read_of_an_unknown_level_is_empty_and_read_skips_malformed_rows() -> void:
	var cfg := ConfigFile.new()
	assert_eq(PlayerActions.marks_read(cfg, LEVEL_A).size(), 0, "no section -> empty, never an error")
	assert_eq(PlayerActions.marks_read(cfg, "").size(), 0, "blank level -> empty")
	PlayerActions.marks_write(cfg, LEVEL_A, "good", Vector3(1.0, 2.0, 3.0), 0.0)
	# Hand-edit casualties: a bare number, and a dict missing yaw.
	cfg.set_value(LEVEL_A, "junk", 42)
	cfg.set_value(LEVEL_A, "half", {"x": 1.0, "y": 2.0, "z": 3.0})
	var back := _round_trip(cfg)
	var here: Dictionary = PlayerActions.marks_read(back, LEVEL_A)
	assert_eq(here.size(), 1, "only the well-formed mark is read")
	assert_true(here.has("good"), "and it is the right one")
	back = null
	cfg = null


# --- erase ------------------------------------------------------------------------------------------------

func test_erase_removes_one_mark_and_reports_whether_it_existed() -> void:
	var cfg := ConfigFile.new()
	PlayerActions.marks_write(cfg, LEVEL_A, "a", Vector3(1.0, 0.0, 0.0), 0.0)
	PlayerActions.marks_write(cfg, LEVEL_A, "b", Vector3(2.0, 0.0, 0.0), 0.0)
	assert_true(PlayerActions.marks_erase(cfg, LEVEL_A, "A "), "erase resolves through mark_key, true when it existed")
	assert_false(PlayerActions.marks_erase(cfg, LEVEL_A, "a"), "a second erase of the same name is false")
	assert_false(PlayerActions.marks_erase(cfg, LEVEL_B, "b"), "erasing under the WRONG level is false and touches nothing")
	var back := _round_trip(cfg)
	var here: Dictionary = PlayerActions.marks_read(back, LEVEL_A)
	assert_eq(here.size(), 1, "one mark left")
	assert_true(here.has("b"), "the other one survived")
	back = null
	cfg = null


func test_erasing_the_last_mark_drops_the_level_section() -> void:
	var cfg := ConfigFile.new()
	PlayerActions.marks_write(cfg, LEVEL_A, "only", Vector3.ONE, 0.0)
	assert_eq(PlayerActions.marks_levels(cfg), PackedStringArray([LEVEL_A]), "the level is listed while it has a mark")
	assert_true(PlayerActions.marks_erase(cfg, LEVEL_A, "only"), "erased")
	assert_false(cfg.has_section(LEVEL_A), "the empty section is dropped with it")
	assert_true(PlayerActions.marks_levels(cfg).is_empty(), "so `marks` never counts a ghost level")
	cfg = null


# --- levels listing ---------------------------------------------------------------------------------------

func test_levels_lists_every_level_with_marks_sorted() -> void:
	var cfg := ConfigFile.new()
	assert_true(PlayerActions.marks_levels(cfg).is_empty(), "empty file -> no levels")
	PlayerActions.marks_write(cfg, LEVEL_B, "b1", Vector3.ZERO, 0.0)
	PlayerActions.marks_write(cfg, LEVEL_A, "a1", Vector3.ZERO, 0.0)
	PlayerActions.marks_write(cfg, LEVEL_A, "a2", Vector3.ZERO, 0.0)
	var back := _round_trip(cfg)
	var levels: PackedStringArray = PlayerActions.marks_levels(back)
	assert_eq(levels.size(), 2, "two levels have marks")
	assert_eq(levels[0], LEVEL_B, "sorted (String order: 'T' < 'a')")
	assert_eq(levels[1], LEVEL_A, "sorted")
	assert_eq(PlayerActions.marks_read(back, LEVEL_A).size(), 2, "level A's marks are its own")
	assert_eq(PlayerActions.marks_read(back, LEVEL_B).size(), 1, "level B's marks are its own")
	back = null
	cfg = null


func test_null_configfile_is_tolerated_by_every_helper() -> void:
	# The commands always hand a real ConfigFile; the guard is what keeps a future caller's null from crashing
	# the console instead of printing one honest line.
	assert_eq(PlayerActions.marks_read(null, LEVEL_A).size(), 0, "read")
	assert_false(PlayerActions.marks_erase(null, LEVEL_A, "x"), "erase")
	assert_true(PlayerActions.marks_levels(null).is_empty(), "levels")
	PlayerActions.marks_write(null, LEVEL_A, "x", Vector3.ZERO, 0.0)  # must not throw
	pass_test("marks_write on a null ConfigFile is a no-op")
