extends GutTest

## Quest STAGES (QuestStage + Quest.stages + QuestTracker's current stage) and their save field. Sections:
##   1. PRE-REFACTOR CONTRACT, written before QuestStage existed and left unedited after it landed: the two shipped
##      quests under resources/quests/ (both stage-less), driven through the real tracker the way play drives them,
##      plus the [quests_active] record they save. Still green = "a quest with an empty `stages` array behaves
##      exactly as today".
##   2. The pure Quest stage helpers.
##   3. Stage flow on a bare tracker: start in stages[0], hand-off by next_stage_id, terminal stages, jumps
##      (set_quest_stage) and two routes converging, the current-stage-only hooks, the entry effects (back-fill +
##      set_flag_on_enter, each counted once), the dangling-id and loop guards.
##   4. Persistence: the stage round-trips through a real save; a record with no / an unknown stage resumes in
##      stages[0] (the lazy SAVE_VERSION 6 migration).
##   5. The dialogue consequence (DialogueChoice.set_quest_stage_id) and the journal's entry text.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const QUESTTRACKER_PATH := "res://managers/QuestTracker.gd"
const CLEAR_BLOCK := "res://resources/quests/clear_the_block.tres"
const RECOVER := "res://resources/quests/recover_the_package.tres"
const MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"
const JOURNAL_PATH := "res://scripts/ui/quest_journal.gd"
const TMP_SAVE := "user://test_quest_stages_tmp.cfg"
const TMP_QUEST := "user://test_quest_stages_tmp.tres"
## The quest id the dialogue test starts on the QuestTracker AUTOLOAD (the manager calls it directly). Unique, and
## erased again in after_each, so no other test ever sees it.
const AUTOLOAD_QUEST_ID := &"__test_quest_stages_dialogue_jump"


func after_each() -> void:
	for f in [TMP_SAVE, TMP_SAVE + ".bak", TMP_SAVE + ".tmp", TMP_QUEST]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	QuestTracker._quests_active.erase(AUTOLOAD_QUEST_ID)


## A bare GameState wired both ways to its own bare tracker (the test_quests.gd isolation idiom).
func _bare_gs() -> Node:
	var gs = load(GAMESTATE_PATH).new()
	var qt = load(QUESTTRACKER_PATH).new()
	gs.quest_tracker = qt
	qt.game_state = gs
	return gs


func _free_gs(gs: Node) -> void:
	if gs.quest_tracker != null:
		gs.quest_tracker.free()
	gs.free()


func test_clear_the_block_plays_as_a_single_implicit_stage() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	var q := load(CLEAR_BLOCK) as Quest
	assert_not_null(q, "clear_the_block.tres loads as a Quest")
	qt.start_quest(q)
	assert_true(qt.is_quest_active(&"clear_the_block"), "starting it tracks it")
	assert_eq(qt.objective_progress(&"clear_the_block", &"kill_raiders"), 0, "the required kill objective is seeded at 0")
	qt.notify_kill(&"Raider")
	assert_eq(qt.objective_progress(&"clear_the_block", &"kill_raiders"), 1, "a Raider kill ticks it (the legacy display-name match)")
	for i in 3:
		qt.notify_kill(&"Raider")
	assert_true(qt.is_quest_active(&"clear_the_block"), "4/5 kills: still active (the optional vault objective never gates)")
	qt.notify_kill(&"Raider")
	assert_true(qt.is_quest_completed(&"clear_the_block"), "the fifth kill auto-completes it -- the optional reach_vault objective does not block")
	_free_gs(gs)


func test_recover_the_package_waits_for_its_turn_in() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	var q := load(RECOVER) as Quest
	qt.start_quest(q)
	qt.notify_pickup(&"slice_package")
	assert_true(qt.is_objective_done(&"recover_package", &"recover_package"), "picking up the package completes the objective")
	assert_true(qt.is_quest_active(&"recover_package"), "auto_complete is OFF, so the quest waits for its turn-in")
	qt.complete_quest(&"recover_package")
	assert_true(qt.is_quest_completed(&"recover_package"), "the explicit turn-in completes it (the relay terminal's complete_quest_id)")
	_free_gs(gs)


