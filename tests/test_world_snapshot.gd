extends GutTest

const WorldSnapshot = preload("res://scripts/world/world_snapshot.gd")

## WorldSnapshot — the per-level WORLD LEDGER every save carries (authored-NPC alive/position/hp, deaths, and every
## authored container's exact contents, for every level visited this run). Covers the serializer (capture/apply/
## round-trip) with lightweight in-tree stubs (per CLAUDE.md we never run NPC._ready in a unit test), the real
## ItemContainer serialize/restore pair off-tree, and the GameState glue on a BARE instance (never the real autoload,
## so a test run can't clobber the user's real save — save/load target throwaway user:// temp files): every save writes
## the ledger, a load rebuilds it, the capture guard for a level whose apply is queued, and the payload-growth bound.
## The in-tree door round-trip across two levels (loot in A, door to B, save, reload, return to A) lives in
## tests/test_level_boot_lifecycle.gd, where a real GameRoot drives load_level.

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


## Duck-typed ItemContainer stand-in for the v2 container walk: snapshot_key/snapshot_contents drive capture,
## restore_snapshot_contents records what apply hands back. A plain Node — the container tier never touches
## transforms.
class ContainerStub extends Node:
	var key: String = ""
	var contents: Dictionary = {"stacks": [], "grid": false}
	var restored_with: Variant = null
	func snapshot_key() -> String:
		return key
	func snapshot_contents() -> Dictionary:
		return contents
	func restore_snapshot_contents(d: Dictionary) -> void:
		restored_with = d


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
	# src is written in the FULL v2 shape (every bucket carries "containers", the container entry carries an
	# explicit "grid") because from_dict normalizes to exactly that — the assert_eq below is an exact-equality pin.
	var src := {
		"res://lvl.tres": {
			"authored_npcs": {"id:a": {"alive": true, "pos": Vector3(1, 2, 3), "yaw": 0.5, "hp": 42.0}},
			"dead_authored": ["id:b"],
			"containers": {"id:crate": {"stacks": [{"id": "ammo", "count": 3, "x": 1, "y": 2, "w": 1, "h": 1}], "grid": true, "locked": true}},
		}
	}
	var snap := WorldSnapshot.new()
	snap.from_dict(src)
	var out := snap.to_dict()
	assert_eq(out, src, "the snapshot round-trips its nested Dictionary (incl. Vector3 + v2 containers) unchanged")
	# and it's a DEEP copy — mutating the export must not reach back into the snapshot
	out["res://lvl.tres"]["dead_authored"].append("id:c")
	assert_false("id:c" in snap.to_dict()["res://lvl.tres"]["dead_authored"], "to_dict is a deep copy, not a live handle")
	snap = null

func test_from_dict_degrades_junk_to_empty() -> void:
	var snap := WorldSnapshot.new()
	snap.from_dict("not a dictionary")
	assert_true(snap.is_empty(), "junk-typed load input degrades to an empty snapshot rather than crashing")
	snap = null

func test_from_dict_shape_filters_corrupt_inner_types() -> void:
	# A hand-edited / corrupt save can hold ANY Variant under a key. from_dict must coerce each bucket to the exact
	# shapes dead_map()/apply() require, so junk degrades instead of raising a runtime error DEEP inside a load that has
	# already overwritten money/stats in memory (which would strand the run on a half-loaded profile). The prior junk
	# test only feeds a TOP-level non-Dictionary, which never reaches the inner loop — this pins the inner coercions.
	var snap := WorldSnapshot.new()
	snap.from_dict({
		"res://lvl.tres": {
			"dead_authored": 7,  # not an Array (a non-iterable would hard-error dead_map() without the filter)
			"authored_npcs": {
				"id:junk": "not a dict",                                  # non-Dictionary entry -> dropped
				"id:ok": {"pos": "not a vector", "yaw": "nope", "hp": 15.0},  # junk pos/yaw -> defaulted, valid hp kept
			},
		},
		"res://bad.tres": "not a dictionary bucket",  # whole bucket junk -> dropped
	})
	var dm := snap.dead_map()  # must NOT raise on the non-Array dead_authored
	assert_false(dm.has("res://lvl.tres"), "a non-Array dead_authored degrades to no dead keys (no crash)")
	var bucket: Dictionary = snap.to_dict().get("res://lvl.tres", {})
	assert_false((bucket.get("authored_npcs", {}) as Dictionary).has("id:junk"), "a non-Dictionary authored_npcs entry is dropped")
	var ok: Dictionary = bucket["authored_npcs"]["id:ok"]
	assert_eq(ok["pos"], Vector3.ZERO, "a junk pos falls back to Vector3.ZERO")
	assert_eq(ok["yaw"], 0.0, "a junk yaw falls back to 0.0")
	assert_eq(ok["hp"], 15.0, "a valid hp survives the filter")
	assert_false(snap.to_dict().has("res://bad.tres"), "a non-Dictionary bucket is dropped entirely")
	snap.apply(get_tree(), "res://lvl.tres")  # sanitized shapes -> apply() runs without a runtime error (GUT fails on engine errors)
	assert_false(snap.is_empty(), "the sanitized snapshot still holds the one coerced entry")
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

