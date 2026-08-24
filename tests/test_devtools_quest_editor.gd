extends GutTest

## Quest Edit dock: the PURE ops on quest_edit_ops.gd — add / remove / move OBJECTIVE, add / remove / move REWARD
## row, and `normalize` — tested on throwaway Quest.new()s with NO disk write and NO EditorInterface: exactly the
## code path a dock button takes MINUS ResourceSaver.save().
##
## Also a construct smoke test: instantiating the dock Control forces GDScript to compile the WHOLE editor script,
## catching errors --import misses for addon-only scripts. With the Control built, four more checks are cheap here
## and otherwise cost a live editor session to find:
##   * every widget the ROUND-TRIP (three-site) rule depends on was actually BUILT in _init — a var declared and
##     never assigned reads as null and crashes _load_quest the first time a designer opens the tab;
##   * each of those widgets landed INSIDE the tab's ScrollContainer — the bottom-panel TabContainer sizes to its
##     TALLEST tab, and this plugin has twice shipped a tab that grew past the panel and made the editor unusable;
##   * `_clear_loaded` — the RESET site of the three-site rule — puts every widget back to its RESOURCE default
##     rather than its widget default, `auto_complete` back to TRUE being the one that cannot be faked; and
##   * `_reward_summary` marks a 0-count row as skipped, and ONLY a 0-count row.
## PUSH site 1 (`_load_quest`) is deliberately NOT here: it needs a real .tres off disk, so it is covered by the
## value-round-trip rows in docs/CYBER_SUNDAY_PLUGIN_QA.md instead of by a fixture this suite would have to author.
##
## Per CLAUDE.md, Resources are .new() then released with `= null`; Nodes are .new() + .free().
## GUT here has assert_lte / assert_gte, never assert_le / assert_ge.

const QuestOps := preload("res://addons/cybersunday_tools/dock_quest/quest_edit_ops.gd")
const QuestEditor := preload("res://addons/cybersunday_tools/dock_quest/quest_editor.gd")

## The widgets Phase 2 added to the tab, by PROPERTY NAME (read through Object.get, see the smoke below). These are
## the ones whose absence is invisible until a designer loads a quest: the flow flags, the reward row block, and the
## per-objective marker group.
const PHASE2_WIDGETS := [
	"_auto_complete_chk",
	"_expire_edit",
	"_reward_list",
	"_reward_item_pick",
	"_reward_count",
	"_obj_show_marker",
	"_obj_marker_x",
	"_obj_marker_y",
	"_obj_marker_z",
]


func _quest_with(n: int) -> Quest:
	var q := Quest.new()
	q.id = &"test_quest"
	for i in n:
		var o := QuestObjective.new()
		o.id = StringName("obj_%d" % (i + 1))
		o.target_id = StringName("tgt_%d" % (i + 1))
		q.objectives.append(o)
	return q


## `n` reward rows whose COUNT is the row marker (row i has count i + 1), so the ordering tests below can read the
## list back without an Item. `item` stays null on purpose: none of the reward ops touch it, and loading real Item
## .tres files would drag the whole item pipeline into a test of three array mutations. Built by hand rather than
## through QuestOps.add_reward so the remove/move tests never depend on the op they are not testing.
func _quest_with_rewards(n: int) -> Quest:
	var q := Quest.new()
	q.id = &"test_quest"
	for i in n:
		var s := ItemStack.new()
		s.item = null
		s.count = i + 1
		q.rewards.append(s)
	return q


## True when `w` sits somewhere under a ScrollContainer inside `root` — the tab's HEIGHT POLICY, made checkable
## off-tree. Walks parents rather than searching children so it answers the question that actually matters ("is this
## row inside the scroll?") instead of "does the tab own a scroll somewhere?". A null widget answers false, which
## reads as a plain assert failure rather than an engine error.
func _inside_scroll(root: Node, w: Node) -> bool:
	var n: Node = w
	while n != null and n != root:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


# --- construct smoke -------------------------------------------------------------------------------------------

func test_quest_editor_constructs() -> void:
	var d = QuestEditor.new()
	assert_not_null(d, "quest editor should construct (compiles + builds its widgets off-tree)")
	assert_eq(d.name, "Quest Edit", "dock tab name")
	d.free()

