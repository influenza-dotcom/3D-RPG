extends GutTest

## Manual save / quicksave / named slots (ML-1): the thin wrappers layered over the path-parameterized
## save_to_disk(path) / load_from_disk(path). Tested on FRESH off-tree GameState instances (load().new(), never
## the autoload) and a TEMP path — so a test run touches neither the real GameState nor the user's actual
## user://quicksave.cfg / save_slot_*.cfg. We drive the PRIVATE path-explicit seams (_capture_and_write /
## _load_and_reload) with the temp path: the public quicksave()/save_to_slot()/quickload()/load_from_slot()
## just feed those the fixed real paths, so the only extra surface they add is path selection (slot_path) + the
## off-tree guard, both covered below. The in-tree scene-reload itself is playtested.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const TMP_SAVE := "user://test_saveslots_tmp.cfg"
const TMP_MISSING := "user://test_saveslots_definitely_absent.cfg"


## A minimal in-tree stand-in for the Player: just the duck-typed surface GameState.capture() reads. We can't
## add the real Player to the tree in a unit test (its _ready spins up weapon.tscn / nav / audio), so this gives
## capture() / set_respawn() something in-tree to read without that machinery.
class StubPlayer extends Node3D:
	var money: float = 0.0
	var inventory = null
	var _sheet := CharacterStats.new()
	func stats_or_default() -> CharacterStats: return _sheet
	func unlocked_list() -> Array: return []


func after_each() -> void:
	for f in [TMP_SAVE, TMP_MISSING]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_slot_path_formats_and_clamps() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_eq(gs.slot_path(1), "user://save_slot_1.cfg", "slot 1 -> its file")
	assert_eq(gs.slot_path(gs.SLOT_COUNT), "user://save_slot_%d.cfg" % gs.SLOT_COUNT, "the last slot -> its file")
	assert_eq(gs.slot_path(0), "user://save_slot_1.cfg", "an under-range slot clamps to 1 (can't escape user://)")
	assert_eq(gs.slot_path(999), "user://save_slot_%d.cfg" % gs.SLOT_COUNT, "an over-range slot clamps to the last")
	gs.free()


func test_capture_and_write_intree_stamps_respawn_and_round_trips() -> void:
	# The core of quicksave/save_to_slot: with an IN-TREE player it stamps the respawn point at the player's
	# current spot (so a load returns you exactly there), captures the run, and writes the file.
	var gs = load(GAMESTATE_PATH).new()  # off-tree is fine — _capture_and_write only checks the PLAYER's tree state
	var stub := StubPlayer.new()
	stub.money = 175.0
	add_child_autofree(stub)  # global_position requires being in-tree — add first, THEN set the transform
	stub.global_position = Vector3(9.0, 0.0, -4.0)
	stub.rotation.y = 1.25
	assert_true(gs._capture_and_write(stub, TMP_SAVE), "an in-tree capture+write succeeds")
	assert_true(FileAccess.file_exists(TMP_SAVE), "the snapshot was written to disk")
	assert_true(gs.has_respawn, "a quick/slot save stamps a respawn point")
	assert_almost_eq(gs.respawn_position, Vector3(9.0, 0.0, -4.0), Vector3(0.01, 0.01, 0.01), "stamped at the player's spot")
	assert_almost_eq(gs.respawn_yaw, 1.25, 0.001, "stamped at the player's facing")
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the snapshot loads back")
	assert_eq(gs2.money, 175.0, "the captured wallet round-trips")
	assert_almost_eq(gs2.respawn_position, Vector3(9.0, 0.0, -4.0), Vector3(0.01, 0.01, 0.01), "the stamped respawn round-trips")
	gs.free()
	gs2.free()


func test_capture_and_write_offtree_player_is_noop() -> void:
	# The guard that stops a test run (or a bare player) clobbering a save: an OFF-TREE player writes nothing.
	var gs = load(GAMESTATE_PATH).new()
	var stub := StubPlayer.new()  # NOT added to the tree
	stub.money = 50.0
	assert_false(stub.is_inside_tree(), "precondition: the stub player is off-tree")
	assert_false(gs._capture_and_write(stub, TMP_SAVE), "off-tree capture+write is a no-op")
	assert_false(FileAccess.file_exists(TMP_SAVE), "...so nothing was written (no clobber)")
	stub.free()
	gs.free()


func test_public_quicksave_and_slot_save_guard_offtree() -> void:
	# The public wrappers inherit the same off-tree guard (they delegate to _capture_and_write).
	var gs = load(GAMESTATE_PATH).new()
	var stub := StubPlayer.new()
	assert_false(gs.quicksave(stub), "quicksave on an off-tree player is a no-op")
	assert_false(gs.save_to_slot(stub, 1), "save_to_slot on an off-tree player is a no-op")
	stub.free()
	gs.free()


func test_load_and_reload_missing_file_returns_false() -> void:
	# quickload / load_from_slot guard: a path with no file fails and does not reload.
	var gs = load(GAMESTATE_PATH).new()
	assert_false(FileAccess.file_exists(TMP_MISSING), "precondition: the temp path has no file")
	assert_false(gs._load_and_reload(TMP_MISSING), "loading a missing snapshot fails (no reload)")
	gs.free()


func test_load_and_reload_offtree_loads_without_reload() -> void:
	# Off-tree (no SceneTree) _load_and_reload still LOADS the profile (loaded=true so a future Player applies it)
	# but skips the scene reload — proving the load and the reload are cleanly separable.
	var src = load(GAMESTATE_PATH).new()
	src.money = 412.0
	src.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_false(gs2.is_inside_tree(), "precondition: gs2 is off-tree (no reload possible)")
	assert_true(gs2._load_and_reload(TMP_SAVE), "the snapshot loads even off-tree")
	assert_true(gs2.loaded, "a successful load marks the profile present (the Player will re-apply it)")
	assert_eq(gs2.money, 412.0, "the loaded profile carries the saved wallet")
	src.free()
	gs2.free()


func test_input_actions_exist() -> void:
	# F5 / F9 are wired in project.godot so the Player's poll can read them.
	assert_true(InputMap.has_action(&"Quicksave"), "the Quicksave action (F5) is registered")
	assert_true(InputMap.has_action(&"Quickload"), "the Quickload action (F9) is registered")