func test_capture_live_wins_over_a_stale_dead_ledger() -> void:
	# LIVE-WINS remediation: the death ledger only ever GROWS, but a killed authored NPC comes back ALIVE when its level
	# re-instantiates (door A->B->A, or a RELOAD_CHECKPOINT_FRESH death). If capture sees it alive in the tree now, its
	# OWN key must be erased from the incoming dead ledger — else apply() (which frees dead-first) would delete an NPC
	# standing in front of the player and poison every later quicksave. The other capture test never puts the live NPC's
	# own key in the ledger, so this is the case that actually exercises world_snapshot.gd's dead.erase(key).
	var live := NpcStub.new()
	live.key = "id:back_alive"
	add_child_autofree(live)
	live.add_to_group(Groups.NPC)
	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://lvl.tres", {"id:back_alive": true})  # its OWN key is (stale) in the dead ledger
	var bucket: Dictionary = snap.to_dict()["res://lvl.tres"]
	assert_true((bucket["authored_npcs"] as Dictionary).has("id:back_alive"), "the re-instantiated NPC is captured LIVE")
	assert_false("id:back_alive" in bucket["dead_authored"], "and its stale dead-ledger key is erased — live wins over the ledger")
	snap = null

# --- Phase 2: cross-level death persistence ------------------------------------------------------------------
func test_fold_dead_ledger_persists_other_levels() -> void:
	# A quicksave folds EVERY visited level's death ledger into the snapshot, not just the level saved IN, so a quickload's
	# dead_map restores cross-level kills (you door back into a cleared level and it stays cleared). Other levels aren't in
	# the tree, so only their dead keys are known.
	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://a.tres", {"id:a_dead": true})  # current level A (no live NPCs in this test)
	snap.fold_dead_ledger({
		"res://a.tres": {"id:a_dead": true},                       # current level — fold SKIPS it (capture owns it)
		"res://b.tres": {"id:b_dead": true},
		"res://c.tres": {"id:c1": true, "id:c2": true},
	}, "res://a.tres")
	var dm := snap.dead_map()
	assert_true(dm.has("res://a.tres") and dm["res://a.tres"].has("id:a_dead"), "the saved-in level keeps its dead (from capture)")
	assert_true(dm.has("res://b.tres") and dm["res://b.tres"].has("id:b_dead"), "another visited level's dead persist")
	assert_true(dm.has("res://c.tres") and dm["res://c.tres"].has("id:c1") and dm["res://c.tres"].has("id:c2"), "all of a third level's keys persist")
	snap = null

func test_fold_dead_ledger_does_not_clobber_current_level_live() -> void:
	var live := NpcStub.new()
	live.key = "id:live"
	add_child_autofree(live)
	live.add_to_group(Groups.NPC)
	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://a.tres", {})  # captures the live NPC into level A
	snap.fold_dead_ledger({"res://a.tres": {"id:x": true}, "res://b.tres": {"id:b": true}}, "res://a.tres")
	assert_true((snap.to_dict()["res://a.tres"]["authored_npcs"] as Dictionary).has("id:live"), "fold skips the current level, so its captured live NPC survives")
	assert_true("res://b.tres" in snap.to_dict(), "another level's dead-only bucket is added alongside")
	snap = null

func test_suppress_dead_authored_frees_only_ledger_keys() -> void:
	# The door A->B->A / load path: the level re-instantiates fresh with ALL NPCs alive; suppress frees the ones already
	# killed (key in the ledger) so they STAY dead, and leaves the rest.
	var gs := _bare_gs()
	var alive := NpcStub.new()
	alive.key = "id:alive"
	add_child_autofree(alive)
	alive.add_to_group(Groups.NPC)
	var slain := NpcStub.new()
	slain.key = "id:slain"
	add_child_autofree(slain)
	slain.add_to_group(Groups.NPC)
	gs.record_npc_death("res://a.tres", "id:slain")
	gs.suppress_dead_authored(get_tree(), "res://a.tres")
	assert_true(slain.is_queued_for_deletion(), "an NPC in the death ledger is freed (stays dead) on the level re-load")
	assert_false(alive.is_queued_for_deletion(), "an NPC NOT in the ledger is left alive")
	gs.free()

# --- v2: container contents ----------------------------------------------------------------------------------
func test_capture_records_container_contents() -> void:
	var crate := ContainerStub.new()
	crate.key = "id:crate"
	crate.contents = {"stacks": [{"id": "ammo", "count": 7}], "grid": true, "locked": false}
	add_child_autofree(crate)
	crate.add_to_group(Groups.CONTAINERS)
	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://lvl.tres")
	var conts: Dictionary = snap.to_dict()["res://lvl.tres"]["containers"]
	assert_true(conts.has("id:crate"), "an authored container in Groups.CONTAINERS is captured by snapshot_key")
	assert_eq(conts["id:crate"], crate.contents, "capture stores the container's snapshot_contents() verbatim")
	snap = null

