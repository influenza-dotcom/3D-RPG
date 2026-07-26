extends GutTest

## Slice 6a (quests): the GameState quest tracker — start, advance (clamped to required_count), auto-complete
## once the required objectives are done (optional ones don't block), explicit turn-in, the New-Game clear, and
## the signals. Uses a FRESH GameState instance (never the autoload); rewards no-op off-tree (no player in the
## tree), so it's isolated like test_game_save / test_story_flags. Objective HOOKS + persistence are the next slice.

const GAMESTATE_PATH := "res://managers/GameState.gd"

func _obj(oid: StringName, cnt := 1, optional := false) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = oid
	o.required_count = cnt
	o.optional = optional
	return o

func _quest(qid: StringName, objs: Array, auto := true) -> Quest:
	var q := Quest.new()
	q.id = qid
	for o in objs:
		q.objectives.append(o)
	q.auto_complete = auto
	return q

func test_start_tracks_and_emits() -> void:
	var gs = load(GAMESTATE_PATH).new()
	watch_signals(gs)
	gs.start_quest(_quest(&"q1", [_obj(&"kill", 2)]))
	assert_true(gs.is_quest_active(&"q1"), "active after start")
	assert_signal_emitted(gs, "quest_started", "start emits quest_started")
	gs.free()

func test_advance_completes_when_required_done() -> void:
	var gs = load(GAMESTATE_PATH).new()
	watch_signals(gs)
	gs.start_quest(_quest(&"q1", [_obj(&"kill", 2)]))
	gs.advance_objective(&"q1", &"kill", 1)
	assert_false(gs.is_quest_completed(&"q1"), "not complete at 1/2")
	assert_eq(gs.objective_progress(&"q1", &"kill"), 1, "progress is 1")
	gs.advance_objective(&"q1", &"kill", 1)
	assert_true(gs.is_quest_completed(&"q1"), "auto-completes at 2/2")
	assert_false(gs.is_quest_active(&"q1"), "no longer active once complete")
	assert_signal_emitted(gs, "quest_completed", "completion emits quest_completed")
	gs.free()

func test_optional_objective_does_not_block() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_obj(&"main", 1), _obj(&"bonus", 1, true)]))
	gs.advance_objective(&"q1", &"main", 1)  # required done; bonus still 0
	assert_true(gs.is_quest_completed(&"q1"), "required done completes it; the optional objective doesn't block")
	gs.free()

func test_progress_clamps_and_explicit_turn_in() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_obj(&"kill", 2)], false))  # auto_complete off
	gs.advance_objective(&"q1", &"kill", 99)
	assert_eq(gs.objective_progress(&"q1", &"kill"), 2, "count clamps to required_count")
	assert_true(gs.is_quest_active(&"q1"), "stays active without auto_complete")
	gs.complete_quest(&"q1")
	assert_true(gs.is_quest_completed(&"q1"), "explicit turn-in completes it")
	gs.free()

func test_no_restart_of_active_or_completed() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var q := _quest(&"q1", [_obj(&"x", 1)])
	gs.start_quest(q)
	gs.start_quest(q)  # already active -> no-op
	gs.advance_objective(&"q1", &"x", 1)  # completes
	gs.start_quest(q)  # already completed -> no-op
	assert_false(gs.is_quest_active(&"q1"), "a completed quest doesn't restart")
	gs.free()

func test_reset_for_new_game_clears_quests() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_obj(&"x", 1)], false))
	gs.reset_for_new_game()
	assert_false(gs.is_quest_active(&"q1"), "New Game clears active quests")
	gs.free()


# --- WR-6: quest fail / expire-on-flag ----------------------------------------------------------------------

func test_fail_quest_moves_active_to_failed() -> void:
	var gs = load(GAMESTATE_PATH).new()
	watch_signals(gs)
	gs.start_quest(_quest(&"q1", [_obj(&"kill", 2)]))
	gs.fail_quest(&"q1")
	assert_true(gs.is_quest_failed(&"q1"), "failed after fail_quest")
	assert_false(gs.is_quest_active(&"q1"), "no longer active once failed")
	assert_false(gs.is_quest_completed(&"q1"), "a failed quest is not completed")
	assert_signal_emitted(gs, "quest_failed", "fail emits quest_failed")
	gs.free()

func test_fail_quest_noop_on_non_active() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.fail_quest(&"never")  # unknown quest -> no-op, no crash
	assert_false(gs.is_quest_failed(&"never"), "failing an unknown quest is a no-op")
	gs.start_quest(_quest(&"q1", [_obj(&"x", 1)]))
	gs.complete_quest(&"q1")
	gs.fail_quest(&"q1")  # already completed -> fail_quest only acts on ACTIVE
	assert_false(gs.is_quest_failed(&"q1"), "a completed quest can't be failed")
	assert_true(gs.is_quest_completed(&"q1"), "...it stays completed")
	gs.free()