func test_legacy_quest_save_record_is_path_and_progress() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	qt.start_quest(load(CLEAR_BLOCK) as Quest)
	qt.notify_kill(&"Raider")
	var cfg := ConfigFile.new()
	qt.save_into(cfg)
	var rec: Variant = cfg.get_value("quests_active", "clear_the_block", null)
	assert_true(rec is Dictionary, "an active quest writes one record under [quests_active]")
	var keys: Array = (rec as Dictionary).keys()
	keys.sort()
	assert_eq(keys, ["path", "progress"],
		"a quest WITHOUT stages writes exactly {path, progress} -- the shape every save before stages carried, so an old build still reads a new save of a stage-less quest")
	assert_eq(rec["progress"], {"kill_raiders": 1, "reach_vault": 0}, "its progress is keyed by objective id")
	_free_gs(gs)


func test_a_save_written_before_stages_restores_a_legacy_quest() -> void:
	var qt = load(QUESTTRACKER_PATH).new()
	var cfg := ConfigFile.new()
	cfg.set_value("quests_active", "clear_the_block", {"path": CLEAR_BLOCK, "progress": {"kill_raiders": 3}})
	qt.load_from(cfg)
	assert_true(qt.is_quest_active(&"clear_the_block"), "a pre-stages record restores the quest")
	assert_eq(qt.objective_progress(&"clear_the_block", &"kill_raiders"), 3, "with its progress")
	qt.free()


# ---------------------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------------------

func _obj(oid: StringName, cnt := 1, type := QuestObjective.Type.FLAG, target := &"", optional := false) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = oid
	o.required_count = cnt
	o.type = type
	o.target_id = target
	o.optional = optional
	return o


func _stage(sid: StringName, objs: Array, next := &"", flag := &"", journal := "") -> QuestStage:
	var st := QuestStage.new()
	st.id = sid
	for o in objs:
		st.objectives.append(o)
	st.next_stage_id = next
	st.set_flag_on_enter = flag
	st.journal_text = journal
	return st


func _staged(qid: StringName, stages: Array, auto := true) -> Quest:
	var q := Quest.new()
	q.id = qid
	for st in stages:
		q.stages.append(st)
	q.auto_complete = auto
	return q


## The New Vegas shape the stages exist for: a waiting intro beat, two alternative routes, and one later beat both
## routes converge on (by next_stage_id), which is terminal.
func _heist() -> Quest:
	return _staged(&"heist", [
		_stage(&"intro", [], &"", &"heist_offered", "A fixer wants the vault opened."),
		_stage(&"bribe", [_obj(&"pay_guard", 1, QuestObjective.Type.FLAG, &"guard_paid")], &"inside"),
		_stage(&"sneak", [_obj(&"vents", 1, QuestObjective.Type.ENTER_AREA, &"vents")], &"inside"),
		_stage(&"inside", [_obj(&"crack_vault", 1, QuestObjective.Type.FLAG, &"vault_open")], &"", &"", "You're in. Crack it."),
	])


# ---------------------------------------------------------------------------------------------------------------
# 2. Pure Quest helpers
# ---------------------------------------------------------------------------------------------------------------

func test_stage_less_quest_helpers_answer_the_legacy_shape() -> void:
	var q := Quest.new()
	var o := _obj(&"x")
	q.objectives.append(o)
	q.description = "Do the thing."
	assert_false(q.has_stages(), "no stages authored")
	assert_eq(q.first_stage_id(), &"", "a stage-less quest starts in the blank stage")
	assert_eq(q.objectives_for_stage(&""), [o], "its own objectives are the implicit stage")
	assert_eq(q.objectives_for_stage(&"anything"), [o], "whatever stage id is asked for")
	assert_eq(q.all_objectives(), [o], "all_objectives is its own list")
	assert_eq(q.journal_text_for(&""), "Do the thing.", "the journal shows the description")
	assert_null(q.stage_by_id(&"x"), "no stage matches")