func test_capture_skips_runtime_spawned_containers() -> void:
	# A runtime-spawned container has no authored save_id, so its key falls back to a generated "@Class@N"
	# node_path — no stable identity to re-match on reload. Mirror of the NPC dynamic-spawn skip.
	var bag := ContainerStub.new()
	bag.key = "res://lvl.tres|/root/Level/@ItemContainer@33"
	add_child_autofree(bag)
	bag.add_to_group(Groups.CONTAINERS)
	var blank := ContainerStub.new()  # a blank key (off-tree edge) is skipped too, like the NPC walk
	blank.key = ""
	add_child_autofree(blank)
	blank.add_to_group(Groups.CONTAINERS)
	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://lvl.tres")
	assert_true((snap.to_dict()["res://lvl.tres"]["containers"] as Dictionary).is_empty(),
		"an @-pathed (runtime-spawned) or blank-keyed container is never captured")
	snap = null

func test_apply_hands_container_its_entry() -> void:
	var crate := ContainerStub.new()
	crate.key = "id:crate"
	add_child_autofree(crate)
	crate.add_to_group(Groups.CONTAINERS)
	var other := ContainerStub.new()  # not in the snapshot -> left alone (keeps its authored seed)
	other.key = "id:other"
	add_child_autofree(other)
	other.add_to_group(Groups.CONTAINERS)
	var entry := {"stacks": [{"id": "ammo", "count": 2, "x": 0, "y": 0, "w": 1, "h": 1}], "grid": true, "locked": true}
	var snap := WorldSnapshot.new()
	snap.from_dict({"res://lvl.tres": {"authored_npcs": {}, "dead_authored": [], "containers": {"id:crate": entry}}})
	snap.apply(get_tree(), "res://lvl.tres")
	assert_eq(crate.restored_with, entry, "a captured container gets its exact entry back on apply")
	assert_null(other.restored_with, "a container absent from the snapshot is left untouched")
	snap = null

func test_from_dict_shape_filters_junk_containers() -> void:
	var snap := WorldSnapshot.new()
	snap.from_dict({
		"res://lvl.tres": {
			"authored_npcs": {},
			"dead_authored": [],
			"containers": {
				"id:junk": "not a dict",                                        # non-Dictionary entry -> dropped
				"id:ok": {"stacks": [7, {"id": "ammo", "count": 1}], "grid": 3, "locked": "nope"},
			},
		}
	})
	var conts: Dictionary = snap.to_dict()["res://lvl.tres"]["containers"]
	assert_false(conts.has("id:junk"), "a non-Dictionary container entry is dropped")
	var ok: Dictionary = conts["id:ok"]
	assert_eq(ok["stacks"], [{"id": "ammo", "count": 1}], "a non-Dictionary stack row is dropped, valid rows kept")
	assert_eq(ok["grid"], false, "a junk-typed grid bit degrades to false (stay lazily unbounded)")
	assert_false(ok.has("locked"), "a junk-typed locked bit is OMITTED — absent means 'don't touch the lock'")
	assert_false(snap.is_empty(), "a container-only snapshot counts as non-empty")
	snap = null

func test_fold_dead_ledger_keeps_captured_containers() -> void:
	var crate := ContainerStub.new()
	crate.key = "id:crate"
	add_child_autofree(crate)
	crate.add_to_group(Groups.CONTAINERS)
	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://a.tres")
	snap.fold_dead_ledger({"res://a.tres": {"id:x": true}, "res://b.tres": {"id:b": true}}, "res://a.tres")
	assert_true((snap.to_dict()["res://a.tres"]["containers"] as Dictionary).has("id:crate"),
		"fold skips the current level, so its captured containers survive alongside its live NPCs")
	# …and the OTHER-level branch (the one the current-level skip above never reaches) must carry an existing
	# bucket's containers through while it merges dead keys. Seed level B with a container the way a loaded
	# snapshot would hold one, then fold MORE dead keys into B and assert the bucket wasn't clobbered — without
	# this, the carry-through line in fold_dead_ledger is never executed by any test.
	var snap_b := WorldSnapshot.new()
	snap_b.from_dict({"res://b.tres": {"authored_npcs": {}, "dead_authored": ["id:old"],
		"containers": {"id:b_crate": {"stacks": [{"id": "ammo_pistol", "count": 2}], "grid": false}}}})
	snap_b.fold_dead_ledger({"res://b.tres": {"id:new": true}}, "res://a.tres")  # B is NOT the current level
	var b_bucket: Dictionary = snap_b.to_dict()["res://b.tres"]
	assert_true((b_bucket["containers"] as Dictionary).has("id:b_crate"),
		"folding dead keys into ANOTHER level's bucket carries its containers through instead of dropping them")
	assert_true("id:new" in b_bucket["dead_authored"] and "id:old" in b_bucket["dead_authored"],
		"…and both the pre-existing and the newly folded dead keys survive the merge")
	snap = null
	snap_b = null

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

