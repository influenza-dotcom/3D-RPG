extends GutTest

## Dialogue-edit tab: PURE round-trip on the static ops (dialogue_edit_ops.gd + choice_consequence_ops.gd) + a
## construct smoke test on the tab Control. Instantiating the tab forces GDScript to compile the WHOLE editor script
## (catching errors --import misses for addon-only scripts). The ops are tested on throwaway
## DialogueResource/Line/Choice.new()s with NO disk write and NO EditorInterface -- exactly the code path an
## add/remove/reorder button uses MINUS the save.
##
## The CONSEQUENCES half (quest picker rows / start-quest warnings / the choice-row tag suffix, plus the Perks id
## registry that feeds `required_perk_id`) is the surface that made a conversation able to hand out a quest at all.
## It is covered here because it is pure: `quest_rows` does `load()` a .tres, which works headless, and everything
## else runs on bare `.new()` resources. Nothing in this file may reach EditorInterface, a socket or a SubViewport --
## GUT runs headless and 9.6 FAILS a test on any engine error, so an editor-only call would break the whole run.

const Ops := preload("res://addons/cybersunday_tools/dock_dialogue/dialogue_edit_ops.gd")
## The consequence ops. A SECOND module beside `Ops` by design: dialogue_edit_ops owns list MUTATION, this owns the
## consequence READS. Preloaded by path because neither carries a class_name.
const Ops2 := preload("res://addons/cybersunday_tools/dock_dialogue/choice_consequence_ops.gd")
const DialogueEditor := preload("res://addons/cybersunday_tools/dock_dialogue/dialogue_editor.gd")
## The perk registry (no class_name -- preloaded by path, like factions.gd / item_ids.gd).
const Perks := preload("res://scripts/player/perks.gd")

## Scanned by the Start quest picker. Trailing slash is harmless (InspectorCalc.resource_paths_in path_join()s).
const QUESTS_DIR := "res://resources/quests/"
## A real folder holding only NON-Quest .tres (Faction resources), used as the type-filter fixture: `quest_rows`
## must exclude every one of them. An existing folder beats inventing throwaway files, and `is Quest` is what keeps
## a non-Quest out of a picker whose write-back assigns to a `Quest` field.
const NON_QUEST_DIR := "res://resources/factions/"
## THE discriminating fixture: on disk this file's stem and its `id` deliberately DIFFER
## (recover_the_package.tres carries `id = &"recover_package"`). That gap is the only way to prove a picker row is
## labelled by the id -- the key "Complete quest id" / "Advance quest id" address quests with -- rather than by the
## filename, which would teach a designer the wrong key and manufacture a silent runtime no-op.
const QUEST_FIXTURE_PATH := "res://resources/quests/recover_the_package.tres"
const QUEST_FIXTURE_ID := "recover_package"
const QUEST_FIXTURE_STEM := "recover_the_package"

## The consequence tags, written out as LITERALS rather than read back off Ops2's own consts: an expectation built
## from the module under test would pass even if a tag were renamed to garbage, and the choice-row suffix is the
## only at-a-glance signal that a choice carries a payload.
const TAG_START_QUEST := "[Q+]"
const TAG_COMPLETE_QUEST := "[Q done]"
const TAG_ADVANCE_QUEST := "[Q++]"
const TAG_GIVE_ITEM := "[item]"
const TAG_GIVE_MONEY := "[$]"
const TAG_REWARD_REP := "[rep]"
const TAG_AGGRO := "[aggro]"
## The TWO-space separator consequence_summary puts in FRONT of a non-empty tag list (so an effect-free row stays
## byte-identical to today's). A literal here for the same reason the tags are: read off Ops2.SUMMARY_PREFIX it would
## agree with itself even if the separator vanished, and a vanished separator is a row reading "2: Yes.[Q+]".
const TAG_SEP := "  "
## What a choice with EVERY consequence set must produce: the separator above, then the tags in documented order.
const ALL_TAGS := "  [Q+] [Q done] [Q++] [item] [$] [rep] [aggro]"

## Direct children of the tab's `_choice_box` after Phase 1: identity 2 (Label, Target) + gates 13 (section header
## + 12 rows, ending on Fail target) + consequences 13 (section header + 12 rows). Asserted as a FLOOR, not an
## equality: adding a row later is authoring progress, whereas LOSING one is a field that silently stopped being
## authorable -- which is the bug this smoke exists to catch.
const CHOICE_ROW_FLOOR := 28