func test_staged_quest_helpers() -> void:
	var q := _heist()
	var ignored := _obj(&"ignored")
	q.objectives.append(ignored)  # authored on the Quest itself: IGNORED once stages exist (the Audit warns)
	q.description = "The heist."
	assert_true(q.has_stages(), "stages authored")
	assert_eq(q.first_stage_id(), &"intro", "a staged quest starts in stages[0]")
	assert_eq(q.stage_ids(), [&"intro", &"bribe", &"sneak", &"inside"], "stage ids in authored order")
	assert_eq(q.objectives_for_stage(&"bribe").size(), 1, "a stage answers its own objectives")
	assert_eq(q.objectives_for_stage(&"bribe")[0].id, &"pay_guard", "...and only those")
	assert_true(q.objectives_for_stage(&"nope").is_empty(), "an unknown stage answers NOTHING, never the ignored quest-level objectives")
	assert_false(q.objectives_for_stage(&"").has(ignored), "the blank id on a staged quest is unknown too")
	assert_eq(q.all_objectives().size(), 3, "all_objectives walks every stage (and skips the ignored quest-level list)")
	assert_eq(q.journal_text_for(&"inside"), "You're in. Crack it.", "a stage with journal_text shows it")
	assert_eq(q.journal_text_for(&"bribe"), "The heist.", "a stage with none falls back to the quest description")


# ---------------------------------------------------------------------------------------------------------------
# 3. Stage flow on a bare tracker
# ---------------------------------------------------------------------------------------------------------------

func test_start_puts_a_staged_quest_in_its_first_stage_and_fires_its_entry_flag() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	watch_signals(qt)
	qt.start_quest(_heist())
	assert_true(qt.is_quest_active(&"heist"), "started")
	assert_eq(qt.current_stage_id(&"heist"), &"intro", "in stages[0]")
	assert_eq(qt.current_stage(&"heist").id, &"intro", "current_stage is the QuestStage resource")
	assert_true(qt.current_objectives(&"heist").is_empty(), "the intro is an objective-less waiting beat")
	assert_true(gs.get_flag(&"heist_offered"), "entering the first stage set its set_flag_on_enter")
	assert_signal_emitted(qt, "quest_started", "quest_started still announces the start")
	assert_signal_not_emitted(qt, "quest_stage_changed", "the FIRST stage is not a stage change -- quest_started covers it")
	assert_eq(qt.current_stage_id(&"nope"), &"", "an inactive quest has no current stage")
	assert_null(qt.current_stage(&"nope"), "...and no current QuestStage")
	_free_gs(gs)


## Drive one route through the heist. NOT a loop inside one test: GUT's signal watcher is reset only between tests, and
## watching a tracker that is freed and then watching a fresh one in the SAME test corrupted memory and hung the run
## ("BUG: Unreferenced static string" and no exit). One test per route keeps each watcher on one live object.
func _play_route(route: StringName) -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	qt.start_quest(_heist())
	watch_signals(qt)
	assert_true(qt.set_quest_stage(&"heist", route), "jumping into route %s is accepted" % route)
	assert_eq(qt.current_stage_id(&"heist"), route, "the quest is in %s" % route)
	assert_signal_emitted(qt, "quest_stage_changed", "a jump announces the stage change")
	if route == &"bribe":
		gs.set_flag(&"guard_paid", true)  # the FLAG hook completes the bribe route's one objective
	else:
		qt.notify_enter(&"vents")         # the ENTER_AREA hook completes the sneak route's
	assert_eq(qt.current_stage_id(&"heist"), &"inside", "route %s hands off by next_stage_id to the SAME later stage" % route)
	assert_eq(qt.objective_progress(&"heist", &"crack_vault"), 0, "the new stage's objectives are seeded fresh")
	gs.set_flag(&"vault_open", true)
	assert_true(qt.is_quest_completed(&"heist"), "the terminal stage completes the quest (auto_complete) via route %s" % route)
	_free_gs(gs)


func test_the_bribe_route_converges_on_the_vault() -> void:
	_play_route(&"bribe")


func test_the_sneak_route_converges_on_the_same_vault() -> void:
	_play_route(&"sneak")


