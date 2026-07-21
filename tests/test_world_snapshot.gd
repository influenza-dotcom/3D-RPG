extends GutTest

const WorldSnapshot = preload("res://scripts/world/world_snapshot.gd")

## WorldSnapshot — the exact-snapshot save tier (Phase 1: authored-NPC death + position). Covers the serializer
## (capture/apply/round-trip) with lightweight in-tree stubs (per CLAUDE.md we never run NPC._ready in a unit test),
## and the GameState save/load glue on a BARE instance (never the real autoload, so a test run can't clobber the
## user's real save — save/load target throwaway user:// temp files).

## Duck-typed NPC stand-in: enough surface (snapshot_key / is_alive / hp / global_position) for capture+apply to
## drive it. In-tree (add_child_autofree) so global_position doesn't trip GUT's tracked-error guard.
class NpcStub extends Node3D:
	var key: String = ""
	var alive: bool = true
	var hp: float = 100.0
	var restored: bool = false
	var last_pos: Vector3 = Vector3.ZERO
	var last_yaw: float = 0.0
	var last_hp: float = 0.0
	func snapshot_key() -> String:
		return key
	func is_alive() -> bool:
		return alive
	func restore_snapshot_state(pos: Vector3, yaw: float, restored_hp: float) -> void:
		restored = true
		last_pos = pos
		last_yaw = yaw
		last_hp = restored_hp


const TMP_A := "user://__test_ws_a.cfg"
const TMP_B := "user://__test_ws_b.cfg"

