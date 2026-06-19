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