func test_a_terminal_stage_waits_for_its_turn_in_when_auto_complete_is_off_but_a_hand_off_does_not() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	var q := _staged(&"turn_in", [
		_stage(&"fetch", [_obj(&"got_it", 1, QuestObjective.Type.PICKUP, &"relic")], &"report"),
		_stage(&"report", [_obj(&"told", 1, QuestObjective.Type.TALK, &"fixer")]),
	], false)
	qt.start_quest(q)
	qt.notify_pickup(&"relic")
	assert_eq(qt.current_stage_id(&"turn_in"), &"report", "a next_stage_id hand-off happens whatever auto_complete says -- that flag governs only the END")
	qt.notify_talk(&"fixer")
	assert_true(qt.is_quest_active(&"turn_in"), "the terminal stage's objectives are done, but auto_complete is OFF: it waits for the turn-in")
	qt.complete_quest(&"turn_in")
	assert_true(qt.is_quest_completed(&"turn_in"), "the explicit turn-in completes it")
	_free_gs(gs)


func test_hooks_only_match_the_current_stage() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	var q := _staged(&"order", [
		_stage(&"first", [_obj(&"a", 1, QuestObjective.Type.PICKUP, &"key")], &"second"),
		_stage(&"second", [_obj(&"b", 1, QuestObjective.Type.KILL, &"boss")]),
	])
	qt.start_quest(q)
	qt.notify_kill(&"boss")
	assert_eq(qt.current_stage_id(&"order"), &"first", "a kill the player is not on yet does nothing")
	qt.advance_objective(&"order", &"b", 1)
	assert_eq(qt.objective_progress(&"order", &"b"), 0, "advance_objective on another stage's objective is a no-op")
	assert_false(qt.is_objective_done(&"order", &"b"), "and it is not done")
	qt.notify_pickup(&"key")
	assert_eq(qt.current_stage_id(&"order"), &"second", "the current stage's pickup moves it on")
	qt.notify_kill(&"boss")
	assert_true(qt.is_quest_completed(&"order"), "now the kill counts")
	_free_gs(gs)


func test_one_event_never_ticks_a_same_id_objective_in_the_stage_it_just_entered() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	var q := _staged(&"repeat", [
		_stage(&"round_1", [_obj(&"hit", 1, QuestObjective.Type.KILL, &"dummy")], &"round_2"),
		_stage(&"round_2", [_obj(&"hit", 2, QuestObjective.Type.KILL, &"dummy")]),
	])
	qt.start_quest(q)
	qt.notify_kill(&"dummy")
	assert_eq(qt.current_stage_id(&"repeat"), &"round_2", "the first kill completed round 1")
	assert_eq(qt.objective_progress(&"repeat", &"hit"), 0,
		"...and did NOT also tick round 2's objective of the same id -- the hook's walk stops when the stage changes (the epoch guard)")
	_free_gs(gs)


func test_entering_a_stage_back_fills_an_already_set_flag_and_can_chain() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	gs.set_flag(&"door_open", true)  # flipped long before the quest reaches the stage that waits on it
	var q := _staged(&"chain", [
		_stage(&"start", [_obj(&"go", 1, QuestObjective.Type.ENTER_AREA, &"lobby")], &"door"),
		_stage(&"door", [_obj(&"opened", 1, QuestObjective.Type.FLAG, &"door_open")], &"beyond"),
		_stage(&"beyond", [_obj(&"loot", 1, QuestObjective.Type.PICKUP, &"cash")]),
	])
	qt.start_quest(q)
	qt.notify_enter(&"lobby")
	assert_eq(qt.current_stage_id(&"chain"), &"beyond",
		"entering 'door' back-filled its already-set flag, which completed it and chained straight on to 'beyond'")
	_free_gs(gs)


func test_set_flag_on_enter_ticks_a_matching_objective_exactly_once() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	var q := _staged(&"once", [
		_stage(&"a", [_obj(&"go", 1, QuestObjective.Type.PICKUP, &"map")], &"b"),
		_stage(&"b", [_obj(&"marked", 2, QuestObjective.Type.FLAG, &"b_reached")], &"", &"b_reached"),
	])
	qt.start_quest(q)
	qt.notify_pickup(&"map")
	assert_eq(qt.current_stage_id(&"once"), &"b", "moved on")
	assert_eq(qt.objective_progress(&"once", &"marked"), 1,
		"the stage's own set_flag_on_enter ticked its FLAG objective ONCE (set_flag notifies; the back-fill ran first and saw it unset)")
	_free_gs(gs)


