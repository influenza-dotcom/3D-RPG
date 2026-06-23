extends GutTest

## Dialogue-edit tab: PURE round-trip on the static ops (dialogue_edit_ops.gd) + a construct smoke test on the
## tab Control. Instantiating the tab forces GDScript to compile the WHOLE editor script (catching errors --import
## misses for addon-only scripts). The ops are tested on throwaway DialogueResource/Line/Choice.new()s with NO
## disk write and NO EditorInterface -- exactly the code path an add/remove/reorder button uses MINUS the save.

const Ops := preload("res://addons/cybersunday_tools/dock_dialogue/dialogue_edit_ops.gd")
const DialogueEditor := preload("res://addons/cybersunday_tools/dock_dialogue/dialogue_editor.gd")


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