func test_quest_editor_builds_every_phase2_widget() -> void:
	var d = QuestEditor.new()
	for prop: String in PHASE2_WIDGETS:
		# Object.get() rather than d.<prop>: a RENAMED field then reads back as null — a readable assert failure —
		# instead of an "invalid get index" engine error, which GUT 9.6 fails the test on before printing anything useful.
		assert_not_null(d.get(StringName(prop)), "%s must be built in _init; a null widget crashes _load_quest on the first open" % prop)
	d.free()

func test_phase2_widgets_live_inside_the_scroll_container() -> void:
	var d = QuestEditor.new()
	for prop: String in PHASE2_WIDGETS:
		var w = d.get(StringName(prop))
		assert_true(_inside_scroll(d, w), "%s must sit INSIDE the tab's ScrollContainer — the bottom-panel TabContainer sizes to its tallest tab" % prop)
	d.free()

## The reward row's list text. item_stack.gd documents count 0 as "skip this row", so a 0 has to LOOK deliberate in
## the list instead of reading as a normal reward that silently hands nothing over. `_reward_summary` is a PINNED
## name here (it is pure — a null item short-circuits, and a real one only reaches LootEditor._item_label, which is
## itself a pure static: no tree, no scan, no EditorInterface); rename it and rename it in this test too.
func test_reward_summary_calls_out_a_zero_count() -> void:
	var d = QuestEditor.new()
	var s := ItemStack.new()
	s.count = 2
	# NOTE: assert_string_contains(text, search, match_case) takes NO message argument — a third string would land
	# in match_case and vanish from the output. GUT prints the got/expected pair itself.
	var normal: String = d._reward_summary(0, s)
	assert_string_contains(normal, "×2")
	# The ABSENCE half, and it carries the whole meaning: a _reward_summary that stamped "(skipped)" on EVERY row
	# would still satisfy the zero case below while telling a designer nothing, because the tell only reads as
	# deliberate if it is rare. GUT has no negative twin for assert_string_contains, so this is String.contains.
	assert_false(normal.contains("(skipped)"), "a POSITIVE count must not be marked skipped — a marker on every row is no marker at all")
	s.count = 0
	assert_string_contains(d._reward_summary(0, s), "(skipped)")
	assert_string_contains(d._reward_summary(0, null), "<null>")
	s = null
	d.free()


## The RESET site of the three-site rule, checkable off-tree because _clear_loaded only pushes constants into
## widgets — no disk, no EditorInterface, no tree. Every widget is DIRTIED first on purpose: "resets to
## blank / false / zero" would otherwise pass on a _clear_loaded that does nothing at all, since blank/false/zero
## ARE the construction defaults. `auto_complete` is the assertion that cannot be faked in either direction —
## quest.gd:27 defaults TRUE while a CheckBox defaults false, so only a real reset-to-the-RESOURCE-default leaves it
## pressed, and the "tidy" version of this line (reset to false) fails loudly instead of shipping.
func test_clear_loaded_resets_to_the_resource_defaults() -> void:
	var d = QuestEditor.new()
	d._auto_complete_chk.set_pressed_no_signal(false)
	d._expire_edit.text = "hostage_died"
	d._reward_list.add_item("a row belonging to the PREVIOUS quest")
	d._obj_show_marker.set_pressed_no_signal(true)
	d._obj_marker_x.set_value_no_signal(3.0)
	d._obj_marker_y.set_value_no_signal(0.5)
	d._obj_marker_z.set_value_no_signal(-12.0)
	d._clear_loaded()
	assert_true(d._auto_complete_chk.button_pressed, "auto_complete resets to the RESOURCE default (quest.gd:27 is true), never to the CheckBox's own false")
	assert_eq(d._expire_edit.text, "", "the expire flag is blanked, not carried into whatever loads next")
	assert_eq(d._reward_list.item_count, 0, "the previous quest's reward rows are cleared — a leftover row aims the item picker at a FOREIGN ItemStack")
	assert_true(d._reward_item_pick.disabled, "with no row loaded the item picker is disabled, so a stray pick has nothing to clobber")
	assert_false(d._reward_count.editable, "with no row loaded the count spin is read-only")
	assert_false(d._obj_show_marker.button_pressed, "the per-objective editor is reset alongside the headline, not left on the last objective")
	# assert_almost_eq, not assert_eq: Range snaps every value onto its step grid measured from min_value (-9999 at
	# step 0.01 here), so betting on an exact 0.0 would be betting on double-rounding rather than on the reset.
	assert_almost_eq(d._obj_marker_x.value, 0.0, 0.0001, "marker X back to QuestObjective's Vector3.ZERO default")
	assert_almost_eq(d._obj_marker_y.value, 0.0, 0.0001, "marker Y back to QuestObjective's Vector3.ZERO default")
	assert_almost_eq(d._obj_marker_z.value, 0.0, 0.0001, "marker Z back to QuestObjective's Vector3.ZERO default")
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
	var q := _quest_with(2)  # tgt_1, tgt_2
	assert_false(QuestOps.move_objective(q, 5, -1), "an index far past the end is a no-op")
	assert_false(QuestOps.move_objective(q, 2, -1), "index == size is out of range — the exact off-by-one the `index >= n` guard exists for")
	assert_false(QuestOps.move_objective(q, -1, 1), "negative index is a no-op")
	# ORDER, not size: a move can never change the size, so size() == 2 would pass on a refused index that quietly
	# wrapped to row 0 and swapped the list anyway.
	assert_eq(String(q.objectives[0].target_id), "tgt_1", "order unchanged by three refused moves")
	assert_eq(String(q.objectives[1].target_id), "tgt_2", "order unchanged by three refused moves")
	q = null