func test_expire_on_flag_auto_fails_active_quest() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var q := _quest(&"rescue", [_obj(&"save", 1)])
	q.expire_on_flag = &"hostage_dead"
	gs.start_quest(q)
	assert_true(gs.is_quest_active(&"rescue"), "active before the flag")
	gs.set_flag(&"hostage_dead", true)
	assert_true(gs.is_quest_failed(&"rescue"), "setting expire_on_flag auto-fails the active quest")
	assert_false(gs.is_quest_active(&"rescue"), "...and it leaves the active set")
	gs.free()

func test_expire_on_flag_inert_for_other_flags() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var q := _quest(&"rescue", [_obj(&"save", 1)])
	q.expire_on_flag = &"hostage_dead"
	gs.start_quest(q)
	gs.set_flag(&"some_other_flag", true)  # a DIFFERENT flag must not expire it
	assert_true(gs.is_quest_active(&"rescue"), "an unrelated flag leaves the quest active")
	assert_false(gs.is_quest_failed(&"rescue"), "...not failed")
	gs.free()

func test_failed_quest_cannot_restart() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var q := _quest(&"q1", [_obj(&"x", 1)])
	gs.start_quest(q)
	gs.fail_quest(&"q1")
	gs.start_quest(q)  # try to re-start the failed quest
	assert_false(gs.is_quest_active(&"q1"), "a failed quest can't be re-started")
	assert_true(gs.is_quest_failed(&"q1"), "...it stays failed")
	gs.free()

func test_reset_for_new_game_clears_failed() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_obj(&"x", 1)]))
	gs.fail_quest(&"q1")
	gs.reset_for_new_game()
	assert_false(gs.is_quest_failed(&"q1"), "New Game forgets failed quests")
	gs.free()

# --- 6b hooks: FLAG (via set_flag) + KILL (via notify_kill) ---

func _flag_obj(oid: StringName, flag: StringName) -> QuestObjective:
	var o := _obj(oid, 1)
	o.type = QuestObjective.Type.FLAG
	o.target_id = flag
	return o

func test_flag_objective_advances_on_set_flag() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_flag_obj(&"reach", &"reached_exit")]))
	gs.set_flag(&"reached_exit")  # the universal hook — any flag set can drive a quest step
	assert_true(gs.is_quest_completed(&"q1"), "setting the objective's flag advances + completes it")
	gs.free()

func test_flag_objective_ignores_unrelated_flag() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_flag_obj(&"reach", &"reached_exit")]))
	gs.set_flag(&"some_other_flag")
	assert_false(gs.is_quest_completed(&"q1"), "an unrelated flag doesn't advance it")
	gs.free()


# --- M15: start_quest back-fills FLAG objectives whose flag is ALREADY set (chained quests) ---

func test_start_quest_backfills_already_set_flag() -> void:
	# A CHAINED quest keyed on a flag an earlier quest / action already flipped: set_flag won't fire again, so without
	# the back-fill the objective stalls at 0. Starting with the flag already up should satisfy it immediately.
	var gs = load(GAMESTATE_PATH).new()
	gs.set_flag(&"gate_opened")  # flipped BEFORE this quest is started
	gs.start_quest(_quest(&"q1", [_flag_obj(&"reach", &"gate_opened")]))
	assert_true(gs.is_quest_completed(&"q1"), "a FLAG objective on an already-set flag is back-filled + auto-completes at start")
	gs.free()

func test_start_quest_no_backfill_when_flag_unset() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_flag_obj(&"reach", &"gate_opened")]))  # flag never set
	assert_false(gs.is_quest_completed(&"q1"), "an unset flag is not back-filled")
	assert_true(gs.is_quest_active(&"q1"), "the quest stays active, awaiting the flag")
	gs.free()

func test_start_quest_no_backfill_for_falsey_flag() -> void:
	# A flag explicitly set FALSEY must not satisfy the objective — get_flag's truthiness gates the back-fill exactly
	# like the live set_flag hook (which only advances on a truthy value).
	var gs = load(GAMESTATE_PATH).new()
	gs.set_flag(&"gate_opened", false)
	gs.start_quest(_quest(&"q1", [_flag_obj(&"reach", &"gate_opened")]))
	assert_false(gs.is_quest_completed(&"q1"), "a falsey flag does not back-fill the objective")
	gs.free()

func test_start_quest_backfill_leaves_other_objectives_alone() -> void:
	# Back-fill only touches FLAG objectives whose flag is up; a still-open KILL objective keeps the quest active, so a
	# multi-objective quest doesn't wrongly complete on start.
	var gs = load(GAMESTATE_PATH).new()
	gs.set_flag(&"gate_opened")
	gs.start_quest(_quest(&"q1", [_flag_obj(&"reach", &"gate_opened"), _obj(&"kill", 2)]))
	assert_false(gs.is_quest_completed(&"q1"), "a still-open KILL objective keeps the quest active despite the back-filled flag")
	assert_true(gs.is_objective_done(&"q1", &"reach"), "the FLAG objective IS satisfied by the back-fill")
	assert_false(gs.is_objective_done(&"q1", &"kill"), "the KILL objective is untouched")
	gs.free()