func test_set_quest_stage_refusals() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	assert_false(qt.set_quest_stage(&"heist", &"bribe"), "an inactive quest is refused")
	qt.start_quest(_heist())
	assert_false(qt.set_quest_stage(&"heist", &"vault_room"), "a stage id the quest does not have is refused (warned; the Audit reports it)")
	assert_eq(qt.current_stage_id(&"heist"), &"intro", "and the quest stays where it was")
	assert_true(qt.set_quest_stage(&"heist", &"bribe"), "a real stage is accepted")
	watch_signals(qt)
	assert_true(qt.set_quest_stage(&"heist", &"bribe"), "re-entering the stage it is ALREADY in answers true")
	assert_signal_not_emitted(qt, "quest_stage_changed", "...as a no-op: no stage change, no progress reset")
	var plain := Quest.new()
	plain.id = &"plain"
	plain.objectives.append(_obj(&"x"))
	qt.start_quest(plain)
	assert_false(qt.set_quest_stage(&"plain", &"x"), "a stage-less quest has no stages to jump to")
	assert_eq(qt.current_stage_id(&"plain"), &"", "a stage-less quest's stage is blank")
	_free_gs(gs)


func test_a_dangling_next_stage_id_leaves_the_quest_in_place_instead_of_completing_it() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	var q := _staged(&"broken", [_stage(&"only", [_obj(&"x", 1, QuestObjective.Type.PICKUP, &"coin")], &"gone")])
	qt.start_quest(q)
	qt.notify_pickup(&"coin")
	assert_true(qt.is_quest_active(&"broken"), "a next_stage_id naming no stage never completes the quest by mistake (no rewards)")
	assert_eq(qt.current_stage_id(&"broken"), &"only", "it stays in the stage (warned)")
	_free_gs(gs)


func test_a_next_stage_loop_of_instantly_complete_stages_is_stopped() -> void:
	var gs = _bare_gs()
	var qt = gs.quest_tracker
	gs.set_flag(&"always", true)
	var q := _staged(&"loop", [
		_stage(&"kick", [_obj(&"start", 1, QuestObjective.Type.PICKUP, &"trigger")], &"ping"),
		_stage(&"ping", [_obj(&"p", 1, QuestObjective.Type.FLAG, &"always")], &"pong"),
		_stage(&"pong", [_obj(&"q", 1, QuestObjective.Type.FLAG, &"always")], &"ping"),
	])
	qt.start_quest(q)
	qt.notify_pickup(&"trigger")
	assert_true(qt.is_quest_active(&"loop"), "the loop guard stopped the recursion -- no stack overflow, the quest is still active")
	assert_eq(qt._stage_entry_depth, 0, "and the nesting counter unwound fully")
	_free_gs(gs)


# ---------------------------------------------------------------------------------------------------------------
# 4. Persistence
# ---------------------------------------------------------------------------------------------------------------

func test_the_current_stage_round_trips_through_a_real_save() -> void:
	ResourceSaver.save(_heist(), TMP_QUEST)  # persistence keys by resource_path
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(load(TMP_QUEST) as Quest)
	gs._qt().set_quest_stage(&"heist", &"inside")
	var cfg := ConfigFile.new()
	gs._qt().save_into(cfg)
	var rec: Dictionary = cfg.get_value("quests_active", "heist", {})
	assert_eq(rec.get("stage", ""), "inside", "a staged quest's record carries its current stage id")
	assert_eq(rec.get("progress", {}), {"crack_vault": 0}, "beside the progress of THAT stage only")
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	gs2.load_from_disk(TMP_SAVE)
	assert_eq(gs2.save_version, GameState.SAVE_VERSION, "the save stamps the current schema")
	assert_gte(GameState.SAVE_VERSION, 6, "stages are SAVE_VERSION 6")
	assert_true(gs2.is_quest_active(&"heist"), "the quest restores")
	assert_eq(gs2._qt().current_stage_id(&"heist"), &"inside", "IN the stage it was saved in")
	assert_eq(gs2.objective_progress(&"heist", &"crack_vault"), 0, "with that stage's progress")
	gs2.set_flag(&"vault_open", true)
	assert_true(gs2.is_quest_completed(&"heist"), "and it plays on from there")
	gs.free()
	gs2.free()