func test_move_objective_noops_on_null() -> void:
	assert_false(QuestOps.move_objective(null, 0, 1), "null quest is a no-op returning false")


# --- add_reward ------------------------------------------------------------------------------------------------
# Quest.rewards is an Array[ItemStack] granted on completion. Same bool-returning, bounds-guarded convention as the
# objective ops above (NOT loot_edit_ops' int-returning add_entry), so these mirror the blocks above deliberately.

func test_add_reward_appends_and_returns_true() -> void:
	var q := _quest_with_rewards(0)
	assert_true(QuestOps.add_reward(q), "add returns true on success")
	assert_eq(q.rewards.size(), 1, "one reward row appended")
	q = null

func test_add_reward_seeds_an_empty_row_of_one() -> void:
	var q := _quest_with_rewards(0)
	QuestOps.add_reward(q)
	var row = q.rewards[0]
	assert_not_null(row, "the appended row is a real object, not a null hole in the array")
	# assert_is, not String(row) — the point here IS the type. String() coerces anything and would pass on a
	# LootEntry, a Dictionary, or a freed object.
	assert_is(row, ItemStack, "a reward row is an ItemStack (what ItemStack.seed_into walks on completion)")
	assert_null(row.item, "a fresh row has NO item yet — seed_into skips a null-item row rather than erroring")
	assert_eq(row.count, 1, "count seeds to 1, not 0: item_stack.gd documents 0 as 'skip the row'")
	q = null

func test_add_reward_twice_gives_two_rows() -> void:
	var q := _quest_with_rewards(0)
	QuestOps.add_reward(q)
	QuestOps.add_reward(q)
	assert_eq(q.rewards.size(), 2, "two adds append two independent rows")
	assert_not_same(q.rewards[0], q.rewards[1], "each add makes its OWN ItemStack — a shared one would edit both rows at once")
	q = null

func test_add_reward_noops_on_null() -> void:
	assert_false(QuestOps.add_reward(null), "null quest is a no-op returning false")


# --- remove_reward ---------------------------------------------------------------------------------------------

func test_remove_reward_removes_the_right_one() -> void:
	var q := _quest_with_rewards(3)  # counts 1, 2, 3
	assert_true(QuestOps.remove_reward(q, 1), "remove returns true")
	assert_eq(q.rewards.size(), 2, "two reward rows left")
	assert_eq(q.rewards[0].count, 1, "first survives")
	assert_eq(q.rewards[1].count, 3, "third shifts down to index 1")
	q = null

func test_remove_reward_noops_out_of_range() -> void:
	var q := _quest_with_rewards(2)
	assert_false(QuestOps.remove_reward(q, 2), "index == size is out of range")
	assert_false(QuestOps.remove_reward(q, -1), "negative index is out of range")
	assert_eq(q.rewards.size(), 2, "no row removed by an out-of-range index (a stale ItemList selection must not delete)")
	q = null

func test_remove_reward_noops_on_null() -> void:
	assert_false(QuestOps.remove_reward(null, 0), "null quest is a no-op returning false")


# --- move_reward -----------------------------------------------------------------------------------------------

func test_move_reward_up() -> void:
	var q := _quest_with_rewards(3)  # counts 1, 2, 3
	assert_true(QuestOps.move_reward(q, 2, -1), "moving index 2 up returns true")
	assert_eq(q.rewards[1].count, 3, "row 3 moved to index 1")
	assert_eq(q.rewards[2].count, 2, "row 2 pushed to index 2")
	q = null