func _cleanup(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func after_each() -> void:
	_cleanup(TMP_A)
	_cleanup(TMP_B)

# --- serializer round-trip -----------------------------------------------------------------------------------
func test_to_dict_from_dict_round_trip_preserves_vector3() -> void:
	var src := {
		"res://lvl.tres": {
			"authored_npcs": {"id:a": {"alive": true, "pos": Vector3(1, 2, 3), "yaw": 0.5, "hp": 42.0}},
			"dead_authored": ["id:b"],
		}
	}
	var snap := WorldSnapshot.new()
	snap.from_dict(src)
	var out := snap.to_dict()
	assert_eq(out, src, "the snapshot round-trips its nested Dictionary (incl. Vector3) unchanged")
	# and it's a DEEP copy — mutating the export must not reach back into the snapshot
	out["res://lvl.tres"]["dead_authored"].append("id:c")
	assert_false("id:c" in snap.to_dict()["res://lvl.tres"]["dead_authored"], "to_dict is a deep copy, not a live handle")
	snap = null

func test_from_dict_degrades_junk_to_empty() -> void:
	var snap := WorldSnapshot.new()
	snap.from_dict("not a dictionary")
	assert_true(snap.is_empty(), "junk-typed load input degrades to an empty snapshot rather than crashing")
	snap = null

func test_is_empty_and_dead_map() -> void:
	var snap := WorldSnapshot.new()
	assert_true(snap.is_empty(), "a fresh snapshot is empty")
	snap.from_dict({"res://a.tres": {"authored_npcs": {}, "dead_authored": ["id:x"]}})
	assert_false(snap.is_empty(), "a recorded death makes it non-empty")
	var dm := snap.dead_map()
	assert_true(dm.has("res://a.tres") and dm["res://a.tres"].has("id:x"), "dead_map exposes { level -> { key: true } }")
	snap = null

# --- capture -------------------------------------------------------------------------------------------------
func test_capture_sorts_live_alive_and_dead() -> void:
	var live := NpcStub.new()
	live.key = "id:alive"
	add_child_autofree(live)
	live.add_to_group(Groups.NPC)
	live.global_position = Vector3(4, 0, 6)
	live.rotation.y = 1.25
	live.hp = 37.0
	var dying := NpcStub.new()  # _dead but still in-tree (a save mid death-freeze) -> counts as dead
	dying.key = "id:dying"
	dying.alive = false
	add_child_autofree(dying)
	dying.add_to_group(Groups.NPC)

	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://lvl.tres", {"id:already_dead": true})  # passed-in ledger of already-freed deaths
	var bucket: Dictionary = snap.to_dict()["res://lvl.tres"]

	assert_true(bucket["authored_npcs"].has("id:alive"), "a live NPC is captured into authored_npcs")
	assert_eq(bucket["authored_npcs"]["id:alive"]["pos"], Vector3(4, 0, 6), "captured position")
	assert_eq(bucket["authored_npcs"]["id:alive"]["hp"], 37.0, "captured hp")
	var dead: Array = bucket["dead_authored"]
	assert_true("id:dying" in dead, "an in-tree _dead NPC (mid-freeze) is captured as dead")
	assert_true("id:already_dead" in dead, "the passed-in death ledger is folded into dead_authored")
	assert_false("id:alive" in dead, "a live NPC is NOT marked dead")
	snap = null

# --- apply ---------------------------------------------------------------------------------------------------
func test_apply_restores_live_and_frees_dead() -> void:
	var live := NpcStub.new()
	live.key = "id:alive"
	add_child_autofree(live)
	live.add_to_group(Groups.NPC)
	var dead := NpcStub.new()
	dead.key = "id:dead"
	add_child_autofree(dead)
	dead.add_to_group(Groups.NPC)

	var snap := WorldSnapshot.new()
	snap.from_dict({
		"res://lvl.tres": {
			"authored_npcs": {"id:alive": {"alive": true, "pos": Vector3(9, 1, 2), "yaw": 2.0, "hp": 15.0}},
			"dead_authored": ["id:dead"],
		}
	})
	snap.apply(get_tree(), "res://lvl.tres")

	assert_true(live.restored, "a live authored NPC gets restore_snapshot_state")
	assert_eq(live.last_pos, Vector3(9, 1, 2), "restored to its saved position")
	assert_eq(live.last_hp, 15.0, "restored to its saved hp")
	assert_true(dead.is_queued_for_deletion(), "a dead authored NPC is freed (suppressed) on apply")
	snap = null

func test_apply_ignores_unknown_level() -> void:
	var stub := NpcStub.new()
	stub.key = "id:alive"
	add_child_autofree(stub)
	stub.add_to_group(Groups.NPC)
	var snap := WorldSnapshot.new()
	snap.from_dict({"res://other.tres": {"authored_npcs": {"id:alive": {"pos": Vector3.ZERO, "yaw": 0.0, "hp": 1.0}}, "dead_authored": []}})
	snap.apply(get_tree(), "res://lvl.tres")  # different level -> no bucket
	assert_false(stub.restored, "a snapshot for a different level leaves this level's NPCs untouched")
	assert_false(stub.is_queued_for_deletion(), "and frees nothing")
	snap = null

# --- GameState glue (bare instance, temp files) --------------------------------------------------------------
func _bare_gs() -> Node:
	return load("res://managers/GameState.gd").new()

func test_manual_save_writes_section_autosave_omits_it() -> void:
	var gs := _bare_gs()
	# Manual path populates world_snapshot -> [world_snapshot] is written.
	gs.world_snapshot = WorldSnapshot.new()
	gs.world_snapshot.from_dict({"res://lvl.tres": {"authored_npcs": {}, "dead_authored": ["id:x"]}})
	assert_eq(gs.save_to_disk(TMP_A), OK, "the manual save writes")
	var cfg_a := ConfigFile.new()
	cfg_a.load(TMP_A)
	assert_true(cfg_a.has_section_key("world_snapshot", "data"), "a manual (snapshot-bearing) save writes [world_snapshot]")

	# Lean path leaves world_snapshot null -> the section is ABSENT (the load-bearing 'profile != snapshot' invariant).
	gs.world_snapshot = null
	assert_eq(gs.save_to_disk(TMP_B), OK, "the lean save writes")
	var cfg_b := ConfigFile.new()
	cfg_b.load(TMP_B)
	assert_false(cfg_b.has_section("world_snapshot"), "a lean (profile-only) save has NO [world_snapshot] section")
	gs.free()

func test_load_restores_snapshot_and_pending_is_one_shot() -> void:
	var writer := _bare_gs()
	writer.world_snapshot = WorldSnapshot.new()
	writer.world_snapshot.from_dict({"res://lvl.tres": {"authored_npcs": {}, "dead_authored": ["id:z"]}})
	writer.save_to_disk(TMP_A)
	writer.free()

	var gs := _bare_gs()
	assert_true(gs.load_from_disk(TMP_A), "the temp save loads")
	assert_not_null(gs.world_snapshot, "a load with a [world_snapshot] section rebuilds the snapshot in memory")
	assert_true(gs.consume_world_snapshot(), "the pending flag is set once by the load")
	assert_false(gs.consume_world_snapshot(), "and is consumed exactly once (one-shot, like the clock-apply flag)")
	# the live death ledger is reloaded from the snapshot so post-load deaths accumulate correctly
	assert_true(gs._dead_authored.has("res://lvl.tres"), "the per-level death ledger is reloaded from the snapshot")
	gs.free()

func test_profile_only_load_has_no_snapshot() -> void:
	var writer := _bare_gs()
	writer.world_snapshot = null  # lean
	writer.save_to_disk(TMP_A)
	writer.free()

	var gs := _bare_gs()
	gs.load_from_disk(TMP_A)
	assert_null(gs.world_snapshot, "a profile-only load leaves world_snapshot null")
	assert_false(gs.consume_world_snapshot(), "and nothing pending — Continue never applies a snapshot")
	gs.free()

func test_reset_for_new_game_clears_snapshot_state() -> void:
	var gs := _bare_gs()
	gs.world_snapshot = WorldSnapshot.new()
	gs._world_snapshot_pending = true
	gs.record_npc_death("res://lvl.tres", "id:x")
	gs.reset_for_new_game()
	assert_null(gs.world_snapshot, "New Game drops any in-memory snapshot")
	assert_false(gs.consume_world_snapshot(), "New Game clears the pending flag")
	assert_true(gs._dead_authored.is_empty(), "New Game forgets the death ledger")
	gs.free()

func test_record_npc_death_ignores_blank_key() -> void:
	var gs := _bare_gs()
	gs.record_npc_death("res://lvl.tres", "")
	assert_true(gs._dead_authored.is_empty(), "a blank key is never recorded")
	gs.record_npc_death("res://lvl.tres", "id:real")
	assert_true(gs._dead_authored["res://lvl.tres"].has("id:real"), "a real death is recorded under its level")
	gs.free()