func _res_with_lines(n: int) -> DialogueResource:
	var r := DialogueResource.new()
	for i in range(n):
		var ln := DialogueLine.new()
		ln.text = "line %d" % i
		r.lines.append(ln)
	return r


# --- construct smoke ------------------------------------------------------------------------------------------

func test_dialogue_editor_constructs() -> void:
	var d = DialogueEditor.new()
	assert_not_null(d, "dialogue editor should construct (compiles + builds its widgets off-tree)")
	assert_eq(d.name, "Dialogue Edit", "tab name matches the spec")
	assert_gt(d.get_child_count(), 0, "the tab built its own children (top bar / body / status) in _init")
	d.free()


## The whole widget build, off-tree. This is the ONLY automated check that reaches the consequence block -- every row
## in it is a live editor widget -- so a compile error or a mistyped member surfaces HERE instead of the first time a
## designer opens the panel. It deliberately does NOT claim to check the signal WIRING: `connect` does not validate
## arity, so a handler with the wrong argument count only errors when the signal is EMITTED, and nothing here emits.
## test_choice_widget_signals_emit_with_the_right_arity below is the test that actually covers that.
##
## Construction runs with the tab OFF-TREE, so `is_visible_in_tree()` is false and the first-reveal latch never fires:
## no disk scan happens here, and every picker holds only its prompt/"(none)" row. That is why this asserts widgets
## EXIST and are width-guarded, never what they contain.
func test_choice_block_builds_every_consequence_row() -> void:
	var d = DialogueEditor.new()
	var box: VBoxContainer = d._choice_box
	assert_not_null(box, "the per-choice field stack exists")
	assert_gte(box.get_child_count(), CHOICE_ROW_FLOOR,
		"the choice field stack still carries at least the %d Phase 1 rows (a lost row = a field that quietly stopped being authorable)" % CHOICE_ROW_FLOOR)
	assert_false(box.visible, "the field stack stays HIDDEN until a choice is selected")
	# The seven widgets Phase 1 added -- one per Consequences export this tab used to send designers to the raw
	# inspector for (`set_flag` / `set_flag_value` shipped long before). Named one by one because a null member is
	# precisely the typo a construct-only smoke sails past.
	assert_not_null(d._c_start_quest, "Start quest dropdown built (the one true dropdown -- a Quest resource ref)")
	assert_not_null(d._c_give_item, "Give item id field built")
	assert_not_null(d._c_give_count, "Give item count spin built")
	assert_not_null(d._c_give_money, "Give money spin built")
	assert_not_null(d._c_reward_faction, "Reward faction id field built")
	assert_not_null(d._c_reward_rep, "Reward reputation spin built")
	assert_not_null(d._c_aggro, "Aggro speaker checkbox built")
	# Money and reputation are FLOATS on DialogueChoice. A step of 1 would make set_value_no_signal(12.50) snap to
	# 12, and the next _write_choice() would persist the rounded number -- merely SELECTING a choice would corrupt
	# an authored fee. This pins the guard that stops that.
	assert_eq(d._c_give_money.step, 0.01, "Give money keeps a fractional step, so selecting a choice can't round a fee away")
	assert_eq(d._c_reward_rep.step, 0.01, "Reward reputation keeps a fractional step (a float standing)")
	# The stamp pickers beside the id LineEdits. They must exist for a Refresh to refill them from a re-scanned
	# registry; the LineEdit stays the source of truth, so a missing stamp is a lost typo-avoider, not lost data.
	assert_not_null(d._c_req_stat_stamp, "Req stat stamp built")
	assert_not_null(d._c_req_faction_stamp, "Req faction id stamp built")
	assert_not_null(d._c_req_item_stamp, "Req item id stamp built")
	assert_not_null(d._c_give_item_stamp, "Give item id stamp built")
	assert_not_null(d._c_reward_faction_stamp, "Reward faction id stamp built")
	# HEIGHT POLICY, pinned. The bottom-panel TabContainer sizes to its TALLEST tab, so all 28 rows have to sit inside
	# the right column's ScrollContainer -- vertical scrolling is what stops the stack's content height ever reaching
	# the tab's minimum. This plugin has TWICE shipped a tab that grew past the panel and made the editor unusable, and
	# nothing else in the suite checks it: a row parented to the head bar instead would look fine in every other assert.
	assert_true(_has_scroll_ancestor(box),
		"the choice field stack lives under a ScrollContainer, so 28 rows scroll instead of growing the bottom panel")
	# WIDTH is the other half of the same policy, and it fails the opposite way. `fit_to_longest_item` defaults TRUE on
	# OptionButton, and this tab's right column DISABLES horizontal scrolling -- so an unclamped dropdown's
	# longest-item minimum propagates outward and widens the whole panel. PickerRows.apply clears it; a picker filled
	# by hand instead of through apply() is exactly how that regresses.
	assert_false(d._c_start_quest.fit_to_longest_item,
		"the Start quest dropdown was filled through PickerRows.apply, so a long '<id>  (<file>)' label can't widen the panel")
	assert_false(d._c_give_item_stamp.fit_to_longest_item,
		"each stamp went through PickerRows.apply too -- 35 item ids would otherwise set the panel's minimum width")
	d.free()