func test_move_reward_down() -> void:
	var q := _quest_with_rewards(3)  # counts 1, 2, 3
	assert_true(QuestOps.move_reward(q, 0, 1), "moving index 0 down returns true")
	assert_eq(q.rewards[0].count, 2, "row 2 moved to index 0")
	assert_eq(q.rewards[1].count, 1, "row 1 pushed to index 1")
	q = null

func test_move_reward_off_top_is_noop() -> void:
	var q := _quest_with_rewards(3)
	assert_false(QuestOps.move_reward(q, 0, -1), "can't move the first row up")
	assert_eq(q.rewards[0].count, 1, "order unchanged")
	q = null

func test_move_reward_off_bottom_is_noop() -> void:
	var q := _quest_with_rewards(3)
	assert_false(QuestOps.move_reward(q, 2, 1), "can't move the last row down")
	assert_eq(q.rewards[2].count, 3, "order unchanged")
	q = null

func test_move_reward_rejects_bad_direction() -> void:
	var q := _quest_with_rewards(3)
	assert_false(QuestOps.move_reward(q, 1, 0), "dir 0 is rejected")
	assert_false(QuestOps.move_reward(q, 1, 2), "dir 2 (not a single step) is rejected")
	assert_eq(q.rewards[1].count, 2, "order unchanged by a bad direction")
	q = null

func test_move_reward_noops_out_of_range_index() -> void:
	var q := _quest_with_rewards(2)  # counts 1, 2
	assert_false(QuestOps.move_reward(q, 5, -1), "an index far past the end is a no-op")
	assert_false(QuestOps.move_reward(q, 2, -1), "index == size is out of range — the exact off-by-one the `index >= n` guard exists for")
	assert_false(QuestOps.move_reward(q, -1, 1), "negative index is a no-op")
	# ORDER, not size, for the same reason as the objective mirror above: a move can never change the size, so
	# size() == 2 is a vacuous assertion here. The counts ARE the row identity (see _quest_with_rewards).
	assert_eq(q.rewards[0].count, 1, "row 1 still first after three refused moves")
	assert_eq(q.rewards[1].count, 2, "row 2 still second")
	q = null

func test_move_reward_noops_on_null() -> void:
	assert_false(QuestOps.move_reward(null, 0, 1), "null quest is a no-op returning false")


# --- normalize -------------------------------------------------------------------------------------------------
# The drift these repair is SILENT at runtime: every one of these ids is compared by exact StringName equality, so a
# single stray space makes a perfectly authored-looking quest do nothing at all. normalize returns the COUNT of
# fields it repaired (not a bool) because the dock reports that number on its status line.

func test_normalize_trims_an_objective_target_id() -> void:
	var q := _quest_with(1)
	q.objectives[0].target_id = &" raider "
	assert_eq(QuestOps.normalize(q), 1, "one repaired field")
	assert_eq(String(q.objectives[0].target_id), "raider", "a padded target_id never matches a kill/pickup/talk event")
	q = null

func test_normalize_trims_an_objective_id() -> void:
	var q := _quest_with(1)
	q.objectives[0].id = &"  obj_1"
	assert_eq(QuestOps.normalize(q), 1, "one repaired field")
	assert_eq(String(q.objectives[0].id), "obj_1", "the progress Dictionary is keyed by this id — padded, advance addresses a key that was never seeded")
	q = null

func test_normalize_trims_the_prereq_and_expire_ids() -> void:
	var q := _quest_with(0)
	q.prereq_quest_id = &"intro_job "
	q.expire_on_flag = &" hostage_died"
	assert_eq(QuestOps.normalize(q), 2, "two repaired fields")
	assert_eq(String(q.prereq_quest_id), "intro_job", "a padded prereq makes the quest permanently unstartable")
	assert_eq(String(q.expire_on_flag), "hostage_died", "a padded expire flag makes the WR-6 fail window dead content")
	q = null

func test_normalize_floors_required_count_to_one() -> void:
	var q := _quest_with(2)
	q.objectives[0].required_count = 0   # loads fine despite @export_range(1, 9999) — the range is an inspector HINT
	q.objectives[1].required_count = -3
	assert_eq(QuestOps.normalize(q), 2, "both counts repaired")
	assert_eq(q.objectives[0].required_count, 1, "a 0 count reads as done before the player does anything")
	assert_eq(q.objectives[1].required_count, 1, "a negative count is floored the same way")
	q = null