# --- B-F40: a saved quest whose .tres won't load is surfaced (a HUD warning), not silently dropped ---

func test_load_skip_records_a_warning() -> void:
	# A saved active quest whose path no longer loads AS A QUEST is dropped; B-F40 records a user-facing warning the
	# HUD can toast. A non-Quest path stands in for a missing/renamed one: load() succeeds but `as Quest` is null —
	# the same skip branch, and no missing-resource engine error to trip GUT.
	var gs = load(GAMESTATE_PATH).new()
	var cfg := ConfigFile.new()
	cfg.set_value("quests_active", "q_ghost", {"path": GAMESTATE_PATH, "progress": {}})
	gs._load_perks_and_quests(cfg)
	assert_eq(gs.take_load_warnings().size(), 1, "a dropped active quest records one load warning")
	gs.free()

func test_clean_load_records_no_warnings() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs._load_perks_and_quests(ConfigFile.new())  # no quest sections -> nothing to skip
	assert_eq(gs.take_load_warnings().size(), 0, "a clean load records no warnings")
	gs.free()

func test_take_load_warnings_consumes_once() -> void:
	# The HUD consumes the warnings; a second read is empty, so a HUD rebuild on a level change doesn't re-toast them.
	var gs = load(GAMESTATE_PATH).new()
	var cfg := ConfigFile.new()
	cfg.set_value("quests_active", "q_ghost", {"path": GAMESTATE_PATH, "progress": {}})
	gs._load_perks_and_quests(cfg)
	assert_eq(gs.take_load_warnings().size(), 1, "first read returns the warning")
	assert_eq(gs.take_load_warnings().size(), 0, "second read is empty (consumed)")
	gs.free()

func test_kill_objective_advances_on_notify_kill() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var o := _obj(&"hunt", 2)
	o.type = QuestObjective.Type.KILL
	o.target_id = &"Raider"
	gs.start_quest(_quest(&"q1", [o]))
	gs.notify_kill(&"Raider")
	assert_eq(gs.objective_progress(&"q1", &"hunt"), 1, "one matching kill -> 1/2")
	gs.notify_kill(&"Bystander")  # non-matching name -> ignored
	assert_eq(gs.objective_progress(&"q1", &"hunt"), 1, "a different name doesn't count")
	gs.notify_kill(&"Raider")
	assert_true(gs.is_quest_completed(&"q1"), "two matching kills complete the hunt")
	gs.free()

func test_pickup_objective_advances_on_notify_pickup() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var o := _obj(&"collect", 2)
	o.type = QuestObjective.Type.PICKUP
	o.target_id = &"keycard"
	gs.start_quest(_quest(&"q1", [o]))
	gs.notify_pickup(&"keycard")
	assert_eq(gs.objective_progress(&"q1", &"collect"), 1, "one matching pickup -> 1/2")
	gs.notify_pickup(&"rock")  # non-matching id -> ignored
	gs.notify_pickup(&"keycard")
	assert_true(gs.is_quest_completed(&"q1"), "two keycards complete the collect objective")
	gs.free()

func test_talk_objective_advances_on_notify_talk() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var o := _obj(&"meet", 1)
	o.type = QuestObjective.Type.TALK
	o.target_id = &"Marko"
	gs.start_quest(_quest(&"q1", [o]))
	gs.notify_talk(&"Stranger")  # a different NPC -> no advance
	assert_false(gs.is_quest_completed(&"q1"), "talking to someone else doesn't advance it")
	gs.notify_talk(&"Marko")
	assert_true(gs.is_quest_completed(&"q1"), "talking to Marko completes the objective")
	gs.free()

func test_enter_area_objective_advances_on_notify_enter() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var o := _obj(&"reach", 1)
	o.type = QuestObjective.Type.ENTER_AREA
	o.target_id = &"market"
	gs.start_quest(_quest(&"q1", [o]))
	gs.notify_enter(&"alley")  # a different area -> no advance
	assert_false(gs.is_quest_completed(&"q1"), "entering a different area doesn't advance it")
	gs.notify_enter(&"market")
	assert_true(gs.is_quest_completed(&"q1"), "entering the target area completes the objective")
	gs.free()

func test_use_item_objective_advances_on_notify_use() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var o := _obj(&"drink", 1)
	o.type = QuestObjective.Type.USE_ITEM
	o.target_id = &"potion"
	gs.start_quest(_quest(&"q1", [o]))
	gs.notify_use(&"potion")
	assert_true(gs.is_quest_completed(&"q1"), "using the target item completes the objective")
	gs.free()

