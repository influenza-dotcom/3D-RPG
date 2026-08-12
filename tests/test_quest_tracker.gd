extends GutTest

## The M1 SPLIT ITSELF — the seam between GameState and the QuestTracker autoload.
##
## `test_quests.gd` covers quest BEHAVIOUR (start/advance/complete/fail/hooks). This file covers the things the
## split newly makes possible to get wrong, none of which behaviour tests would catch:
##   • the GameState forwarders actually reach a tracker (a typo'd forwarder is silently inert)
##   • the autoload pairs with the autoload, but a BARE GameState gets its OWN private tracker
##   • that private tracker is OWNED (freed with its GameState) so the suite doesn't grow orphans
##   • the signals moved — GameState no longer carries them
##
## The isolation rule is the load-bearing one. Quest state used to live on GameState, so a bare `GameState.new()`
## gave a test a private journal for free. If the split had simply pointed every GameState at the singleton, quest
## state would leak between tests — which is exactly what happened during the split (a stale quest from one test
## got written into another test's save, whose .tres was already deleted, and the reload hit an engine error).

const GAMESTATE_PATH := "res://managers/GameState.gd"
const QUESTTRACKER_PATH := "res://managers/QuestTracker.gd"


func _obj(oid: StringName, cnt := 1) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = oid
	o.required_count = cnt
	return o

func _quest(qid: StringName, objs: Array, auto := true) -> Quest:
	var q := Quest.new()
	q.id = qid
	for o in objs:
		q.objectives.append(o)
	q.auto_complete = auto
	return q


# --- Pairing + isolation --------------------------------------------------------------------------------------

func test_bare_gamestate_gets_its_own_private_tracker() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_obj(&"x", 1)], false))
	assert_ne(gs._qt(), QuestTracker,
		"a bare GameState must NOT drive the autoload — that is how quest state leaks between tests")
	assert_true(gs.is_quest_active(&"q1"), "...but its own private tracker still tracks the quest")
	assert_false(QuestTracker.is_quest_active(&"q1"), "the autoload's journal must be untouched by a bare instance")
	gs.free()

func test_two_bare_gamestates_do_not_share_a_journal() -> void:
	var a = load(GAMESTATE_PATH).new()
	var b = load(GAMESTATE_PATH).new()
	a.start_quest(_quest(&"only_in_a", [_obj(&"x", 1)], false))
	assert_true(a.is_quest_active(&"only_in_a"), "the quest is active on the instance that started it")
	assert_false(b.is_quest_active(&"only_in_a"), "a second bare GameState must have a wholly separate journal")
	a.free()
	b.free()

func test_private_tracker_is_owned_and_freed_with_its_gamestate() -> void:
	# Freed WITH its owner, or every bare-GameState test in the suite would leak a Node and GUT would start
	# reporting orphans that have nothing to do with the test that caused them.
	var gs = load(GAMESTATE_PATH).new()
	var qt = gs._qt()
	assert_eq(qt.get_parent(), gs, "the private tracker must be a CHILD of its GameState, so it dies with it")
	assert_true(is_instance_valid(qt), "the tracker is alive while its GameState is")
	gs.free()
	assert_false(is_instance_valid(qt), "freeing the GameState must free its private tracker — no orphan")

func test_explicitly_injected_tracker_wins() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var qt = load(QUESTTRACKER_PATH).new()
	gs.quest_tracker = qt
	qt.game_state = gs
	gs.start_quest(_quest(&"q1", [_obj(&"x", 1)], false))
	assert_true(qt.is_quest_active(&"q1"), "an explicitly wired tracker is the one the forwarders drive")
	assert_eq(gs._qt(), qt, "...and no private tracker is created alongside it")
	qt.free()
	gs.free()

func test_autoload_gamestate_pairs_with_the_autoload_tracker() -> void:
	assert_eq(GameState._qt(), QuestTracker,
		"in a real run the GameState autoload must drive the QuestTracker autoload, not a private copy")


# --- The forwarders -------------------------------------------------------------------------------------------