func test_every_save_writes_the_ledger_and_an_empty_ledger_writes_no_section() -> void:
	# POLICY (2026-09-16): the ledger is the ordinary save's world state — save_to_disk writes it whenever it holds
	# anything, whichever path called (autosave, quicksave, a slot). An EMPTY ledger (a run that has recorded no world
	# state yet) writes no section, so an untouched run's file stays lean.
	var gs := _bare_gs()
	gs.world_snapshot.from_dict({"res://lvl.tres": {"authored_npcs": {}, "dead_authored": ["id:x"]}})
	assert_eq(gs.save_to_disk(TMP_A), OK, "the save writes")
	var cfg_a := ConfigFile.new()
	cfg_a.load(TMP_A)
	assert_true(cfg_a.has_section_key("world_snapshot", "data"), "a save with world state writes [world_snapshot]")
	var fresh := _bare_gs()
	assert_not_null(fresh.world_snapshot, "the ledger is never null — a fresh GameState starts with an EMPTY one")
	assert_true(fresh.world_snapshot.is_empty(), "...and empty")
	assert_eq(fresh.save_to_disk(TMP_B), OK, "an empty-ledger save writes")
	var cfg_b := ConfigFile.new()
	cfg_b.load(TMP_B)
	assert_false(cfg_b.has_section("world_snapshot"), "an empty ledger writes NO [world_snapshot] section")
	gs.free()
	fresh.free()

func test_load_rebuilds_the_ledger_and_arms_the_booted_level() -> void:
	var writer := _bare_gs()
	writer.world_snapshot.from_dict({"res://lvl.tres": {"authored_npcs": {}, "dead_authored": ["id:z"]}})
	writer.save_to_disk(TMP_A)
	writer.free()

	var gs := _bare_gs()
	assert_true(gs.load_from_disk(TMP_A), "the temp save loads")
	assert_true(gs.world_snapshot.has_level("res://lvl.tres"), "the load rebuilds the ledger in memory")
	assert_true(gs._dead_authored.has("res://lvl.tres"), "the per-level death ledger is reloaded from it")
	# A load applies NOTHING itself — GameRoot applies the booted level's bucket when it spawns the level.
	assert_eq(gs._level_apply_pending, "", "a load arms no capture guard on its own")
	assert_true(gs.begin_level_load("res://lvl.tres"), "a level the ledger knows gets an apply queued (Continue, quickload, a door return)")
	assert_eq(gs._level_apply_pending, "res://lvl.tres", "...and the capture guard is armed for it")
	assert_false(gs.begin_level_load("res://never_visited.tres"), "a level the ledger has no bucket for plays from its authored seed")
	assert_eq(gs._level_apply_pending, "", "...and a superseding load clears the previous guard")
	gs.free()

func test_multi_level_deaths_survive_save_and_load() -> void:
	# A ledger carrying deaths for MULTIPLE levels round-trips through disk, and load restores the FULL cross-level
	# death ledger (via dead_map) so per-level suppression works everywhere, not just the level saved in.
	var writer := _bare_gs()
	writer.world_snapshot.from_dict({
		"res://a.tres": {"authored_npcs": {}, "dead_authored": ["id:a"]},
		"res://b.tres": {"authored_npcs": {}, "dead_authored": ["id:b1", "id:b2"]},
	})
	assert_eq(writer.save_to_disk(TMP_A), OK, "the multi-level ledger save writes")
	writer.free()

	var gs := _bare_gs()
	assert_true(gs.load_from_disk(TMP_A), "the multi-level ledger loads")
	assert_true(gs._dead_authored.has("res://a.tres") and gs._dead_authored["res://a.tres"].has("id:a"), "level A deaths restored")
	assert_true(gs._dead_authored.has("res://b.tres") and gs._dead_authored["res://b.tres"].has("id:b1") and gs._dead_authored["res://b.tres"].has("id:b2"), "level B deaths restored too")
	gs.free()

func test_a_save_written_before_the_ledger_policy_loads_an_empty_ledger() -> void:
	# An AUTOSAVE from before 2026-09-16 never carried [world_snapshot] (only quick/slot saves did). It must load as an
	# EMPTY ledger — every level plays from its authored seed, exactly what that save meant — never a null ledger.
	var writer := _bare_gs()
	writer.save_to_disk(TMP_A)  # empty ledger -> no section: the same file shape an old autosave has
	writer.free()
	var cfg := ConfigFile.new()
	cfg.load(TMP_A)
	assert_false(cfg.has_section("world_snapshot"), "precondition: the file has no ledger section")

	var gs := _bare_gs()
	gs.record_npc_death("res://stale.tres", "id:stale")  # in-memory state from a previous run must not survive the load
	gs.load_from_disk(TMP_A)
	assert_not_null(gs.world_snapshot, "the ledger is an empty object, never null")
	assert_true(gs.world_snapshot.is_empty(), "a ledger-less save loads as an empty ledger")
	assert_true(gs._dead_authored.is_empty(), "and the death ledger is cleared, not carried over from the previous run")
	gs.free()