## True when any ancestor of `node` is a ScrollContainer. Walks parents rather than asking the tab, because the stack
## is nested several deep (row HBox -> _choice_box -> block VBox -> right VBox -> ScrollContainer) and the exact depth
## is layout detail this test must not pin. Off-tree-safe: get_parent() is null at the top of the built subtree.
func _has_scroll_ancestor(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


## Every widget signal the Consequences block wires, ACTUALLY EMITTED. This is the check the construct smoke above
## cannot be: `connect` does not validate a Callable's arity, and Godot 4 does NOT drop surplus signal args -- so a
## 0-arg handler on `item_selected`, or a `.bind()` that appends the wrong number of extras, errors AT EMIT and
## nowhere else. GUT 9.6 fails a test on any engine error, which is what turns "the connect reads right" into a fact.
##
## Nothing is mutated: no conversation is loaded, so `_write_choice` and `_on_start_quest_picked` both return at their
## `ch == null` guard and `_on_stamp_picked` returns on the prompt row (index 0). The emits exist for their ARITY
## alone, and none of those paths touches EditorInterface or the disk.
func test_choice_widget_signals_emit_with_the_right_arity() -> void:
	var d = DialogueEditor.new()
	d._c_give_item.text_changed.emit("medkit")
	d._c_give_count.value_changed.emit(2.0)
	d._c_give_money.value_changed.emit(-12.5)
	d._c_reward_faction.text_changed.emit("townsfolk")
	d._c_reward_rep.value_changed.emit(8.0)
	d._c_aggro.toggled.emit(true)  # a CheckBox is a Button: `toggled`, never the SpinBoxes' `value_changed`
	d._c_start_quest.item_selected.emit(0)
	# The stamps are the connection most likely to drift: `.bind(stamp, field)` APPENDS to the signal's own arg, so the
	# handler must take THREE. Index 0 is the permanent prompt row, so each call short-circuits after re-selecting it.
	for stamp in [d._c_req_stat_stamp, d._c_req_faction_stamp, d._c_req_item_stamp, d._c_give_item_stamp, d._c_reward_faction_stamp]:
		stamp.item_selected.emit(0)
	assert_null(d._selected_choice(),
		"no conversation is loaded, so every handler above hit its null-choice guard and wrote nothing")
	d.free()


# --- add_line -------------------------------------------------------------------------------------------------

func test_add_line_appends_and_returns_it() -> void:
	var r := _res_with_lines(0)
	var ln := Ops.add_line(r)
	assert_not_null(ln, "add_line returns the new line")
	assert_eq(r.lines.size(), 1, "add_line appended one line")
	assert_eq(r.lines[0], ln, "the returned line is the one appended (same reference)")
	r = null


func test_add_line_noops_on_null_resource() -> void:
	assert_null(Ops.add_line(null), "add_line on null returns null (no crash)")


# --- remove_line ----------------------------------------------------------------------------------------------

func test_remove_line_removes_at_index() -> void:
	var r := _res_with_lines(3)
	assert_true(Ops.remove_line(r, 1), "remove_line(1) succeeds")
	assert_eq(r.lines.size(), 2, "one line removed")
	assert_eq(r.lines[0].text, "line 0", "line 0 intact")
	assert_eq(r.lines[1].text, "line 2", "line 2 shifted into slot 1")
	r = null


func test_remove_line_bounds_guarded() -> void:
	var r := _res_with_lines(2)
	assert_false(Ops.remove_line(r, -1), "negative index refused")
	assert_false(Ops.remove_line(r, 2), "index == size refused")
	assert_false(Ops.remove_line(r, 99), "far out-of-range refused")
	assert_false(Ops.remove_line(null, 0), "null resource refused")
	assert_eq(r.lines.size(), 2, "no line removed by any bad call")
	r = null


# --- move_line ------------------------------------------------------------------------------------------------

func test_move_line_down_swaps() -> void:
	var r := _res_with_lines(3)
	assert_true(Ops.move_line(r, 0, 1), "move line 0 down succeeds")
	assert_eq(r.lines[0].text, "line 1", "line 1 is now first")
	assert_eq(r.lines[1].text, "line 0", "line 0 moved to slot 1")
	r = null


func test_move_line_up_swaps() -> void:
	var r := _res_with_lines(3)
	assert_true(Ops.move_line(r, 2, -1), "move line 2 up succeeds")
	assert_eq(r.lines[1].text, "line 2", "line 2 is now in slot 1")
	assert_eq(r.lines[2].text, "line 1", "line 1 moved to slot 2")
	r = null


func test_move_line_refuses_off_the_ends_and_bad_step() -> void:
	var r := _res_with_lines(3)
	assert_false(Ops.move_line(r, 0, -1), "cannot move the first line up")
	assert_false(Ops.move_line(r, 2, 1), "cannot move the last line down")
	assert_false(Ops.move_line(r, 0, 2), "invalid step (not +-1) refused")
	assert_false(Ops.move_line(r, 0, 0), "zero step refused")
	assert_false(Ops.move_line(null, 0, 1), "null resource refused")
	assert_eq(r.lines[0].text, "line 0", "order unchanged after refused moves")
	r = null


# --- add_choice -----------------------------------------------------------------------------------------------

func test_add_choice_appends_with_continue_default() -> void:
	var ln := DialogueLine.new()
	var ch := Ops.add_choice(ln)
	assert_not_null(ch, "add_choice returns the new choice")
	assert_eq(ln.choices.size(), 1, "one choice appended")
	assert_eq(ch.target, DialogueLine.CONTINUE, "a fresh choice defaults to CONTINUE so it doesn't dead-end")
	ln = null


func test_add_choice_noops_on_null_line() -> void:
	assert_null(Ops.add_choice(null), "add_choice on null returns null (no crash)")


# --- remove_choice --------------------------------------------------------------------------------------------

func test_remove_choice_removes_at_index() -> void:
	var ln := DialogueLine.new()
	var a := Ops.add_choice(ln)
	var b := Ops.add_choice(ln)
	a.text = "a"
	b.text = "b"
	assert_true(Ops.remove_choice(ln, 0), "remove_choice(0) succeeds")
	assert_eq(ln.choices.size(), 1, "one choice removed")
	assert_eq(ln.choices[0].text, "b", "choice b shifted into slot 0")
	ln = null


func test_remove_choice_bounds_guarded() -> void:
	var ln := DialogueLine.new()
	Ops.add_choice(ln)
	assert_false(Ops.remove_choice(ln, -1), "negative index refused")
	assert_false(Ops.remove_choice(ln, 1), "index == size refused")
	assert_false(Ops.remove_choice(null, 0), "null line refused")
	assert_eq(ln.choices.size(), 1, "no choice removed by any bad call")
	ln = null


# --- move_choice ----------------------------------------------------------------------------------------------

func test_move_choice_reorders() -> void:
	var ln := DialogueLine.new()
	var a := Ops.add_choice(ln); a.text = "a"
	var b := Ops.add_choice(ln); b.text = "b"
	var c := Ops.add_choice(ln); c.text = "c"
	assert_true(Ops.move_choice(ln, 2, -1), "move choice 2 up succeeds")
	assert_eq(ln.choices[1].text, "c", "c moved into slot 1")
	assert_eq(ln.choices[2].text, "b", "b moved to slot 2")
	assert_true(Ops.move_choice(ln, 0, 1), "move choice 0 down succeeds")
	assert_eq(ln.choices[0].text, "c", "c moved into slot 0")
	assert_eq(ln.choices[1].text, "a", "a moved to slot 1")
	ln = null


func test_move_choice_refuses_off_the_ends_and_bad_step() -> void:
	var ln := DialogueLine.new()
	Ops.add_choice(ln)
	Ops.add_choice(ln)
	assert_false(Ops.move_choice(ln, 0, -1), "cannot move the first choice up")
	assert_false(Ops.move_choice(ln, 1, 1), "cannot move the last choice down")
	assert_false(Ops.move_choice(ln, 0, 3), "invalid step refused")
	assert_false(Ops.move_choice(null, 0, 1), "null line refused")
	assert_eq(ln.choices.size(), 2, "choice count unchanged after refused moves")
	ln = null


# --- a small end-to-end authoring round-trip ------------------------------------------------------------------

func test_author_a_tiny_branch_via_ops() -> void:
	# Build a 2-line conversation where line 0 offers a choice that branches to line 1 -- using only the ops the
	# tab buttons call, then assert the structure the way DialogueManager would address it.
	var r := _res_with_lines(0)
	var l0 := Ops.add_line(r)
	var l1 := Ops.add_line(r)
	l0.text = "Halt. Who goes there?"
	l1.text = "Pass, friend."
	var ch := Ops.add_choice(l0)
	ch.text = "A friend."
	ch.target = 1  # branch to line index 1
	assert_eq(r.lines.size(), 2, "two lines authored")
	assert_true(r.lines[0].has_choices(), "line 0 is a branch point")
	assert_eq(r.lines[0].choices[0].target, 1, "the choice targets line index 1")
	assert_gte(r.lines[0].choices[0].target, 0, "a branch target is a real line index (>= 0)")
	assert_lte(r.lines[0].choices[0].target, r.lines.size() - 1, "target is in range")
	r = null


# ==============================================================================================================
# CONSEQUENCES (choice_consequence_ops.gd) -- the pure half of "a conversation can give a quest"
# ==============================================================================================================

# --- quest_rows: the Start quest picker's rows -----------------------------------------------------------------

## A REAL scan of resources/quests/, because the fixture that matters only exists on disk: a quest whose filename
## and `id` differ. Both halves of a row label are useful (the id is the key, the filename is what the FileSystem
## dock shows), but the ID HAS TO COME FIRST.
func test_quest_rows_are_labelled_by_quest_id_not_filename() -> void:
	var rows: Dictionary = Ops2.quest_rows(QUESTS_DIR)
	var paths: PackedStringArray = rows.get("paths", PackedStringArray())
	var labels: PackedStringArray = rows.get("labels", PackedStringArray())
	assert_eq(labels.size(), paths.size(),
		"paths and labels stay PARALLEL -- PickerRows.path_rows walks them by the same index")
	assert_gt(paths.size(), 0, "resources/quests/ holds authored quests, so a real scan is never empty")
	var i := -1
	for k in paths.size():
		if paths[k] == QUEST_FIXTURE_PATH:
			i = k
			break
	assert_gte(i, 0, "the scan includes %s -- the fixture whose id and filename differ" % QUEST_FIXTURE_PATH)
	if i < 0:
		return  # the assert above already failed; there is no row to inspect
	var label: String = labels[i]
	# STARTS WITH, not merely contains: the id has to be the LEADING text for the designer to read it as the key.
	# (assert_string_starts_with's third parameter is match_case -- it takes NO message argument, so an invariant
	# written there would be silently swallowed. The failure output prints both strings.)
	assert_string_starts_with(label, QUEST_FIXTURE_ID)
	assert_string_contains(label, "(%s)" % QUEST_FIXTURE_STEM)
	assert_false(label.begins_with(QUEST_FIXTURE_STEM),
		"a FILENAME-first label would teach the wrong key: 'Complete quest id' / 'Advance quest id' address quests by Quest.id, so this row must read '%s' first" % QUEST_FIXTURE_ID)


## A missing folder is the state a fresh clone (or a renamed content folder) is in. It must read as "no quests to
## offer" -- the picker then collapses to PickerRows' "(none)" row -- and must NOT push an engine error, which GUT
## would fail the test on.
func test_quest_rows_missing_dir_is_empty() -> void:
	var rows: Dictionary = Ops2.quest_rows("res://resources/__no_such_quests_folder__/")
	var paths: PackedStringArray = rows.get("paths", PackedStringArray())
	var labels: PackedStringArray = rows.get("labels", PackedStringArray())
	assert_eq(paths.size(), 0, "a missing folder yields no paths")
	assert_eq(labels.size(), 0, "a missing folder yields no labels")


## The `is Quest` type filter. The dropdown writes into a `Quest` field, and the pick handler re-checks `is Quest`
## before assigning -- so a non-Quest row is not a crash, it is a DEAD ROW: it looks pickable, and clicking it only
## ever reports "Not a Quest" and leaves the field alone. Filtering at the scan is what keeps it out of the list in
## the first place. resources/factions/ is a real folder of non-Quest .tres, which makes it the honest fixture for
## "the scan found files and rejected all of them" -- an empty folder would prove nothing.
func test_quest_rows_excludes_non_quest_resources() -> void:
	var rows: Dictionary = Ops2.quest_rows(NON_QUEST_DIR)
	var paths: PackedStringArray = rows.get("paths", PackedStringArray())
	assert_eq(paths.size(), 0,
		"%s holds Faction .tres, not quests -- every one is type-filtered out" % NON_QUEST_DIR)


# --- quest_start_warnings: the feature's own audit -------------------------------------------------------------

## Build a Quest OFF-TREE (a Resource: .new() then release with `= null`, never add_child).
func _quest(id: StringName, prereq: StringName) -> Quest:
	var q := Quest.new()
	q.id = id
	q.prereq_quest_id = prereq
	return q


## QuestTracker.start_quest returns SILENTLY for an idless quest -- no toast, no log line -- so a choice wired to
## one looks authored, saves cleanly and starts NOTHING. That silent no-op is the exact green-gauge failure this
## plugin has eaten before, which is why the warning exists at all.
func test_quest_start_warnings_flags_a_blank_id() -> void:
	var q := _quest(&"", &"")
	var w := Ops2.quest_start_warnings(q)
	assert_typeof(w, TYPE_PACKED_STRING_ARRAY, "warnings come back as a PackedStringArray, one line per problem")
	assert_false(w.is_empty(), "a quest with a BLANK id must warn -- start_quest would return immediately")
	assert_eq(w.size(), 1, "exactly one problem here (blank id), so exactly one line -- no over-warning")
	q = null


## The prereq must be NAMED: "something is wrong" is not actionable, "quest 'x' must be completed first" is.
func test_quest_start_warnings_names_an_unmet_prereq() -> void:
	var q := _quest(&"the_next_job", &"the_first_job")
	var w := Ops2.quest_start_warnings(q)
	assert_eq(w.size(), 1, "a set prereq is one problem (the id itself is fine)")
	assert_string_contains(w[0], "the_first_job")
	q = null


func test_quest_start_warnings_reports_both_problems() -> void:
	var q := _quest(&"", &"the_first_job")
	var w := Ops2.quest_start_warnings(q)
	assert_eq(w.size(), 2, "a blank id AND a prereq are two separate lines")
	q = null


## The clean case has to be genuinely silent, or the warning becomes noise the designer learns to ignore.
func test_quest_start_warnings_clean_quest_yields_none() -> void:
	var q := _quest(&"clear_the_block", &"")
	var w := Ops2.quest_start_warnings(q)
	assert_true(w.is_empty(), "an id'd quest with no prereq really will start -- no warning")
	q = null


## Nothing assigned is a legitimate authored state ("this choice starts no quest"), not an error to warn about.
func test_quest_start_warnings_null_quest_is_not_an_error() -> void:
	assert_eq(Ops2.quest_start_warnings(null).size(), 0, "a null quest yields no warnings (no crash either)")


# --- consequence_summary: the choice-row tag suffix ------------------------------------------------------------

## THE pin behind every tag test: a fresh DialogueChoice is NOT all-zero -- `give_item_count` defaults to 1. A
## summary keyed off "a consequence field is non-default" would therefore stamp [item] on every choice ever added.
## Every tag keys off the value the RUNTIME gates on instead, so an effect-free choice's row text is unchanged.
func test_consequence_summary_is_empty_for_a_fresh_choice() -> void:
	var ch := DialogueChoice.new()
	assert_eq(ch.give_item_count, 1, "read off the Resource, not the ops: the default really is 1, hence this test")
	assert_eq(Ops2.consequence_summary(ch), "", "a choice with no consequences appends NOTHING to its row")
	ch = null


## `set_flag` is deliberately untagged: it is bookkeeping rather than a payload the player feels, it appears on most
## branching choices, and a tag on nearly every row is noise -- the opposite of what the suffix is for.
func test_consequence_summary_ignores_set_flag() -> void:
	var ch := DialogueChoice.new()
	ch.set_flag = &"met_the_old_man"
	ch.set_flag_value = true
	assert_eq(Ops2.consequence_summary(ch), "", "set_flag is bookkeeping, not a tagged payload")
	ch = null


## The two writes a designer most often confuses must not read alike on the row.
func test_consequence_summary_distinguishes_a_quest_start_from_money() -> void:
	var q := Quest.new()
	q.id = &"clear_the_block"
	var starts := DialogueChoice.new()
	starts.start_quest_on_choice = q
	var pays := DialogueChoice.new()
	pays.give_money = 250.0
	var starts_sum: String = Ops2.consequence_summary(starts)
	var pays_sum: String = Ops2.consequence_summary(pays)
	assert_string_contains(starts_sum, TAG_START_QUEST)
	assert_string_contains(pays_sum, TAG_GIVE_MONEY)
	assert_false(pays_sum.contains(TAG_START_QUEST), "money alone must not read as a quest start")
	assert_false(starts_sum.contains(TAG_GIVE_MONEY), "a quest start alone must not read as a payout")
	assert_ne(starts_sum, pays_sum, "the two rows are distinguishable at a glance")
	starts = null
	pays = null
	q = null


## NEGATIVE money is a fee the player pays -- still a consequence, so still tagged. (0 is the "no effect" value,
## which is why the gate is `!= 0` and not `> 0`.)
func test_consequence_summary_tags_a_negative_fee() -> void:
	var ch := DialogueChoice.new()
	ch.give_money = -75.0
	assert_string_contains(Ops2.consequence_summary(ch), TAG_GIVE_MONEY)
	ch = null


## DialogueManager advances an objective only when BOTH ids are set, so one alone advances nothing and must not
## claim it does.
##
## The half-authored case asserts the summary is EXACTLY EMPTY rather than "does not contain [Q++]", and that is not
## pedantry: TAG_START_QUEST ("[Q+]") is a SUBSTRING of TAG_ADVANCE_QUEST ("[Q++]"), so a `contains` test cannot tell
## a missing tag from a wrong one -- a bug that stamped [Q+] on a half-authored advance would sail straight past it.
## Nothing else is set on this choice, so "" is the only correct answer and any tag at all fails.
func test_consequence_summary_needs_both_advance_ids() -> void:
	var half := DialogueChoice.new()
	half.advance_quest_id = &"clear_the_block"
	assert_eq(Ops2.consequence_summary(half), "",
		"an advance quest id with no objective id advances nothing at runtime, so the row carries NO tag at all")
	var whole := DialogueChoice.new()
	whole.advance_quest_id = &"clear_the_block"
	whole.advance_objective_id = &"kill_raiders"
	assert_string_contains(Ops2.consequence_summary(whole), TAG_ADVANCE_QUEST)
	half = null
	whole = null


## Same shape for reputation: the runtime needs a faction id AND a non-zero delta, so a faction with a 0 delta is
## inert and gets no tag. This is the pair most likely to be half-authored (pick the faction, forget the number).
## Exact-empty again, for the reason spelled out on the advance test above: a `contains` negative would also pass if
## the half-authored choice grew some OTHER tag.
func test_consequence_summary_reputation_needs_a_nonzero_delta() -> void:
	var inert := DialogueChoice.new()
	inert.reward_reputation_faction_id = "townsfolk"
	inert.reward_reputation = 0.0
	assert_eq(Ops2.consequence_summary(inert), "",
		"a faction id with a 0 delta changes no standing, so it is not a consequence and the row carries NO tag")
	var authored := DialogueChoice.new()
	authored.reward_reputation_faction_id = "townsfolk"
	authored.reward_reputation = -8.0
	assert_string_contains(Ops2.consequence_summary(authored), TAG_REWARD_REP)
	inert = null
	authored = null


## Each single-effect consequence, ALONE, as an EXACT string. The all-at-once test below can only prove a tag exists
## somewhere in a seven-tag line -- it cannot prove the tag keys off its OWN export. A tag wired to the wrong field,
## or made co-dependent on a neighbour, still produces the full string there and fails only here. (The two PAIRED
## consequences -- advance quest+objective, faction+delta -- have their own tests above; one half of either is not a
## consequence at all.)
func test_consequence_summary_tags_each_single_effect_alone() -> void:
	var q := Quest.new()
	q.id = &"clear_the_block"
	var starts := DialogueChoice.new()
	starts.start_quest_on_choice = q
	assert_eq(Ops2.consequence_summary(starts), TAG_SEP + TAG_START_QUEST,
		"a quest reference alone tags [Q+] and nothing else")
	var completes := DialogueChoice.new()
	completes.complete_quest_id = &"recover_package"
	assert_eq(Ops2.consequence_summary(completes), TAG_SEP + TAG_COMPLETE_QUEST,
		"complete_quest_id alone tags [Q done] -- it is a turn-in, not a start")
	var gives := DialogueChoice.new()
	gives.give_item_id = &"medkit"
	assert_eq(Ops2.consequence_summary(gives), TAG_SEP + TAG_GIVE_ITEM,
		"give_item_id alone tags [item], with give_item_count left at its default 1")
	var pays := DialogueChoice.new()
	pays.give_money = 250.0
	assert_eq(Ops2.consequence_summary(pays), TAG_SEP + TAG_GIVE_MONEY, "give_money alone tags [$]")
	var angers := DialogueChoice.new()
	angers.aggro_speaker = true
	assert_eq(Ops2.consequence_summary(angers), TAG_SEP + TAG_AGGRO, "aggro_speaker alone tags [aggro]")
	starts = null
	completes = null
	gives = null
	pays = null
	angers = null
	q = null


## Everything at once, as ONE exact string: it pins the tag set, the documented ORDER, and the two-space separator
## that lives inside the function (a caller adding its own would leave trailing whitespace on every effect-free row).
func test_consequence_summary_emits_every_tag_in_order() -> void:
	var q := Quest.new()
	q.id = &"clear_the_block"
	var ch := DialogueChoice.new()
	ch.start_quest_on_choice = q
	ch.complete_quest_id = &"recover_package"
	ch.advance_quest_id = &"clear_the_block"
	ch.advance_objective_id = &"kill_raiders"
	ch.give_item_id = &"medkit"
	ch.give_money = -12.5
	ch.reward_reputation_faction_id = "townsfolk"
	ch.reward_reputation = 8.0
	ch.aggro_speaker = true
	assert_eq(Ops2.consequence_summary(ch), ALL_TAGS,
		"every consequence tagged, in the documented order, behind the two-space separator")
	# Belt and braces on the individual tags, so a reordering failure above reads differently from a MISSING tag.
	assert_string_contains(Ops2.consequence_summary(ch), TAG_COMPLETE_QUEST)
	assert_string_contains(Ops2.consequence_summary(ch), TAG_GIVE_ITEM)
	assert_string_contains(Ops2.consequence_summary(ch), TAG_AGGRO)
	ch = null
	q = null


## The summary is called from a row refresh, so it has to tolerate whatever the caller hands it -- including a
## queued refresh arriving after the choice was freed. It reads the Variant TAG (typeof) rather than testing
## `choice is Object`, because `is` CRASHES on a freed instance.
func test_consequence_summary_tolerates_a_non_object() -> void:
	assert_eq(Ops2.consequence_summary(null), "", "null yields no tags (no crash)")
	assert_eq(Ops2.consequence_summary({}), "", "a plain Dictionary is not a choice -- no tags, no .get() poke")


# --- Perks.ids() / ids_csv(): the registry that closed the last un-suggested id field -------------------------

## WHY HERE: `required_perk_id` was the one DialogueChoice id field with NO suggestions in EITHER surface. The perk
## registry gained an id scan in the same pass as this tab's consequence block, which is what lets
## dialogue_choice.gd build its PROPERTY_HINT_ENUM_SUGGESTION hint_string from Perks.ids_csv() -- so the RAW
## inspector improved too, not just the plugin. tests/test_perks.gd owns unlock / prerequisite / stat-bonus
## behaviour; the scan belongs beside the surface that motivated it.

func test_perks_ids_scans_the_perk_folder() -> void:
	var ids := Perks.ids()
	# The TYPE, not the contents: `",".join(...)` needs a PackedStringArray, and String()-wrapping the value under
	# test would coerce literally anything into passing -- which is the point of checking a type at all.
	assert_typeof(ids, TYPE_PACKED_STRING_ARRAY, "ids() hands back a PackedStringArray")
	assert_true(ids.has("tough_hide"), "resources/perks/tough_hide.tres is on disk, so its id is offered")
	assert_true(ids.has("deadeye"), "resources/perks/deadeye.tres is on disk, so its id is offered")
	# HONEST LIMIT: both perks on disk have `id` == filename stem, so this cannot prove the scan reads the INTERNAL
	# id (the one PerkManager gates on) rather than the filename. quest_rows has recover_the_package.tres for that
	# distinction; perks have no drifted fixture, and inventing one to prove it is not worth a fake .tres.


func test_perks_ids_csv_matches_ids() -> void:
	var ids := Perks.ids()
	var csv := Perks.ids_csv()
	assert_typeof(csv, TYPE_STRING, "ids_csv() hands back a String -- a hint_string, not an array")
	assert_string_contains(csv, "tough_hide")
	var parts := csv.split(",")
	# Anchored by the disk-truth assertions above: an empty or broken scan makes ids EMPTY, and "" splits to one
	# blank entry, so the size comparison fails rather than trivially agreeing with itself.
	assert_gte(ids.size(), 2, "at least the two authored perks are on disk")
	assert_eq(parts.size(), ids.size(), "one comma-separated entry per id -- no trailing separator, no dropped id")
	for id in ids:
		assert_true(parts.has(id), "id '%s' survives the join into the hint_string" % id)
