extends GutTest

## Quest Edit dock: PURE ops on quest_edit_ops.gd (add / remove / move objective) tested on throwaway Quest.new()s
## with NO disk write and NO EditorInterface — exactly the code path a dock button uses MINUS ResourceSaver.save().
## Also a construct smoke test: instantiating the dock Control forces GDScript to compile the WHOLE editor script,
## catching errors --import misses for addon-only scripts. Per CLAUDE.md, resources are .new() then released = null.

const QuestOps := preload("res://addons/cybersunday_tools/dock_quest/quest_edit_ops.gd")
const QuestEditor := preload("res://addons/cybersunday_tools/dock_quest/quest_editor.gd")


func _quest_with(n: int) -> Quest:
	var q := Quest.new()
	q.id = &"test_quest"
	for i in n:
		var o := QuestObjective.new()
		o.id = StringName("obj_%d" % (i + 1))
		o.target_id = StringName("tgt_%d" % (i + 1))
		q.objectives.append(o)
	return q


# --- construct smoke -------------------------------------------------------------------------------------------

func test_quest_editor_constructs() -> void:
	var d = QuestEditor.new()
	assert_not_null(d, "quest editor should construct (compiles + builds its widgets off-tree)")
	assert_eq(d.name, "Quest Edit", "dock tab name")
	d.free()


# --- add_objective ---------------------------------------------------------------------------------------------

func test_add_objective_appends_and_returns_true() -> void:
	var q := _quest_with(0)
	assert_true(QuestOps.add_objective(q), "add returns true on success")
	assert_eq(q.objectives.size(), 1, "one objective appended")
	q = null

func test_add_objective_seeds_a_flag_objective() -> void:
	var q := _quest_with(0)
	QuestOps.add_objective(q)
	var o: QuestObjective = q.objectives[0]
	assert_eq(o.type, QuestObjective.Type.FLAG, "new objective defaults to FLAG (no target registry needed)")
	assert_eq(o.required_count, 1, "new objective requires 1")
	assert_eq(String(o.id), "obj_1", "first new objective gets the stable id obj_1")
	q = null

func test_add_objective_ids_are_unique() -> void:
	var q := _quest_with(0)
	QuestOps.add_objective(q)
	QuestOps.add_objective(q)
	QuestOps.add_objective(q)
	var ids := {}
	for o in q.objectives:
		ids[String(o.id)] = true
	assert_eq(ids.size(), 3, "three distinct objective ids (obj_1/obj_2/obj_3)")
	q = null

func test_add_objective_id_fills_lowest_free_after_remove() -> void:
	var q := _quest_with(0)
	QuestOps.add_objective(q)  # obj_1
	QuestOps.add_objective(q)  # obj_2
	QuestOps.remove_objective(q, 0)  # drop obj_1, leaving obj_2
	QuestOps.add_objective(q)  # should re-use obj_1 (lowest free), not collide
	var ids := {}
	for o in q.objectives:
		ids[String(o.id)] = true
	assert_true(ids.has("obj_1"), "re-add fills the freed obj_1")
	assert_true(ids.has("obj_2"), "obj_2 still present")
	assert_eq(ids.size(), 2, "no duplicate ids after re-add")
	q = null

func test_add_objective_noops_on_null() -> void:
	assert_false(QuestOps.add_objective(null), "null quest is a no-op returning false")


# --- remove_objective ------------------------------------------------------------------------------------------

func test_remove_objective_removes_the_right_one() -> void:
	var q := _quest_with(3)  # tgt_1, tgt_2, tgt_3
	assert_true(QuestOps.remove_objective(q, 1), "remove returns true")
	assert_eq(q.objectives.size(), 2, "two objectives left")
	assert_eq(String(q.objectives[0].target_id), "tgt_1", "first survives")
	assert_eq(String(q.objectives[1].target_id), "tgt_3", "third shifts down to index 1")
	q = null

func test_remove_objective_noops_out_of_range() -> void:
	var q := _quest_with(2)
	assert_false(QuestOps.remove_objective(q, 2), "index == size is out of range")
	assert_false(QuestOps.remove_objective(q, -1), "negative index is out of range")
	assert_eq(q.objectives.size(), 2, "no objective removed by an out-of-range index")
	q = null

func test_remove_objective_noops_on_null() -> void:
	assert_false(QuestOps.remove_objective(null, 0), "null quest is a no-op returning false")


# --- move_objective --------------------------------------------------------------------------------------------

func test_move_objective_up() -> void:
	var q := _quest_with(3)  # tgt_1, tgt_2, tgt_3
	assert_true(QuestOps.move_objective(q, 2, -1), "moving index 2 up returns true")
	assert_eq(String(q.objectives[1].target_id), "tgt_3", "tgt_3 moved to index 1")
	assert_eq(String(q.objectives[2].target_id), "tgt_2", "tgt_2 pushed to index 2")
	q = null

func test_move_objective_down() -> void:
	var q := _quest_with(3)  # tgt_1, tgt_2, tgt_3
	assert_true(QuestOps.move_objective(q, 0, 1), "moving index 0 down returns true")
	assert_eq(String(q.objectives[0].target_id), "tgt_2", "tgt_2 moved to index 0")
	assert_eq(String(q.objectives[1].target_id), "tgt_1", "tgt_1 pushed to index 1")
	q = null

func test_move_objective_off_top_is_noop() -> void:
	var q := _quest_with(3)
	assert_false(QuestOps.move_objective(q, 0, -1), "can't move the first objective up")
	assert_eq(String(q.objectives[0].target_id), "tgt_1", "order unchanged")
	q = null

func test_move_objective_off_bottom_is_noop() -> void:
	var q := _quest_with(3)
	assert_false(QuestOps.move_objective(q, 2, 1), "can't move the last objective down")
	assert_eq(String(q.objectives[2].target_id), "tgt_3", "order unchanged")
	q = null

func test_move_objective_rejects_bad_direction() -> void:
	var q := _quest_with(3)
	assert_false(QuestOps.move_objective(q, 1, 0), "dir 0 is rejected")
	assert_false(QuestOps.move_objective(q, 1, 2), "dir 2 (not a single step) is rejected")
	assert_eq(String(q.objectives[1].target_id), "tgt_2", "order unchanged by a bad direction")
	q = null

func test_move_objective_noops_out_of_range_index() -> void:
	var q := _quest_with(2)
	assert_false(QuestOps.move_objective(q, 5, -1), "out-of-range index is a no-op")
	assert_false(QuestOps.move_objective(q, -1, 1), "negative index is a no-op")
	q = null

func test_move_objective_noops_on_null() -> void:
	assert_false(QuestOps.move_objective(null, 0, 1), "null quest is a no-op returning false")


# --- size sanity (assert_lte / assert_gte, NOT le/ge) ---------------------------------------------------------

func test_objective_count_bounds_after_ops() -> void:
	var q := _quest_with(1)
	QuestOps.add_objective(q)
	QuestOps.add_objective(q)
	assert_gte(q.objectives.size(), 1, "at least one objective remains")
	assert_lte(q.objectives.size(), 3, "no more than the three we have")
	q = null