func test_reset_for_new_game_clears_the_ledger() -> void:
	var gs := _bare_gs()
	gs.world_snapshot.from_dict({"res://lvl.tres": {"authored_npcs": {}, "dead_authored": ["id:x"]}})
	gs.begin_level_load("res://lvl.tres")
	gs.record_npc_death("res://lvl.tres", "id:x")
	gs.reset_for_new_game()
	assert_true(gs.world_snapshot.is_empty(), "New Game forgets every level's bucket")
	assert_eq(gs._level_apply_pending, "", "New Game clears the capture guard")
	assert_true(gs._dead_authored.is_empty(), "New Game forgets the death ledger")
	gs.free()

func test_record_npc_death_ignores_blank_key() -> void:
	var gs := _bare_gs()
	gs.record_npc_death("res://lvl.tres", "")
	assert_true(gs._dead_authored.is_empty(), "a blank key is never recorded")
	gs.record_npc_death("res://lvl.tres", "id:real")
	assert_true(gs._dead_authored["res://lvl.tres"].has("id:real"), "a real death is recorded under its level")
	gs.free()

# --- v2 GameState glue + the real ItemContainer pair ---------------------------------------------------------
func test_container_snapshot_survives_disk_round_trip() -> void:
	var writer := _bare_gs()
	writer.world_snapshot = WorldSnapshot.new()
	writer.world_snapshot.from_dict({"res://lvl.tres": {"authored_npcs": {}, "dead_authored": [],
		"containers": {"id:crate": {"stacks": [{"id": "ammo_pistol", "count": 4}], "grid": false}}}})
	assert_eq(writer.save_to_disk(TMP_A), OK, "the container-bearing snapshot save writes")
	writer.free()
	var gs := _bare_gs()
	assert_true(gs.load_from_disk(TMP_A), "the container-bearing snapshot loads")
	assert_not_null(gs.world_snapshot, "the snapshot rebuilds in memory")
	var conts: Dictionary = gs.world_snapshot.to_dict()["res://lvl.tres"]["containers"]
	assert_eq(conts["id:crate"]["stacks"], [{"id": "ammo_pistol", "count": 4}],
		"a container's stacks survive the ConfigFile round-trip byte-exact")
	gs.free()

func test_v1_snapshot_still_loads_under_v2() -> void:
	# The version gate is RANGED (SNAPSHOT_MIN_COMPAT..SNAPSHOT_VERSION), not exact-match: the shape only grew
	# additively (v2 added "containers"), so a pre-container quicksave must keep its NPC state on update instead
	# of being dropped to profile-only. Hand-write a v1 section the way the v1 build did (no "containers" keys).
	var writer := _bare_gs()
	writer.save_to_disk(TMP_A)  # a lean profile as the base file
	writer.free()
	var cfg := ConfigFile.new()
	cfg.load(TMP_A)
	cfg.set_value("world_snapshot", "version", 1)
	cfg.set_value("world_snapshot", "data", {"res://lvl.tres": {"authored_npcs": {}, "dead_authored": ["id:z"]}})
	cfg.save(TMP_A)
	var gs := _bare_gs()
	assert_true(gs.load_from_disk(TMP_A), "the v1-stamped save loads")
	assert_true(gs.world_snapshot.has_level("res://lvl.tres"), "a v1 snapshot (an old single-level quicksave) still loads as a one-level ledger (additive shape)")
	assert_true(gs._dead_authored.has("res://lvl.tres"), "and its death ledger restores")
	gs.free()

func test_future_snapshot_version_degrades_to_profile_only() -> void:
	# A NEWER stamp than this build understands (a downgraded install) is ignored — profile loads, snapshot dropped.
	var writer := _bare_gs()
	writer.save_to_disk(TMP_A)
	writer.free()
	var cfg := ConfigFile.new()
	cfg.load(TMP_A)
	cfg.set_value("world_snapshot", "version", WorldSnapshot.SNAPSHOT_VERSION + 1)
	cfg.set_value("world_snapshot", "data", {"res://lvl.tres": {"authored_npcs": {}, "dead_authored": ["id:z"]}})
	cfg.save(TMP_A)
	var gs := _bare_gs()
	assert_true(gs.load_from_disk(TMP_A), "the profile still loads under an unknown future snapshot version")
	assert_true(gs.world_snapshot.is_empty(), "the too-new ledger itself is dropped (an empty ledger), never misread")
	gs.free()