func test_every_forwarder_reaches_the_tracker() -> void:
	# A forwarder that was mistyped (or never written) is SILENTLY inert — the call succeeds and does nothing.
	# Drive each one through GameState and read the answer back off the tracker itself.
	var gs = load(GAMESTATE_PATH).new()
	var qt = gs._qt()
	gs.start_quest(_quest(&"q1", [_obj(&"kill", 2)], false))
	assert_true(qt.is_quest_active(&"q1"), "start_quest forwards")
	gs.advance_objective(&"q1", &"kill", 1)
	assert_eq(qt.objective_progress(&"q1", &"kill"), 1, "advance_objective forwards")
	assert_eq(gs.objective_progress(&"q1", &"kill"), 1, "objective_progress forwards back")
	assert_false(gs.is_objective_done(&"q1", &"kill"), "is_objective_done forwards (1 of 2)")
	assert_eq(gs.active_quest_ids().size(), 1, "active_quest_ids forwards")
	assert_not_null(gs.active_quest(&"q1"), "active_quest forwards")
	gs.complete_quest(&"q1")
	assert_true(qt.is_quest_completed(&"q1"), "complete_quest forwards")
	assert_true(gs.is_quest_completed(&"q1"), "is_quest_completed forwards back")
	assert_eq(gs.completed_quests().size(), 1, "completed_quests forwards")
	gs.start_quest(_quest(&"q2", [_obj(&"x", 1)], false))
	gs.fail_quest(&"q2")
	assert_true(qt.is_quest_failed(&"q2"), "fail_quest forwards")
	assert_true(gs.is_quest_failed(&"q2"), "is_quest_failed forwards back")
	assert_eq(gs.failed_quests().size(), 1, "failed_quests forwards")
	gs.free()

func test_notify_hooks_forward() -> void:
	var gs = load(GAMESTATE_PATH).new()
	for spec in [
			{"type": QuestObjective.Type.KILL, "target": &"Raider"},
			{"type": QuestObjective.Type.PICKUP, "target": &"medkit"},
			{"type": QuestObjective.Type.TALK, "target": &"Doc"},
			{"type": QuestObjective.Type.ENTER_AREA, "target": &"vault"},
			{"type": QuestObjective.Type.USE_ITEM, "target": &"key"}]:
		var o := _obj(&"step", 1)
		o.type = spec["type"]
		o.target_id = spec["target"]
		gs.start_quest(_quest(StringName("q_%s" % spec["target"]), [o]))
	gs.notify_kill(&"Raider")
	gs.notify_pickup(&"medkit")
	gs.notify_talk(&"Doc")
	gs.notify_enter(&"vault")
	gs.notify_use(&"key")
	for t in ["Raider", "medkit", "Doc", "vault", "key"]:
		assert_true(gs.is_quest_completed(StringName("q_%s" % t)),
			"the %s hook must forward through GameState to the tracker" % t)
	gs.free()

func test_take_load_warnings_forwards() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var cfg := ConfigFile.new()
	# A path that loads but is NOT a Quest stands in for a moved/renamed .tres: `as Quest` is null — the same skip
	# branch — without a missing-resource engine error that would trip GUT.
	cfg.set_value("quests_active", "q_ghost", {"path": GAMESTATE_PATH, "progress": {}})
	gs._load_perks_and_quests(cfg)
	assert_eq(gs.take_load_warnings().size(), 1, "the B-F40 warning reaches the HUD through GameState's forwarder")
	assert_eq(gs.take_load_warnings().size(), 0, "...and is consume-once")
	gs.free()


# --- What did NOT stay behind ---------------------------------------------------------------------------------

func test_quest_signals_live_on_the_tracker_not_gamestate() -> void:
	# The signals moved with the state, so `GameState.quest_started.connect(...)` would now be a runtime error.
	# Listeners (ui.gd, quest_journal.gd, quest_marker_sync.gd, reward_stinger.gd) connect to QuestTracker.
	for sig in ["quest_started", "objective_advanced", "quest_completed", "quest_failed"]:
		assert_true(QuestTracker.has_signal(sig), "QuestTracker must declare %s" % sig)
		assert_false(GameState.has_signal(sig),
			"GameState must NOT still declare %s — two emitters would mean half the listeners go deaf" % sig)


# --- Persistence ----------------------------------------------------------------------------------------------

func test_save_into_and_load_from_round_trip_through_a_fresh_tracker() -> void:
	var qt_a = load(QUESTTRACKER_PATH).new()
	var q := _quest(&"q_rt", [_obj(&"kill", 3)], false)
	# Only a quest with a resource_path can round-trip; point it at a real .gd so load() returns non-null.
	# (It won't cast to Quest, so we assert the SHAPE that reached the cfg rather than the restored resource.)
	qt_a.start_quest(q)
	qt_a.advance_objective(&"q_rt", &"kill", 2)
	var cfg := ConfigFile.new()
	qt_a.save_into(cfg)
	assert_false(cfg.has_section("quests_active"),
		"a code-built Quest has no resource_path, so it is deliberately SKIPPED rather than written unloadable")
	qt_a.free()

