extends GutTest

## The pad on-screen keyboard (scripts/ui/pad_keyboard.gd) — the one door a controller player has into the
## character-creation name field (character_creation.gd builds it in _ready and open()s it on A over the field).
## Built IN-TREE via add_child_autofree: open() grabs focus and _input reads the viewport, both of which raise
## engine errors off-tree. No class_name — loaded by path, exactly as character_creation does.
##
## What matters here is the LineEdit contract the creation screen leans on: every key writes straight into
## target.text AND emits text_changed by hand (setting .text in code never emits it, and Begin is gated on that
## signal), the cap is MAX_LEN, Delete on an empty field is silent, and close() hands focus back to the field.
## test_character_creation.gd drives the keyboard THROUGH the screen; this file pins the keyboard on its own.

const PATH := "res://scripts/ui/pad_keyboard.gd"


# --- Fixtures ------------------------------------------------------------------------------------------------

var _kb: PanelContainer = null
var _target: LineEdit = null
var _changes: Array = []  ## every text_changed payload, in order

func before_each() -> void:
	_changes = []
	_target = LineEdit.new()
	add_child_autofree(_target)
	_target.text_changed.connect(func(t: String) -> void: _changes.append(t))
	_kb = load(PATH).new()
	add_child_autofree(_kb)

func after_each() -> void:
	_kb = null
	_target = null

func _buttons() -> Array:
	var out: Array = []
	for grid in _kb.get_children():
		for b in grid.get_children():
			if b is Button:
				out.append(b)
	return out

func _button(label: String) -> Button:
	for b in _buttons():
		if b.text == label:
			return b
	return null


# --- Construction --------------------------------------------------------------------------------------------

func test_starts_hidden_with_no_target() -> void:
	assert_false(_kb.visible, "hidden until the screen open()s it")
	assert_null(_kb._target, "no target until open()")

func test_builds_one_key_per_character_plus_space_delete_done() -> void:
	var grid := _kb.get_child(0)
	assert_true(grid is GridContainer, "the keys live in one GridContainer")
	assert_eq((grid as GridContainer).columns, _kb.COLUMNS, "the grid wraps at COLUMNS")
	var buttons := _buttons()
	assert_eq(buttons.size(), _kb.KEYS.length() + 3, "A-Z + 0-9 plus Space / Delete / Done")
	for i in _kb.KEYS.length():
		assert_eq(buttons[i].text, _kb.KEYS[i], "key %d is labeled with its character" % i)
	assert_not_null(_button(PlayerText.PAD_KEY_SPACE), "a Space key, labeled from PlayerText")
	assert_not_null(_button(PlayerText.PAD_KEY_DELETE), "a Delete key, labeled from PlayerText")
	assert_not_null(_button(PlayerText.PAD_KEY_DONE), "a Done key, labeled from PlayerText")
	assert_eq(buttons[buttons.size() - 1].text, PlayerText.PAD_KEY_DONE, "Done is the LAST key — the natural exit at the end of the walk")

func test_first_key_is_the_first_character() -> void:
	assert_not_null(_kb._first, "the first key is remembered so open() can seat focus on it")
	assert_eq(_kb._first.text, _kb.KEYS[0], "the seat is the first character of KEYS")

func test_keys_are_plain_focusable_buttons() -> void:
	# The D-pad walks the grid through the built-in focus neighbours and A presses via ui_accept — that only works
	# for a Button that can take focus.
	for b in _buttons():
		assert_eq(b.focus_mode, Control.FOCUS_ALL, "key '%s' must be focusable for the pad to reach it" % b.text)


# --- open / close --------------------------------------------------------------------------------------------

func test_open_shows_and_seats_focus_on_the_first_key() -> void:
	_kb.open(_target)
	assert_true(_kb.visible, "open() shows the keyboard")
	assert_eq(_kb._target, _target, "open() binds the field")
	assert_true(_kb._first.has_focus(), "focus lands on the first key so the first A press types")

func test_close_hides_returns_focus_to_the_field_and_forgets_it() -> void:
	_kb.open(_target)
	_kb.close()
	assert_false(_kb.visible, "close() hides the keyboard")
	assert_true(_target.has_focus(), "focus goes back to the field the player was editing")
	assert_null(_kb._target, "the target is released on close")

func test_done_key_closes() -> void:
	_kb.open(_target)
	_button(PlayerText.PAD_KEY_DONE).pressed.emit()
	assert_false(_kb.visible, "the Done key is wired to close()")

func test_close_survives_a_freed_target() -> void:
	var gone := LineEdit.new()
	add_child(gone)
	_kb.open(gone)
	gone.free()
	_kb.close()
	assert_false(_kb.visible, "closing after the field was freed still hides (is_instance_valid guard)")
	assert_null(_kb._target, "and clears the stale handle")


# --- Typing --------------------------------------------------------------------------------------------------

func test_keys_append_and_emit_text_changed_by_hand() -> void:
	_kb.open(_target)
	_button("R").pressed.emit()
	_button("A").pressed.emit()
	_button(PlayerText.PAD_KEY_SPACE).pressed.emit()
	assert_eq(_target.text, "RA ", "each key appends its character; Space appends a space")
	assert_eq(_changes, ["R", "RA", "RA "], "text_changed fires once per key with the new text (code-set .text never emits it)")

func test_delete_removes_the_last_character_and_emits() -> void:
	_kb.open(_target)
	_target.text = "RAX"
	_button(PlayerText.PAD_KEY_DELETE).pressed.emit()
	assert_eq(_target.text, "RA", "Delete drops the trailing character")
	assert_eq(_changes, ["RA"], "Delete emits text_changed so the Begin gate re-evaluates")

func test_delete_on_an_empty_field_is_silent() -> void:
	_kb.open(_target)
	_button(PlayerText.PAD_KEY_DELETE).pressed.emit()
	assert_eq(_target.text, "", "nothing to delete")
	assert_eq(_changes.size(), 0, "no spurious text_changed when nothing changed")

func test_typing_is_capped_at_max_len() -> void:
	_kb.open(_target)
	_target.text = "X".repeat(_kb.MAX_LEN)
	_button("A").pressed.emit()
	assert_eq(_target.text.length(), _kb.MAX_LEN, "a full field refuses the key")
	assert_eq(_changes.size(), 0, "a refused key emits nothing")
	_button(PlayerText.PAD_KEY_DELETE).pressed.emit()
	assert_eq(_target.text.length(), _kb.MAX_LEN - 1, "Delete still works at the cap")

func test_keys_do_nothing_without_a_target() -> void:
	_button("A").pressed.emit()
	_button(PlayerText.PAD_KEY_DELETE).pressed.emit()
	assert_eq(_target.text, "", "an unopened keyboard writes nowhere")
	assert_eq(_changes.size(), 0, "and emits nothing")


# --- ui_cancel -----------------------------------------------------------------------------------------------

func _cancel_event() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	return ev

func test_ui_cancel_closes_the_keyboard_while_open() -> void:
	_kb.open(_target)
	_kb._input(_cancel_event())
	assert_false(_kb.visible, "START / B (ui_cancel) closes the keyboard rather than backing out of the screen")
	assert_true(_target.has_focus(), "and the field gets its focus back")

func test_ui_cancel_is_ignored_while_hidden() -> void:
	# A hidden keyboard must not swallow the screen's own Back — the guard is `visible`.
	_kb._input(_cancel_event())
	assert_false(_kb.visible, "still hidden")
	assert_null(_kb._target, "no target was touched")