func test_item_container_serialize_restore_round_trips_coins_and_layout() -> void:
	# The coin-polarity pin: a CONTAINER's zorkmid tile is REAL loot (the PLAYER's zorkmids are a `money` float
	# that never enters a bag), so it must serialize AND restore like any stack. Also pins that a
	# grid-bounded crate re-bounds on restore with its cells honored, and that restore REPLACES the fresh seed.
	var coin: Item = ItemDb.item_by_id(Zorkmids.ITEM_ID)
	assert_not_null(coin, "the zorkmid coin item is registered in ItemDb")
	var src := ItemContainer.new()
	var src_inv := CharacterInventory.new()
	src.inventory = src_inv  # off-tree: _ready never ran, so wire the bag directly (the _seed_contents idiom)
	src_inv.enable_grid(4, 4)  # the loot screen had bounded this crate in-session
	src_inv.add(coin, 5)
	# MOVE the stack off the origin before capturing. add() always lands at the first free slot (0,0), so a
	# restore that silently AUTO-PLACED instead of honouring the saved cell would still land on (0,0) and the
	# layout assertion below would pass against itself — the pin has to compare a non-default cell.
	var src_key: int = int((src_inv.placed_contents()[0] as Dictionary)["key"])
	assert_true(src_inv.move_stack(src_key, 2, 1, coin.grid_width, coin.grid_height),
		"the coin tile moves to a non-origin cell (2,1) so the placement round-trip is falsifiable")
	var d := src.snapshot_contents()
	assert_true(bool(d["grid"]), "the grid-bounded bit rides in the entry")
	assert_eq((d["stacks"] as Array).size(), 1, "the coin tile serializes — container coins are real loot")
	var entry: Dictionary = d["stacks"][0]
	assert_eq(entry["id"], String(Zorkmids.ITEM_ID), "serialized by registered id")
	assert_eq(entry["count"], 5, "count survives")
	assert_eq(int(entry["x"]), 2, "the moved stack's COLUMN is what serializes, not the default 0")
	assert_eq(int(entry["y"]), 1, "…and its ROW")

	var dst := ItemContainer.new()
	var dst_inv := CharacterInventory.new()
	dst.inventory = dst_inv
	dst_inv.add(coin, 99)  # the fresh _ready seed the restore must REPLACE, never merge onto
	dst.restore_snapshot_contents(d)
	assert_eq(dst_inv.count_of_id(Zorkmids.ITEM_ID), 5, "restore replaces the seeded bag with the exact saved one")
	assert_true(dst_inv.grid_enabled(), "a grid-bounded save re-bounds the restored container")
	var row: Dictionary = dst_inv.placed_contents()[0]
	assert_eq(int(row["x"]), 2, "the saved COLUMN is honored on restore, not auto-placed back to 0 (layout survives)")
	assert_eq(int(row["y"]), 1, "…and the saved ROW")
	src.free()
	src_inv.free()
	dst.free()
	dst_inv.free()

func test_restore_serialized_stacks_degrades_a_junk_count_instead_of_erroring() -> void:
	# from_dict deliberately filters container stacks only down to "Array of Dictionary" and delegates per-FIELD
	# junk here. A non-numeric count must therefore be SKIPPED, not fed to int() — int([3]) is a hard runtime
	# error, which would abort the restore loop and silently drop every LATER stack in the bag (GUT also fails
	# the script on an engine error, so this test would go red rather than quietly pass).
	var inv := CharacterInventory.new()
	inv.restore_serialized_stacks([
		{"id": "ammo_pistol", "count": [3]},          # junk count -> skipped, no error
		{"id": "ammo_pistol", "count": 4},            # the stack AFTER it must still restore
		{"id": "ammo_pistol"},                        # missing count -> defaults to 1
	])
	assert_eq(inv.count_of_id(&"ammo_pistol"), 5,
		"a junk count is skipped and the following stacks still restore (4 + the defaulted 1)")
	inv.free()

func test_item_container_snapshot_key_identity_contract() -> void:
	# CLAUDE.md: "For save/load work, test IDENTITY as well as coordinates or values … container id". The whole
	# v2 tier hinges on snapshot_key() returning the SAME string at capture and at apply — an authored save_id
	# must win outright (so the key survives renaming/re-parenting the node), and the fallback must be the
	# POSITION-FREE level|node_path, never WorldSaveId.key_for (whose position component would never re-match).
	var crate := ItemContainer.new()
	crate.name = &"SupplyCrate"
	crate.save_id = &"dock_crate"
	assert_eq(crate.snapshot_key(), "id:dock_crate", "an authored save_id IS the whole key")
	crate.name = &"RenamedCrate"  # a scene-layout edit must not move the key
	assert_eq(crate.snapshot_key(), "id:dock_crate", "…and it survives renaming the node")
	crate.save_id = &""
	# Off-tree, the fallback uses the node NAME (is_inside_tree() is false) — in-tree it is the node path.
	# Either way the level path prefixes it and the live POSITION never appears.
	var fallback := crate.snapshot_key()
	assert_true(fallback.begins_with(GameState.current_level_path + "|"),
		"the id-less fallback is scoped by level so two levels' identically-pathed crates stay distinct: %s" % fallback)
	assert_false(fallback.begins_with("id:"), "the fallback is not an id: key")
	crate.position = Vector3(37, 12, -9)
	assert_eq(crate.snapshot_key(), fallback, "the key is POSITION-FREE — moving the crate must not re-key it")
	crate.free()

func test_item_container_restore_applies_lock_state_only_when_present() -> void:
	var crate := ItemContainer.new()
	var inv := CharacterInventory.new()
	crate.inventory = inv
	var lock := Lock.new()
	crate.add_child(lock)  # Lock.of finds the first Lock child; freed with the crate
	lock.locked = true  # authored: shut
	crate.restore_snapshot_contents({"stacks": [], "grid": false, "locked": false})
	assert_false(lock.locked, "a save taken after picking the lock restores it OPEN")
	lock.locked = true
	crate.restore_snapshot_contents({"stacks": [], "grid": false})
	assert_true(lock.locked, "an entry with no locked bit leaves the lock untouched (from_dict omits junk)")
	crate.free()
	inv.free()