func test_a_record_without_a_stage_resumes_in_the_first_stage() -> void:
	ResourceSaver.save(_heist(), TMP_QUEST)
	for rec in [
		{"path": TMP_QUEST, "progress": {}},  # a <v6 save, or a save made before this quest GAINED stages
		{"path": TMP_QUEST, "progress": {}, "stage": "renamed_since"},  # a stage renamed / deleted after the save
	]:
		var qt = load(QUESTTRACKER_PATH).new()
		var cfg := ConfigFile.new()
		cfg.set_value("quests_active", "heist", rec)
		qt.load_from(cfg)
		assert_true(qt.is_quest_active(&"heist"), "the quest restores (%s)" % str(rec.keys()))
		assert_eq(qt.current_stage_id(&"heist"), &"intro", "and resumes in stages[0] -- the lazy v6 migration (%s)" % str(rec.get("stage", "no stage field")))
		qt.free()


func test_a_stage_field_on_a_stage_less_quest_is_ignored() -> void:
	var qt = load(QUESTTRACKER_PATH).new()
	var cfg := ConfigFile.new()
	cfg.set_value("quests_active", "clear_the_block", {"path": CLEAR_BLOCK, "progress": {"kill_raiders": 2}, "stage": "junk"})
	qt.load_from(cfg)
	assert_eq(qt.current_stage_id(&"clear_the_block"), &"", "a stage-less quest has no stage, whatever the record says")
	assert_eq(qt.objective_progress(&"clear_the_block", &"kill_raiders"), 2, "and its progress restores untouched")
	qt.free()


# ---------------------------------------------------------------------------------------------------------------
# 5. The dialogue consequence + the journal entry
# ---------------------------------------------------------------------------------------------------------------

func test_dialogue_choice_set_quest_stage_id_defaults_blank() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.set_quest_stage_id, &"", "set_quest_stage_id defaults blank -- no jump, so every existing conversation is unchanged")
	assert_eq(typeof(c.set_quest_stage_id), TYPE_STRING_NAME, "a StringName, like every id field beside it")


func test_a_picked_choice_jumps_the_quest_it_names_to_a_stage() -> void:
	# DialogueManager calls the QuestTracker AUTOLOAD directly, so this one test drives the singleton. Safe: the quest
	# id is unique and erased in after_each, no stage sets a flag, and an autosave needs a live player (none in GUT).
	var q := _staged(AUTOLOAD_QUEST_ID, [_stage(&"wait", []), _stage(&"route_b", [_obj(&"x")])])
	QuestTracker.start_quest(q)
	var m = load(MANAGER_PATH).new()
	var choice := DialogueChoice.new()
	choice.advance_quest_id = AUTOLOAD_QUEST_ID
	choice.set_quest_stage_id = &"route_b"
	m._apply_choice_effects(choice)
	assert_eq(QuestTracker.current_stage_id(AUTOLOAD_QUEST_ID), &"route_b", "the choice jumped the quest named by advance_quest_id to the stage")
	var no_quest := DialogueChoice.new()
	no_quest.set_quest_stage_id = &"wait"
	m._apply_choice_effects(no_quest)
	assert_eq(QuestTracker.current_stage_id(AUTOLOAD_QUEST_ID), &"route_b", "a stage id with no advance_quest_id does nothing (the Audit reports it)")
	m.free()


func test_journal_entry_is_the_stage_text_else_the_description() -> void:
	var J = load(JOURNAL_PATH)
	var q := _heist()
	q.description = "The heist."
	assert_eq(J.summary_text(q, &"intro"), "A fixer wants the vault opened.", "a stage's journal_text is the entry")
	assert_eq(J.summary_text(q, &"sneak"), "The heist.", "a stage without one shows the quest description")
	assert_eq(J.summary_text(null, &""), "", "no quest, no entry")
	var plain := Quest.new()
	plain.objectives.append(_obj(&"x"))
	assert_eq(J.closed_objectives(plain).size(), 1, "a closed stage-less quest still lists its objectives")
	assert_true(J.closed_objectives(q).is_empty(), "a closed staged quest lists none (its past beats are not tracked)")
