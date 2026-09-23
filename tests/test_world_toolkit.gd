extends GutTest

## World toolkit drop-ins: Switch (one-shot latch + verb + action dispatch) and Readable (note pagination + verb).
## The in-tree interaction (PickupRay hover, the dialogue UI showing a note) is playtest-verified; here we pin the
## off-tree logic.

## A target exposing a 1-arg and a 0-arg method, to exercise the Switch's arity-aware action dispatch.
class _ArgTarget extends Node:
	var got: Variant = "none"
	func fire(a) -> void:
		got = a
	func plain() -> void:
		got = "plain"

## The [F] hover prompt the PickupRay paints: a lever dropped in with no verb authored must still say SOMETHING
## (a blank prompt reads as "not interactable"), and an authored verb must replace that generic, verbatim.
func test_switch_hover_prompt_is_never_blank_and_an_authored_verb_replaces_it() -> void:
	var s := Switch.new()
	var generic := s.look_name()
	assert_false(generic.strip_edges().is_empty(),
		"a Switch with no verb authored must still show a hover prompt — a blank [F] label reads as a dead prop")
	s.verb = "Pull the lever"
	assert_eq(s.look_name(), "Pull the lever", "the designer's verb is the hover prompt, verbatim")
	assert_ne(s.look_name(), generic, "...and it replaces the generic prompt rather than being ignored")
	s.free()

func test_switch_one_shot_spends_after_use() -> void:
	var s := Switch.new()
	s.one_shot = true
	assert_true(s.can_be_talked_to(), "usable before its single use")
	s.start_talk(null)  # no actions configured -> just latches + emits `used`
	assert_false(s.can_be_talked_to(), "a one-shot switch is inert after throwing")
	s.free()

func test_switch_repeatable_stays_usable() -> void:
	var s := Switch.new()
	s.start_talk(null)
	assert_true(s.can_be_talked_to(), "a repeatable switch stays usable after use")
	s.free()

func test_readable_paginates_on_blank_lines() -> void:
	var r := Readable.new()
	r.text = "Page one.\n\nPage two.\n\nPage three."
	var res := r._build_pages()
	assert_eq(res.lines.size(), 3, "blank lines split the note into 3 pages")
	assert_eq(res.lines[0].text, "Page one.", "first page text, stripped")
	assert_eq(res.lines[2].text, "Page three.", "last page text")
	res = null
	r.free()

func test_readable_single_paragraph_is_one_page() -> void:
	var r := Readable.new()
	r.text = "Just a one-liner note."
	assert_eq(r._build_pages().lines.size(), 1, "a single paragraph is one page")
	assert_false(r.look_name().strip_edges().is_empty(),
		"a Readable with no verb authored still shows a hover prompt — a blank [F] label reads as a dead prop")
	r.free()

## A SINGLE newline is a line break INSIDE a page, never a page break: a note typed as a short verse or an
## address block must not shatter into one dialogue page per line. Only a BLANK line turns the page.
func test_readable_single_newline_stays_on_the_same_page() -> void:
	var r := Readable.new()
	r.text = "Dear Sam,\nthe key is under the mat.\n\nBurn this note."
	var pages := r._build_pages()
	assert_eq(pages.lines.size(), 2, "one blank line = two pages; the single newline inside the first paragraph must not split it")
	if pages.lines.size() == 2:
		assert_true(pages.lines[0].text.contains("Dear Sam,") and pages.lines[0].text.contains("under the mat."),
			"both lines of the first paragraph read together on page one")
		assert_eq(pages.lines[1].text, "Burn this note.", "the paragraph after the blank line is page two")
	pages = null
	r.free()

func test_switch_passes_activator_to_a_one_arg_action() -> void:
	# The documented escape hatch: an action method that takes the activator (e.g. TriggerVolume.fire(activator)).
	# A zero-arg call would error + abort start_talk; the arity-aware dispatch must pass the activator AND complete.
	var s := Switch.new()
	var t := _ArgTarget.new()
	t.name = "ArgTarget"
	s.add_child(t)
	s.action = &"fire"
	s.target = ^"ArgTarget"
	watch_signals(s)
	s.start_talk(t)  # `t` doubles as the activator (any Node)
	assert_eq(t.got, t, "the activator was passed to the 1-arg action")
	assert_signal_emitted(s, "used", "start_talk ran to completion (used emitted), not aborted by an arity error")
	s.free()  # frees the child target too

func test_switch_calls_a_zero_arg_action_bare() -> void:
	var s := Switch.new()
	var t := _ArgTarget.new()
	t.name = "PlainTarget"
	s.add_child(t)
	s.action = &"plain"
	s.target = ^"PlainTarget"
	s.start_talk(null)
	assert_eq(t.got, "plain", "a zero-arg action is called bare")
	s.free()

func test_readable_paginates_crlf_text() -> void:
	var r := Readable.new()
	r.text = "Alpha.\r\n\r\nBeta."  # Windows CRLF blank line
	assert_eq(r._build_pages().lines.size(), 2, "CRLF blank lines paginate (line endings normalized first)")
	r.free()

func test_readable_skips_whitespace_only_separator() -> void:
	var r := Readable.new()
	r.text = "Alpha.\n\n   \n\nBeta."  # a 'blank' line that actually holds spaces, between two real paragraphs
	assert_eq(r._build_pages().lines.size(), 2, "a whitespace-only separator doesn't emit a blank page")
	r.free()
