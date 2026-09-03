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
##
## The HANDOFF + DIRTY half (select_path, the selection-preserving refresh, the `_dirty` flag, the off-tree dirty
## guard, the failed-load branch) is pinned on the tab itself, OFF-TREE, against the two conversations on disk
## (old_man.tres / slice_relay_terminal.tres -- both two lines). Those tests only ever READ the on-disk files: `load()`
## hands back the process-wide cached instance, so a test that mutated one would leak the edit into every later test
## that loads the same path. Every mutation test builds its own DialogueResource.new() instead.

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

## The two conversations on disk (both two lines: old_man's line 1 carries two choices, slice_relay_terminal's line 0
## carries one), plus the VoiceData that sits in the SAME folder and must be filtered out of the picker. READ-ONLY
## fixtures -- see the header on why no test may mutate them.
const OLD_MAN := "res://resources/dialogue/old_man.tres"
const SLICE_TERMINAL := "res://resources/dialogue/slice_relay_terminal.tres"
const NOT_A_CONVERSATION := "res://resources/dialogue/old_man_voice.tres"
## The Save button's resting text and the dirty marker the tab appends to it -- LITERALS, like the tags, so a renamed
## button fails here instead of the test agreeing with whatever the tab now says.
const SAVE_TEXT := "Save Conversation"
const DIRTY_SUFFIX := "(unsaved changes)"

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
	# HEIGHT POLICY, pinned. A TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter
	# keeps the height it grew to -- so one tall tab, once shown, leaves the panel tall for every tab after it. All 28
	# rows therefore have to sit inside the right column's ScrollContainer: vertical scrolling is what stops the
	# stack's content height ever reaching the tab's minimum. This plugin has TWICE shipped a tab that grew past the
	# panel and made the editor unusable, and nothing else in the suite checks it: a row parented to the head bar
	# instead would look fine in every other assert.
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
	assert_false(d._dirty, "a stray emit with no choice selected must never mark an empty editor dirty")
	d.free()


# ==============================================================================================================
# THE TAB'S OWN CONTRACTS -- layout words, handoff, refresh, dirty state. All off-tree; the on-disk fixtures are
# only ever read (see the header).
# ==============================================================================================================

## Every Button under `node`, in tree order. The top bar is the tab's first child, so its buttons are found by text
## rather than by pinning a child index the layout might reshuffle.
func _buttons_in(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons_in(c))
	return out


func _button_texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for b in _buttons_in(node):
		out.append(b.text)
	return out


## Every Label text under `node`, in tree order (the "Label:" column of each field row).
func _label_texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in node.get_children():
		if c is Label:
			out.append((c as Label).text)
		out.append_array(_label_texts(c))
	return out