func test_restocker_does_not_insta_refill_a_restored_container() -> void:
	# Quickload must never be a free restock: restore_snapshot_contents marks child Restockers spent
	# (note_restored), so ON_VISIT's first-visit-always rule can't top a just-restored looted crate back up.
	var crate := ItemContainer.new()
	var inv := CharacterInventory.new()
	crate.inventory = inv
	var ammo := Item.new()
	ammo.id = &"__test_restock_ammo"
	ammo.display_name = "Ammo"
	ammo.max_stack = 30
	var st := ItemStack.new()
	st.item = ammo
	st.count = 5
	crate.item_stacks.append(st)  # the authored baseline refill() tops toward
	var stocker := Restocker.new()
	stocker.mode = Restocker.Mode.ON_VISIT
	stocker.interval = 9999.0
	crate.add_child(stocker)  # freed with the crate
	stocker._target = crate  # _ready (which resolves the parent target) never runs off-tree
	crate.restore_snapshot_contents({"stacks": [], "grid": false})  # save-time bag: fully looted
	Restocker.notify_visit(crate)  # the first reopen after the quickload
	assert_eq(inv.count_of_id(&"__test_restock_ammo"), 0,
		"the first reopen after a quickload does NOT insta-refill (note_restored marked the cycle spent)")
	stocker._elapsed = stocker.interval  # a full interval later...
	Restocker.notify_visit(crate)
	assert_eq(inv.count_of_id(&"__test_restock_ammo"), 5, "...the ON_VISIT restock cycle resumes normally")
	crate.free()
	inv.free()

# --- _reload_pending latch (quickload autosave-race guard) ----------------------------------------------------
func test_autosave_bails_while_reload_pending() -> void:
	# During a quickload/slot-load the OLD player is still in-tree while the scene reload is deferred. A same-frame
	# deferred autosave flush (a kill bounty / a door fire) must NOT capture it over the freshly-loaded profile. The
	# latch guard sits AFTER the in-tree guard, so an in-tree stub player reaches it and bails BEFORE the ledger is
	# captured into or anything is written — we prove the bail by the sentinel ledger surviving untouched.
	var gs := _bare_gs()
	var player := Node.new()
	add_child_autofree(player)  # in-tree -> passes autosave's first guard so we actually reach the latch
	var sentinel := WorldSnapshot.new()
	gs.world_snapshot = sentinel
	gs._reload_pending = true
	gs.autosave(player)
	assert_eq(gs.world_snapshot, sentinel, "a reload-in-flight autosave bails before touching the ledger or writing the profile")
	assert_true(sentinel.is_empty(), "nothing was captured into it")
	gs.free()

func test_set_current_level_lifts_the_reload_freeze() -> void:
	# The fresh scene's GameRoot boot (set_current_level, called on EVERY level load) clears the latch, so autosave
	# resumes normally once the reloaded world is up. Harmless on a non-reload load (the latch is already false).
	var gs := _bare_gs()
	gs._reload_pending = true
	gs.set_current_level("res://lvl.tres")
	assert_false(gs._reload_pending, "GameRoot boot lifts the autosave freeze latch")
	assert_eq(gs.current_level_path, "res://lvl.tres", "and records the active level")
	gs.free()


# --- The per-level world ledger (2026-09-16 policy) -----------------------------------------------------------

func test_has_level_answers_per_bucket() -> void:
	var snap := WorldSnapshot.new()
	assert_false(snap.has_level("res://a.tres"), "an empty ledger knows no level")
	snap.from_dict({"res://a.tres": {"authored_npcs": {}, "dead_authored": []}})
	assert_true(snap.has_level("res://a.tres"), "a bucket (even an empty one) makes the level known")
	assert_false(snap.has_level("res://b.tres"), "another level stays unknown")
	snap = null

func test_capture_without_live_npcs_keeps_deaths_and_containers() -> void:
	# The RELOAD_CHECKPOINT_FRESH death banks the level this way: actors go back to their authored spots, but the loot
	# the kept profile already holds must not re-seed into its crate (a duplicate), and the dead stay dead.
	var alive := NpcStub.new()
	alive.key = "id:guard"
	add_child_autofree(alive)
	alive.add_to_group(Groups.NPC)
	var crate := ContainerStub.new()
	crate.key = "id:crate"
	crate.contents = {"stacks": [], "grid": false}
	add_child_autofree(crate)
	crate.add_to_group(Groups.CONTAINERS)
	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://lvl.tres", {"id:dead": true, "id:guard": true}, false)
	var b: Dictionary = snap.to_dict()["res://lvl.tres"]
	assert_true((b["authored_npcs"] as Dictionary).is_empty(), "no live NPC position/hp is recorded")
	assert_eq(b["dead_authored"], ["id:dead"], "deaths still record — and a stale key for an NPC seen ALIVE still drops (live wins)")
	assert_eq(b["containers"], {"id:crate": crate.contents}, "containers still record")
	snap = null