func test_prereq_blocks_start_until_completed() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var q2 := _quest(&"q2", [_obj(&"x", 1)])
	q2.prereq_quest_id = &"q1"
	gs.start_quest(q2)
	assert_false(gs.is_quest_active(&"q2"), "a quest with an unmet prereq won't start")
	gs.start_quest(_quest(&"q1", [_obj(&"y", 1)]))
	gs.complete_quest(&"q1")
	gs.start_quest(q2)
	assert_true(gs.is_quest_active(&"q2"), "once the prereq is completed, the quest starts")
	gs.free()

func test_next_quest_chains_on_complete() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var q2 := _quest(&"q2", [_obj(&"x", 1)])
	var q1 := _quest(&"q1", [_obj(&"y", 1)])
	q1.next_quest = q2
	gs.start_quest(q1)
	gs.complete_quest(&"q1")
	assert_true(gs.is_quest_completed(&"q1"), "q1 completed")
	assert_true(gs.is_quest_active(&"q2"), "completing q1 auto-starts its next_quest (q2)")
	gs.free()


# --- WR-6 follow-up: QuestMarkerSync must drop a FAILED quest's markers --------------------------------------
## Contract: QuestMarkerSync listens to quest_failed the same way it listens to quest_completed. It hard-references
## the GameState AUTOLOAD (not an injected instance), so unlike every test above these use the shared singleton and
## bracket with reset_for_new_game() — the same pattern as test_dialogue's WR-6 selector test. Safe off-tree-ish:
## the autosave GameState queues on a quest change is a no-op with no live Player in the tree.
## The rest of QuestMarkerSync (pure wants_marker, WorldMarker channels) is pinned in test_compass.gd.

const QUEST_MARKER_SYNC_PATH := "res://scripts/components/quest_marker_sync.gd"

## How many markers the sync currently owns. Reads its live `_markers` list rather than counting children: a
## rebuild clears that list SYNCHRONOUSLY while the marker nodes themselves only vanish at the next queue_free
## flush, so this asserts the rebuild without needing to await a frame.
func _marker_count(sync) -> int:
	return sync._markers.size()

func _marker_quest(qid: StringName) -> Quest:
	var o := _obj(&"reach", 1)
	o.show_marker = true
	o.marker_position = Vector3(4.0, 0.0, 7.0)
	return _quest(qid, [o])

func test_marker_sync_drops_markers_when_quest_fails() -> void:
	GameState.reset_for_new_game()
	var sync = load(QUEST_MARKER_SYNC_PATH).new()
	add_child_autofree(sync)  # _ready connects the quest signals and does the first (empty) rebuild
	assert_eq(_marker_count(sync), 0, "no active quests -> no markers")
	var q := _marker_quest(&"rescue")
	q.expire_on_flag = &"hostage_dead"
	GameState.start_quest(q)
	assert_eq(_marker_count(sync), 1, "an active show_marker objective spawns one WorldMarker")
	GameState.set_flag(&"hostage_dead", true)  # expire_on_flag -> fail_quest -> quest_failed
	assert_true(GameState.is_quest_failed(&"rescue"), "the expiry flag really failed the quest")
	assert_eq(_marker_count(sync), 0, "failing the quest removes its markers (no beacon lingering all session)")
	GameState.reset_for_new_game()  # cleanup the shared autoload
	q = null

func test_marker_sync_drops_markers_on_explicit_fail() -> void:
	# The same removal via a direct GameState.fail_quest (a dialogue consequence), not an expire_on_flag.
	GameState.reset_for_new_game()
	var sync = load(QUEST_MARKER_SYNC_PATH).new()
	add_child_autofree(sync)
	var q := _marker_quest(&"courier")
	GameState.start_quest(q)
	assert_eq(_marker_count(sync), 1, "marker up while the quest is active")
	GameState.fail_quest(&"courier")
	assert_eq(_marker_count(sync), 0, "an explicit fail_quest removes the marker too")
	GameState.reset_for_new_game()
	q = null

func test_marker_sync_keeps_other_quests_markers_on_fail() -> void:
	# A rebuild must be a REBUILD, not a blanket clear: failing one quest leaves a sibling quest's marker up.
	GameState.reset_for_new_game()
	var sync = load(QUEST_MARKER_SYNC_PATH).new()
	add_child_autofree(sync)
	GameState.start_quest(_marker_quest(&"doomed"))
	GameState.start_quest(_marker_quest(&"survivor"))
	assert_eq(_marker_count(sync), 2, "two active marker objectives -> two markers")
	GameState.fail_quest(&"doomed")
	assert_eq(_marker_count(sync), 1, "only the failed quest's marker goes; the other survives")
	GameState.reset_for_new_game()