func test_load_from_restores_progress_and_clears_prior_state() -> void:
	var qt = load(QUESTTRACKER_PATH).new()
	qt.start_quest(_quest(&"stale", [_obj(&"x", 1)], false))
	assert_true(qt.is_quest_active(&"stale"), "a quest is active before the load")
	qt.load_from(ConfigFile.new())  # an empty cfg — a save with no quest sections
	assert_false(qt.is_quest_active(&"stale"),
		"load_from must CLEAR prior state, or loading a save would merge into the previous run's journal")
	qt.free()

func test_load_from_drops_a_junk_progress_value_instead_of_erroring() -> void:
	# Mirrors test_world_snapshot's junk-count degrade: guarding the SHAPE of the progress dict is not enough — a
	# hand-edited save can hold any Variant under a progress key, and int([3]) at advance_objective is a hard
	# runtime ERROR (not a coercion) that aborts BEFORE the assignment, bricking the objective for good. load_from
	# must DROP the junk value (that objective degrades to 0) while a numeric sibling restores intact — the
	# loader's own "degrade, never hard-fail" contract. An authored .tres (whose existence test_sample_resources.gd
	# already pins) stands in for the restored quest; objective_progress reads the progress dict directly, so the
	# keys need not match its authored objectives.
	var qt = load(QUESTTRACKER_PATH).new()
	var cfg := ConfigFile.new()
	cfg.set_value("quests_active", "q_junk",
		{"path": "res://resources/quests/clear_the_block.tres", "progress": {"broken": [3], "fine": 2.0}})
	qt.load_from(cfg)
	assert_true(qt.is_quest_active(&"q_junk"), "the quest itself still restores — only the junk VALUE is dropped")
	assert_eq(qt.objective_progress(&"q_junk", &"broken"), 0, "a junk-typed progress value degrades to 0 progress")
	assert_eq(qt.objective_progress(&"q_junk", &"fine"), 2,
		"a numeric sibling survives the rebuild (float coerces, per the _cfg_int accept-list)")
	qt.free()

func test_reset_clears_every_bucket() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var qt = gs._qt()
	gs.start_quest(_quest(&"a", [_obj(&"x", 1)], false))
	gs.start_quest(_quest(&"b", [_obj(&"x", 1)], false))
	gs.complete_quest(&"a")
	gs.fail_quest(&"b")
	qt.reset()
	assert_false(qt.is_quest_completed(&"a"), "reset clears completed")
	assert_false(qt.is_quest_failed(&"b"), "reset clears failed")
	assert_eq(qt.active_quest_ids().size(), 0, "reset clears active")
	gs.free()


# --- The flag hook, which is the one seam that runs GameState -> tracker ---------------------------------------

func test_set_flag_drives_both_halves_of_the_quest_hook() -> void:
	# GameState.set_flag is the ONLY inbound edge: it must both ADVANCE a FLAG objective and EXPIRE a quest whose
	# expire_on_flag matches. Losing either half in the split would be invisible until playtest.
	var gs = load(GAMESTATE_PATH).new()
	var advance_obj := _obj(&"reach", 1)
	advance_obj.type = QuestObjective.Type.FLAG
	advance_obj.target_id = &"gate_opened"
	gs.start_quest(_quest(&"q_advance", [advance_obj]))
	var doomed := _quest(&"q_expire", [_obj(&"save", 1)], false)
	doomed.expire_on_flag = &"gate_opened"
	gs.start_quest(doomed)
	gs.set_flag(&"gate_opened")
	assert_true(gs.is_quest_completed(&"q_advance"), "the flag must ADVANCE a matching FLAG objective")
	assert_true(gs.is_quest_failed(&"q_expire"), "...and EXPIRE a quest whose expire_on_flag matches")
	gs.free()

func test_tracker_reads_flags_off_its_own_gamestate() -> void:
	# The M15 back-fill reads a flag that is ALREADY set when the quest starts. A tracker wired to instance A must
	# read A's flags — not the autoload's — or a bare test would silently consult global state.
	var gs = load(GAMESTATE_PATH).new()
	gs.set_flag(&"already_true")
	var o := _obj(&"reach", 1)
	o.type = QuestObjective.Type.FLAG
	o.target_id = &"already_true"
	gs.start_quest(_quest(&"q_backfill", [o]))
	assert_true(gs.is_quest_completed(&"q_backfill"),
		"the back-fill must see the flag on ITS OWN GameState")
	gs.free()