func test_capture_replaces_its_bucket_so_saving_repeatedly_never_grows_the_payload() -> void:
	# The autosave-storm budget: autosave runs on every milestone (a pickup, a kill bounty, a flag), and every one now
	# captures the current level. A capture must REPLACE the level's bucket and a fold must MERGE keys, so a thousand
	# saves of the same world produce the same bytes as one.
	var npc := NpcStub.new()
	npc.key = "id:guard"
	add_child_autofree(npc)
	npc.add_to_group(Groups.NPC)
	var crate := ContainerStub.new()
	crate.key = "id:crate"
	crate.contents = {"stacks": [{"id": "ammo_pistol", "count": 12, "x": 0, "y": 0, "w": 1, "h": 1}], "grid": true}
	add_child_autofree(crate)
	crate.add_to_group(Groups.CONTAINERS)
	var dead_all := {"res://lvl.tres": {"id:ghost": true}, "res://other.tres": {"id:b": true}}
	var snap := WorldSnapshot.new()
	snap.capture(get_tree(), "res://lvl.tres", dead_all["res://lvl.tres"])
	snap.fold_dead_ledger(dead_all, "res://lvl.tres")
	var once := var_to_str(snap.to_dict()).length()
	for i in 25:
		snap.capture(get_tree(), "res://lvl.tres", dead_all["res://lvl.tres"])
		snap.fold_dead_ledger(dead_all, "res://lvl.tres")
	assert_eq(var_to_str(snap.to_dict()).length(), once, "25 more saves of the same world write exactly the same payload")
	snap = null

func test_capture_level_state_skips_a_level_whose_apply_is_queued() -> void:
	var gs := _bare_gs()
	gs.world_snapshot.from_dict({"res://lvl.tres": {"authored_npcs": {}, "dead_authored": [],
		"containers": {"id:crate": {"stacks": [], "grid": false}}}})  # saved: looted empty
	var crate := ContainerStub.new()
	crate.key = "id:crate"
	crate.contents = {"stacks": [{"id": "ammo_pistol", "count": 30}], "grid": false}  # the fresh authored seed
	add_child_autofree(crate)
	crate.add_to_group(Groups.CONTAINERS)
	assert_true(gs.begin_level_load("res://lvl.tres"), "precondition: the level has a bucket, so its apply is queued")
	gs.capture_level_state(get_tree(), "res://lvl.tres")
	assert_eq(gs.world_snapshot.to_dict()["res://lvl.tres"]["containers"]["id:crate"]["stacks"], [],
		"a capture BEFORE the apply is refused — the saved looted state is not overwritten by the fresh seed")
	gs.apply_level_state(get_tree(), "res://lvl.tres")
	assert_eq(crate.restored_with, {"stacks": [], "grid": false}, "the apply hands the container its saved state")
	assert_eq(gs._level_apply_pending, "", "and lifts the guard")
	crate.contents = {"stacks": [], "grid": false}  # what the container now reports
	gs.capture_level_state(get_tree(), "res://lvl.tres")
	assert_true(gs.world_snapshot.has_level("res://lvl.tres"), "after the apply, captures run normally")
	gs.capture_level_state(get_tree(), "")
	assert_false(gs.world_snapshot.has_level(""), "a blank level path (a code-built LevelData) is never captured")
	gs.free()

func test_capture_level_state_never_writes_to_disk() -> void:
	# Watch the autosave-storm counters: a level change captures the outgoing level, and that must cost NO disk write
	# of its own — the next ordinary save persists it.
	var gs := _bare_gs()
	var crate := ContainerStub.new()
	crate.key = "id:crate"
	add_child_autofree(crate)
	crate.add_to_group(Groups.CONTAINERS)
	watch_signals(gs)
	var before: int = gs.save_count
	gs.capture_level_state(get_tree(), "res://lvl.tres")
	gs.capture_world_state()
	assert_eq(gs.save_count, before, "capturing never increments save_count")
	assert_signal_not_emitted(gs, "saved", "and never emits saved(path, err)")
	gs.free()

func test_capture_world_state_folds_deaths_into_levels_not_in_the_tree() -> void:
	# A bare (off-tree) GameState cannot capture a live level, but the fold still runs: a kill recorded in level B since
	# the player last left it reaches B's bucket without disturbing B's captured containers.
	var gs := _bare_gs()
	gs.world_snapshot.from_dict({"res://b.tres": {"authored_npcs": {}, "dead_authored": [],
		"containers": {"id:safe": {"stacks": [], "grid": false}}}})
	gs.current_level_path = "res://a.tres"
	gs.record_npc_death("res://b.tres", "id:guard")
	gs.capture_world_state()
	var b: Dictionary = gs.world_snapshot.to_dict()["res://b.tres"]
	assert_eq(b["dead_authored"], ["id:guard"], "the new death reached level B's bucket")
	assert_true((b["containers"] as Dictionary).has("id:safe"), "and B's looted safe is still in it")
	gs.free()