## The fixed top bar: picker + Refresh + Save Conversation + Check Reach, all OUTSIDE the scroll; the two Target
## dropdowns and the picker carry the width guards; the status label follows the panel contract (two lines, autowrap,
## default font size, tooltip mirroring). Nothing is open at construction, so Save Conversation is greyed with the
## tooltip that names what is missing.
func test_top_bar_and_status_follow_the_panel_contract() -> void:
	var d = DialogueEditor.new()
	var top := _button_texts(d.get_child(0))
	assert_true(top.has("Refresh"), "the top bar keeps Refresh (re-read the list, never the open conversation)")
	assert_true(top.has(SAVE_TEXT), "Save is worded 'Save Conversation' -- one verb per meaning")
	assert_true(top.has("Check Reach"), "Check Reach hands off to the Reach tab from the top bar")
	assert_false(_has_scroll_ancestor(d._save_btn), "the Save button lives in the fixed head bar, not inside the scroll")
	for btn in [d._picker, d._c_target, d._c_target_on_fail, d._c_req_quest_state]:
		var ob: OptionButton = btn
		assert_false(ob.fit_to_longest_item, "a hand-filled dropdown never sizes to its longest row (the panel would widen)")
		assert_true(ob.clip_text, "a hand-filled dropdown clips its text instead of growing")
		assert_eq(ob.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "a long row trims with an ellipsis, not a hard cut")
	assert_eq(d._status.max_lines_visible, 2, "the status label clamps to two lines (the tooltip carries the rest)")
	assert_eq(d._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the status label wraps on words")
	assert_false(d._status.has_theme_font_size_override("font_size"), "the status label keeps the default font size (no 10 px override)")
	assert_eq(d._status.tooltip_text, d._status.text, "the status tooltip mirrors the full text on every write")
	assert_true(d._save_btn.disabled, "nothing is open, so Save Conversation is greyed")
	assert_string_contains(d._save_btn.tooltip_text, "Pick a conversation")
	assert_false(_has_scroll_ancestor(d._status), "the status row is outside the scroll, always visible")
	d.free()


## The list rows read Add / Remove / Up / Down (no bare glyphs), every one carries a tooltip, and the gate labels say
## "Needs", never "Req" -- the designer reads these, not the code.
func test_buttons_and_gate_labels_use_designer_words() -> void:
	var d = DialogueEditor.new()
	var expected := PackedStringArray(["Add", "Remove", "Up", "Down"])
	for rows in [d._line_buttons, d._choice_buttons]:
		var row: Array = rows
		assert_eq(row.size(), 4, "each list has exactly Add / Remove / Up / Down")
		for k in row.size():
			var b: Button = row[k]
			assert_eq(b.text, expected[k], "list button %d reads %s" % [k, expected[k]])
			assert_ne(b.tooltip_text, "", "%s carries a tooltip" % b.text)
	var labels := _label_texts(d._choice_box)
	var needs := 0
	for t in labels:
		assert_false(t.begins_with("Req"), "no gate label abbreviates to 'Req' any more: %s" % t)
		if t.begins_with("Needs"):
			needs += 1
	assert_gte(needs, 9, "the gate rows read 'Needs ...' (stat, value, flag, flag value, faction, reputation, perk, item, count, quest, state)")
	assert_eq(d._c_set_flag_value.text, "Flag becomes true", "the set-flag checkbox says what it does, not 'value = true'")
	assert_ne(d._c_set_flag_value.tooltip_text, "", "and explains the unchecked meaning in its tooltip")
	d.free()


## The choice list's tooltip is the legend for the row tags, and it is built from the SAME consts the summary emits
## -- so every literal the tag tests pin must appear in it.
func test_choice_list_legend_names_every_tag() -> void:
	var d = DialogueEditor.new()
	var legend: String = d._choice_list.tooltip_text
	for tag in [TAG_START_QUEST, TAG_ADVANCE_QUEST, TAG_COMPLETE_QUEST, TAG_GIVE_ITEM, TAG_GIVE_MONEY, TAG_REWARD_REP, TAG_AGGRO]:
		assert_string_contains(legend, tag)
	d.free()


## List sentinels are designer words in parentheses -- "(missing)" / "(empty)" / "(no text)" -- never the old
## angle-bracket "<null>" / "<empty>" / "<no label>".
func test_list_rows_use_designer_sentinels() -> void:
	var d = DialogueEditor.new()
	assert_eq(d._preview(null), "(missing)", "a null line previews as (missing)")
	var ln := DialogueLine.new()
	assert_eq(d._preview(ln), "(empty)", "a blank line previews as (empty)")
	assert_eq(d._choice_row_text(0, null), "0: (missing)", "a null choice row reads (missing)")
	var ch := DialogueChoice.new()
	assert_eq(d._choice_row_text(2, ch), "2: (no text)", "a blank choice label reads (no text)")
	ln = null
	ch = null
	d.free()


## The two Target dropdowns name each line by number AND its opening words ("-> line 0: Halt. Who goes there, st..."),
## with "(empty)" for a blank line, and the sentinels keep their ids (-2 Continue / -1 End / the line index).
func test_target_rows_read_line_number_and_opening_words() -> void:
	var d = DialogueEditor.new()
	var r := _res_with_lines(0)
	var a := Ops.add_line(r)
	a.text = "Halt. Who goes there, stranger of the night?"
	var b := Ops.add_line(r)
	b.text = "\n  \n"
	d._res = r
	d._populate_target_options(d._c_target)
	assert_eq(d._c_target.item_count, 4, "Continue + End + one row per line")
	assert_eq(d._c_target.get_item_id(0), DialogueLine.CONTINUE, "row 0 carries the CONTINUE sentinel id")
	assert_eq(d._c_target.get_item_id(1), DialogueLine.END, "row 1 carries the END sentinel id")
	assert_eq(d._c_target.get_item_text(2), "-> line 0: Halt. Who goes there, st...", "a long line is cut at 24 characters with ...")
	assert_eq(d._c_target.get_item_id(2), 0, "the line row's id IS the line index")
	assert_eq(d._c_target.get_item_text(3), "-> line 1: (empty)", "a whitespace-only line reads (empty)")
	# THE DANGLING ROW, and the same add_item id trap the two sentinels above carry: a target past the end of the
	# list gets a transient row so the value ROUND-TRIPS. If that row's id were auto-assigned (its index) instead of
	# stamped, the next _write_choice() would silently rewrite an out-of-range target to whatever the index happened
	# to be -- the exact shape of the bug that made "End conversation" write "jump to line 1".
	d._select_target(d._c_target, 7)
	assert_eq(d._c_target.item_count, 5, "the dangling target added ONE transient row")
	assert_eq(d._c_target.get_item_id(d._c_target.selected), 7, "and that row carries the REAL target id, so the next write round-trips it unchanged")
	assert_string_contains(d._status.text, "only 2 line(s)")
	d._res = null
	r = null
	d.free()


## Host seam: select_path opens the file, points the picker at it BY PATH (the parallel `_paths` array), latches the
## reveal, and leaves the editor clean with Save Conversation live.
func test_select_path_opens_the_file_and_points_the_picker_at_it() -> void:
	var d = DialogueEditor.new()
	assert_true(d.select_path(OLD_MAN), "select_path finds a conversation that is in the dialogue folder")
	assert_true(d._revealed, "a handoff counts as the first reveal (the registries were scanned)")
	assert_eq(d._loaded_path, OLD_MAN, "the file is the open conversation")
	assert_not_null(d._res, "and it loaded")
	assert_gte(d._picker.selected, 0, "the picker points at a row")
	assert_eq(d._paths[d._picker.selected], OLD_MAN, "the picker row and the parallel path array agree on the file")
	assert_false(d._paths.has(NOT_A_CONVERSATION), "a VoiceData in the same folder is filtered out of the picker")
	assert_eq(d._line_list.item_count, 2, "old_man.tres has two lines, so the list shows two rows")
	assert_eq(d._selected_line_index(), 0, "line 0 is picked on open")
	assert_false(d._dirty, "a fresh load is clean")
	assert_false(d._save_btn.disabled, "Save Conversation is live once a conversation is open")
	assert_eq(d._save_btn.text, SAVE_TEXT, "no dirty marker on a clean load")
	assert_string_contains(d._status.text, "old_man.tres")
	assert_false(d._status.text.contains("res://"), "status lines name files, never res:// paths")
	# A second handoff to a DIFFERENT file swaps (the editor is clean, so no guard is needed).
	assert_true(d.select_path(SLICE_TERMINAL), "a second handoff opens the other conversation")
	assert_eq(d._loaded_path, SLICE_TERMINAL, "the open conversation followed the handoff")
	assert_eq(d._paths[d._picker.selected], SLICE_TERMINAL, "and the picker followed it too")
	d.free()


func test_select_path_refuses_a_file_that_is_not_a_conversation() -> void:
	var d = DialogueEditor.new()
	assert_false(d.select_path(""), "a blank path is refused")
	assert_false(d.select_path(NOT_A_CONVERSATION), "a VoiceData is not a conversation -- the host falls back to the Inspector")
	assert_ne(d._loaded_path, NOT_A_CONVERSATION, "the refused file was never opened")
	assert_string_contains(d._status.text, "old_man_voice.tres")
	assert_false(d.select_path("res://resources/dialogue/__no_such_file__.tres"), "a missing file is refused, no error")
	d.free()


## Refresh = re-read the list, never touch what is open: the SAME resource instance stays open, the picker is
## re-pointed by path, and the picked line + choice survive the rebuild.
func test_refresh_keeps_the_open_conversation_and_its_selection() -> void:
	var d = DialogueEditor.new()
	d.select_path(SLICE_TERMINAL)
	var before: DialogueResource = d._res
	d._select_line(1)
	d._refresh_picker()
	assert_same(d._res, before, "Refresh keeps the very same open resource (no reload)")
	assert_eq(d._loaded_path, SLICE_TERMINAL, "the loaded path is unchanged")
	assert_eq(d._paths[d._picker.selected], SLICE_TERMINAL, "the picker was re-pointed BY PATH after the rebuild")
	assert_eq(d._selected_line_index(), 1, "the picked line survived the refresh")
	# With a choice picked too (line 0 of slice_relay_terminal carries one).
	d._select_line(0)
	d._choice_list.select(0)
	d._on_choice_selected(0)
	assert_true(d._choice_box.visible, "precondition: a choice is picked and its editor is showing")
	d._refresh_picker()
	assert_same(d._res, before, "still the same instance")
	assert_eq(d._selected_line_index(), 0, "line selection restored")
	assert_eq(d._selected_choice_index(), 0, "choice selection restored")
	assert_true(d._choice_box.visible, "the choice editor is back on the same choice")
	assert_false(d._dirty, "a refresh + selection restore is signal-free -- nothing was written")
	d.free()


## Every write-through raises `_dirty`, which shows as "*" on Save Conversation and the suffix on the status line.
## Built on an in-memory conversation so no on-disk fixture is ever mutated.
func test_a_write_sets_dirty_and_the_save_button_shows_it() -> void:
	var d = DialogueEditor.new()
	var r := _res_with_lines(1)
	d._res = r
	d._loaded_path = "res://resources/dialogue/__never_saved__.tres"
	d._rebuild_line_list()
	d._select_line(0)
	assert_false(d._dirty, "selecting a line pushes model -> widgets and writes nothing")
	assert_eq(d._save_btn.text, SAVE_TEXT, "clean: no marker")
	# 1. the line text write-through
	d._line_text.text = "Halt."
	d._on_line_text_changed()
	assert_true(d._dirty, "editing the line text marks the conversation dirty")
	assert_eq(r.lines[0].text, "Halt.", "and the edit reached the model")
	assert_eq(d._save_btn.text, SAVE_TEXT + "*", "the Save button shows the marker")
	assert_string_contains(d._status.text, DIRTY_SUFFIX)
	assert_eq(d._status.tooltip_text, d._status.text, "the tooltip mirrors the dirty status too")
	# 2. a structural op
	d._dirty = false
	d._update_button_states()
	d._add_choice()
	assert_true(d._dirty, "adding a choice marks it dirty")
	assert_eq(r.lines[0].choices.size(), 1, "the choice was added")
	# 3. the choice write-through (the per-keystroke path)
	d._dirty = false
	d._update_button_states()
	d._c_text.text = "A friend."
	d._write_choice()
	assert_true(d._dirty, "a choice field write marks it dirty")
	assert_eq(r.lines[0].choices[0].text, "A friend.", "and the label reached the choice")
	# 4. the reveals-name toggle
	d._dirty = false
	d._on_line_reveals_name_toggled(true)
	assert_true(d._dirty, "toggling reveals-name marks it dirty")
	assert_true(r.lines[0].reveals_name, "and the toggle reached the line")
	d._res = null
	r = null
	d.free()


## THE trap this whole tab is shaped around, driven end to end. `_write_choice` is wired to `_c_text.text_changed`,
## so it fires on EVERY KEYSTROKE and writes EVERY widget it knows about -- which means a field written there but
## never PUSHED model->widget in `_on_choice_selected` stamps its widget's CONSTRUCTION DEFAULT onto the live choice
## the moment the designer types one character into an unrelated field. Silently: the row still looks authored, and
## ContentSaveGuard keeps only ONE .bak, so a clobber plus one more Save loses the original bytes too.
##
## Nothing else in the suite can catch that. The construct smoke only proves the widget EXISTS; the arity test never
## loads a choice, so every handler returns at its null guard. This authors a choice with EVERY field off its
## default, selects it the way a click does, types into Label, and asserts that ONLY the label moved -- so a new
## consequence row wired to `_write_choice` with no matching push fails HERE, naming the field that drifted.
##
## `start_quest_on_choice` is asserted alongside them for the opposite invariant: it is a Resource REFERENCE owned by
## `_on_start_quest_picked` and deliberately NOT written by `_write_choice`, so a keystroke must never re-resolve it.
func test_typing_in_one_field_never_clobbers_the_other_fields() -> void:
	var d = DialogueEditor.new()
	var r := _res_with_lines(2)
	d._res = r
	d._loaded_path = "res://resources/dialogue/__never_saved__.tres"
	d._rebuild_line_list()
	d._select_line(0)
	d._add_choice()
	var ch: DialogueChoice = r.lines[0].choices[0]
	# Author every field off its default, ON THE MODEL -- this is the state a .tres on disk would load as.
	var q := Quest.new()
	q.id = &"clear_the_block"
	ch.text = "Yes."
	ch.target = 1
	ch.target_on_fail = 0
	ch.required_stat = &"streetwise"
	ch.required_value = 6
	ch.required_flag = &"met_the_old_man"
	ch.required_flag_value = "false"
	ch.required_faction_id = "townsfolk"
	ch.required_reputation = 12.5
	ch.required_perk_id = &"tough_hide"
	ch.required_item_id = &"keycard"
	ch.required_item_count = 3
	ch.required_quest_id = &"recover_package"
	ch.required_quest_state = DialogueChoice.QuestGate.COMPLETED
	ch.set_flag = &"took_the_job"
	ch.set_flag_value = false
	ch.start_quest_on_choice = q
	ch.complete_quest_id = &"clear_the_block"
	ch.advance_quest_id = &"clear_the_block"
	ch.advance_objective_id = &"kill_raiders"
	ch.give_item_id = &"medkit"
	ch.give_item_count = 4
	ch.give_money = -12.5
	ch.reward_reputation_faction_id = "raiders"
	ch.reward_reputation = -8.25
	ch.aggro_speaker = true
	# Select it (model -> widgets), then type ONE field. This is the whole editor gesture.
	d._on_choice_selected(0)
	assert_eq(d._c_start_quest.selected, d._quest_rows.size() - 1,
		"an inline / unsaved quest reference selects its own row, never '(none)' -- reading '(none)' is what invites the clobber")
	d._c_text.text = "Yes, I'll do it."
	d._write_choice()
	assert_eq(ch.text, "Yes, I'll do it.", "the field the designer actually typed in DID change")
	# ...and nothing else did.
	assert_eq(ch.target, 1, "Target survived a keystroke in Label")
	assert_eq(ch.target_on_fail, 0, "Fail target survived")
	assert_eq(ch.required_stat, &"streetwise", "Needs stat survived")
	assert_eq(ch.required_value, 6, "Needs stat value survived")
	assert_eq(ch.required_flag, &"met_the_old_man", "Needs flag survived")
	assert_eq(ch.required_flag_value, "false", "Needs flag value survived (its default is \"true\", not \"\")")
	assert_eq(ch.required_faction_id, "townsfolk", "Needs faction id survived")
	assert_almost_eq(ch.required_reputation, 12.5, 0.001, "Needs reputation survived")
	assert_eq(ch.required_perk_id, &"tough_hide", "Needs perk id survived")
	assert_eq(ch.required_item_id, &"keycard", "Needs item id survived")
	assert_eq(ch.required_item_count, 3, "Needs item count survived")
	assert_eq(ch.required_quest_id, &"recover_package", "Needs quest id survived")
	assert_eq(ch.required_quest_state, DialogueChoice.QuestGate.COMPLETED, "Needs quest state survived")
	assert_eq(ch.set_flag, &"took_the_job", "Set flag survived")
	assert_false(ch.set_flag_value, "the set-flag value survived (its default is TRUE, so a lost push reads as unchanged)")
	assert_eq(ch.complete_quest_id, &"clear_the_block", "Complete quest id survived")
	assert_eq(ch.advance_quest_id, &"clear_the_block", "Advance quest id survived")
	assert_eq(ch.advance_objective_id, &"kill_raiders", "Advance objective id survived")
	assert_eq(ch.give_item_id, &"medkit", "Give item id survived")
	assert_eq(ch.give_item_count, 4, "Give item count survived (its default is 1, not 0)")
	assert_almost_eq(ch.give_money, -12.5, 0.001, "Give money survived -- a step-1 spin would have rounded it away")
	assert_eq(ch.reward_reputation_faction_id, "raiders", "Reward faction id survived")
	assert_almost_eq(ch.reward_reputation, -8.25, 0.001, "Reward reputation survived")
	assert_true(ch.aggro_speaker, "Speaker-turns-hostile survived")
	assert_same(ch.start_quest_on_choice, q,
		"the Start quest REFERENCE is owned by the pick handler alone -- a keystroke elsewhere must never re-resolve or blank it")
	d._res = null
	ch = null
	q = null
	r = null
	d.free()


## The half of Discard that a reload cannot do on its own. A .tres OMITS default-valued fields -- old_man.tres on
## disk carries `lines` and `choices` and NOTHING else, no line text, no choice label, no consequence -- so
## re-reading it over the cached instance re-assigns two arrays and leaves every character the designer typed
## exactly where it was. Discard therefore resets to script defaults FIRST and only then reloads. This pins the
## reset on THROWAWAY resources, so the on-disk fixtures and the process-wide resource cache are never touched.
func test_reset_to_defaults_is_what_makes_discard_real() -> void:
	var fresh := DialogueChoice.new()
	var ch := DialogueChoice.new()
	ch.resource_name = "keep me"
	ch.text = "Yes."
	ch.target = 3
	ch.give_item_id = &"medkit"
	ch.give_money = -250.0
	ch.aggro_speaker = true
	assert_gte(DialogueEditor._reset_to_defaults(ch), 5, "every field that was off its default was put back")
	assert_eq(ch.text, fresh.text, "the choice label is blank again")
	assert_eq(ch.target, fresh.target, "Target is back to Continue, not left at the authored line")
	assert_eq(ch.give_item_id, fresh.give_item_id, "Give item id is blank again")
	assert_eq(ch.give_money, fresh.give_money, "Give money is back to 0")
	assert_false(ch.aggro_speaker, "the hostility toggle is back off")
	assert_eq(ch.give_item_count, 1, "a field already AT its default is left alone -- and that default is 1, not 0")
	assert_eq(ch.resource_name, "keep me",
		"only SCRIPT variables are reset: a built-in Resource field is never touched (clearing resource_path would evict it from the cache)")
	# A DialogueLine is NOT a @tool script, unlike DialogueChoice -- worth pinning that the reset still reaches it,
	# because that is the difference between Discard reverting a line's text and silently keeping it.
	var ln := DialogueLine.new()
	ln.text = "Halt."
	ln.reveals_name = true
	ln.choices.append(DialogueChoice.new())
	assert_gte(DialogueEditor._reset_to_defaults(ln), 3, "a DialogueLine resets too, @tool script or not")
	assert_eq(ln.text, "", "the line text is blank again")
	assert_false(ln.reveals_name, "the legacy toggle is back off")
	assert_true(ln.choices.is_empty(), "and the line's choice list is emptied, so the reload refills it from the file")
	assert_eq(DialogueEditor._reset_to_defaults(null), 0, "a null object is a no-op, not a crash")
	fresh = null
	ch = null
	ln = null


## Off-tree there is no window to ask "Save changes first?" in, so a dirty swap is REFUSED: the open conversation
## stays, the picker springs back to it, and the status says why. (In the editor the same chokepoint pops the
## Save / Discard / Cancel dialog instead.) The flag is set by hand -- the on-disk fixture is never mutated.
func test_dirty_guard_refuses_a_swap_off_tree_and_restores_the_picker() -> void:
	var d = DialogueEditor.new()
	d.select_path(OLD_MAN)
	var open_idx: int = d._picker.selected
	var other: int = d._paths.find(SLICE_TERMINAL)
	assert_gte(other, 0, "precondition: the other conversation is in the list")
	d._dirty = true
	d._picker.select(other)  # what the widget does on its own before item_selected fires
	d._on_pick(other)
	assert_eq(d._loaded_path, OLD_MAN, "the dirty conversation was NOT replaced")
	assert_eq(d._picker.selected, open_idx, "the picker sprang back to the open file")
	assert_string_contains(d._status.text, "unsaved")
	assert_null(d._save_dialog, "no dialog was built off-tree")
	# Re-picking the OPEN conversation is a no-op, never a reload -- even while dirty.
	d._on_pick(open_idx)
	assert_eq(d._loaded_path, OLD_MAN, "re-picking the open row changes nothing")
	assert_true(d._dirty, "and does not clear the flag")
	d._dirty = false
	d.free()


## The failed-load branch: no document, empty lists, the choice editor hidden, every write button greyed, and a
## status that names the file and the retry (Refresh).
func test_failed_load_clears_the_editor_and_greys_the_writes() -> void:
	var d = DialogueEditor.new()
	d.select_path(OLD_MAN)
	assert_not_null(d._res, "precondition: a conversation is open")
	d._clear_loaded("res://resources/dialogue/broken.tres")
	assert_null(d._res, "the open resource is nulled")
	assert_eq(d._loaded_path, "", "no loaded path")
	assert_false(d._dirty, "a cleared editor is not dirty")
	assert_eq(d._line_list.item_count, 0, "the line list is emptied")
	assert_eq(d._choice_list.item_count, 0, "the choice list is emptied")
	assert_false(d._choice_box.visible, "the choice editor is hidden")
	assert_eq(d._line_text.text, "", "the line text is cleared")
	assert_true(d._save_btn.disabled, "Save Conversation is greyed")
	for b in d._line_buttons:
		assert_true((b as Button).disabled, "line list button '%s' is greyed with nothing open" % (b as Button).text)
	for b in d._choice_buttons:
		assert_true((b as Button).disabled, "choice list button '%s' is greyed with nothing open" % (b as Button).text)
	assert_string_contains(d._status.text, "broken.tres")
	assert_string_contains(d._status.text, "Refresh")
	d.free()


## The list buttons grey by what is picked: Add needs the parent, Remove / Up / Down need a picked row, and each
## greyed button's tooltip names what is missing.
func test_list_buttons_grey_by_what_is_picked() -> void:
	var d = DialogueEditor.new()
	var r := _res_with_lines(2)
	d._res = r
	d._loaded_path = "res://resources/dialogue/__never_saved__.tres"
	d._rebuild_line_list()
	d._select_line(-1)  # open, nothing picked
	assert_false(d._line_buttons[0].disabled, "Add line is live once a conversation is open")
	assert_true(d._line_buttons[1].disabled, "Remove line needs a picked line")
	assert_string_contains(d._line_buttons[1].tooltip_text, "Pick a line")
	assert_true(d._choice_buttons[0].disabled, "Add choice needs a picked line")
	d._select_line(0)
	assert_false(d._line_buttons[1].disabled, "Remove line is live with a line picked")
	assert_false(d._choice_buttons[0].disabled, "Add choice is live with a line picked")
	assert_true(d._choice_buttons[1].disabled, "Remove choice needs a picked choice")
	assert_string_contains(d._choice_buttons[1].tooltip_text, "Pick a choice")
	d._add_choice()
	assert_false(d._choice_buttons[1].disabled, "Remove choice is live with a choice picked")
	assert_ne(d._choice_buttons[1].tooltip_text, "Pick a choice in the list first", "a live button gets its real tooltip back")
	d._res = null
	r = null
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