func test_normalize_leaves_a_large_required_count_alone() -> void:
	var q := _quest_with(1)
	q.objectives[0].required_count = 9999999
	assert_eq(QuestOps.normalize(q), 0, "the upper bound is deliberately NOT clamped")
	assert_eq(q.objectives[0].required_count, 9999999, "an absurd count is visible in the journal, not silent — leave it")
	q = null

func test_normalize_returns_the_number_of_fields_repaired() -> void:
	var q := _quest_with(2)
	q.prereq_quest_id = &" intro_job "        # 1
	q.expire_on_flag = &" hostage_died "      # 2
	q.objectives[0].id = &" obj_1 "           # 3
	q.objectives[0].target_id = &" raider "   # 4
	q.objectives[1].required_count = 0        # 5
	# 5 is HAND-COUNTED from the five lines above, never derived from the module under test.
	assert_eq(QuestOps.normalize(q), 5, "five drifted fields report a changed-count of five for the status line")
	q = null

func test_normalize_returns_zero_on_a_clean_quest() -> void:
	var q := _quest_with(2)
	assert_eq(QuestOps.normalize(q), 0, "nothing to repair, so the dock can stay quiet about it")
	q = null

func test_normalize_is_idempotent() -> void:
	var q := _quest_with(1)
	q.prereq_quest_id = &" intro_job "
	q.objectives[0].target_id = &" raider "
	assert_eq(QuestOps.normalize(q), 2, "first pass repairs both")
	assert_eq(QuestOps.normalize(q), 0, "second pass finds nothing — every branch only fires when the value differs")
	q = null

func test_normalize_noops_on_null() -> void:
	assert_eq(QuestOps.normalize(null), 0, "null quest repairs nothing and reports nothing")

func test_normalize_skips_a_null_objective_row() -> void:
	var q := _quest_with(1)
	q.objectives[0].target_id = &" raider "
	q.objectives.append(null)  # its own authoring problem (the dock renders it as <null>); normalize must not crash
	assert_eq(QuestOps.normalize(q), 1, "the real row is still repaired past the null one")
	assert_eq(String(q.objectives[0].target_id), "raider", "the surviving row was trimmed")
	q = null

func test_normalize_leaves_the_quest_id_and_prose_alone() -> void:
	var q := _quest_with(1)
	q.id = &" test_quest "
	q.title = " A Padded Title "
	q.objectives[0].description = " padded prose "
	assert_eq(QuestOps.normalize(q), 0, "none of the deliberately-untouched fields count as a repair")
	assert_eq(String(q.id), " test_quest ", "this dock never exposes Quest.id — silently re-keying the quest would be a surprise edit")
	assert_eq(q.title, " A Padded Title ", "player-facing prose is left exactly as authored")
	assert_eq(q.objectives[0].description, " padded prose ", "objective prose is left as authored (strip_edges would eat a multiline's blank lines)")
	q = null

func test_normalize_leaves_a_zero_reward_count_alone() -> void:
	var q := _quest_with_rewards(1)
	q.rewards[0].count = 0  # item_stack.gd:13 documents 0 as "skip this row" — authored intent, not drift
	assert_eq(QuestOps.normalize(q), 0, "a 0-count reward row is legitimate authoring")
	assert_eq(q.rewards[0].count, 0, "normalize must NOT floor a reward count the way it floors required_count")
	q = null


# --- size sanity (assert_lte / assert_gte, NOT le/ge) ---------------------------------------------------------

func test_objective_count_bounds_after_ops() -> void:
	var q := _quest_with(1)
	QuestOps.add_objective(q)
	QuestOps.add_objective(q)
	assert_gte(q.objectives.size(), 1, "at least one objective remains")
	assert_lte(q.objectives.size(), 3, "no more than the three we have")
	q = null

func test_reward_count_bounds_after_ops() -> void:
	var q := _quest_with_rewards(1)
	QuestOps.add_reward(q)
	QuestOps.remove_reward(q, 0)
	QuestOps.move_reward(q, 0, 1)  # a no-op on a single-row list; must not grow or shrink it
	assert_gte(q.rewards.size(), 1, "at least one reward row remains")
	assert_lte(q.rewards.size(), 2, "no more rows than the two that were ever added")
	q = null
