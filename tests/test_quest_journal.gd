extends GutTest

## Slice 6c (quest journal): the pure objective-line formatter (built off a bare journal instance) + the
## GameState journal getters (active_quest / completed_quests). The screen UI itself — open/close, tab strip,
## rendering — is playtest-verified per the in-tree-behaviour convention.

const JOURNAL_PATH := "res://scripts/ui/quest_journal.gd"
const GAMESTATE_PATH := "res://managers/GameState.gd"

func _obj(oid: StringName, desc := "", cnt := 1, optional := false) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = oid
	o.description = desc
	o.required_count = cnt
	o.optional = optional
	return o

func test_objective_line_formatting() -> void:
	var j = load(JOURNAL_PATH).new()
	assert_eq(j.objective_line(_obj(&"o", "Kill the boss"), false, 0), "[ ] Kill the boss", "open single objective")
	assert_eq(j.objective_line(_obj(&"o", "Kill the boss"), true, 1), "[x] Kill the boss", "done -> checked box")
	assert_eq(j.objective_line(_obj(&"o", "Collect parts", 5), false, 2), "[ ] Collect parts (2/5)", "a counted objective shows progress")
	assert_eq(j.objective_line(_obj(&"o", "Find the cache", 1, true), false, 0), "[ ] Find the cache  (optional)", "optional tag")
	assert_eq(j.objective_line(_obj(&"reach_exit", "", 1), false, 0), "[ ] reach_exit", "falls back to the id when no description")
	j.free()

func test_active_and_completed_getters() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var q := Quest.new()
	q.id = &"q1"
	q.title = "The Job"
	q.objectives.append(_obj(&"x", "do it"))
	gs.start_quest(q)
	assert_eq(gs.active_quest(&"q1"), q, "active_quest returns the live Quest")
	assert_null(gs.active_quest(&"nope"), "an unknown id -> null")
	assert_true(gs.completed_quests().is_empty(), "nothing completed yet")
	gs.advance_objective(&"q1", &"x", 1)  # auto-completes
	assert_null(gs.active_quest(&"q1"), "no longer active once complete")
	var done: Array = gs.completed_quests()
	assert_eq(done.size(), 1, "one completed quest")
	assert_eq(done[0].title, "The Job", "the completed quest retains its title for the journal")
	gs.free()
