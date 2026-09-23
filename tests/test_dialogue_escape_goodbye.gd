extends GutTest
## Escape (ui_cancel) is Goodbye while the dialogue response menu is up (DialogueManager._unhandled_input).
##
## Pushed through the REAL root viewport, so the whole autoload _unhandled_input walk runs. Autoloads join /root in
## [autoload] row order and Godot delivers _unhandled_input in REVERSE tree order, so a LATER row hears Escape first.
## OptionsMenu marks every ui_cancel handled, even when open() refuses because a conversation is up, so
## DialogueManager must sit on a row AFTER OptionsMenu or Escape never reaches the Goodbye row.

var _prev_mouse_mode: Input.MouseMode
var _prev_paused: bool


func before_each() -> void:
	_prev_mouse_mode = Input.mouse_mode
	_prev_paused = get_tree().paused


func after_each() -> void:
	DialogueManager.abort()  # no-op when the conversation already ended
	if OptionsMenu.is_open():
		OptionsMenu.close()
	get_tree().paused = _prev_paused
	Input.mouse_mode = _prev_mouse_mode
	# The Goodbye row's buttons and Options' rebuilt tab pages are detached then queue_free'd; let them go.
	await wait_process_frames(1)


## Put the live DialogueManager on a one-line conversation with its response menu (and the pinned Goodbye row)
## painted by the real _reveal_menu. start() is skipped on purpose: its intro beat awaits a timer and then pauses
## the tree, and the input walk is what this file tests.
func _open_response_menu() -> void:
	var line := DialogueLine.new()
	line.text = "Anything else?"
	var convo := DialogueResource.new()
	convo.lines = [line]
	DialogueManager._active = convo
	DialogueManager._index = 0
	DialogueManager._intro_playing = false
	DialogueManager._view.open()
	DialogueManager._reveal_menu()


## A press of the live ui_cancel key binding (Escape), sent to the root viewport like a real key press.
func _push_escape() -> void:
	var press: InputEventKey = null
	for e in InputMap.action_get_events(&"ui_cancel"):
		if e is InputEventKey:
			press = (e as InputEventKey).duplicate() as InputEventKey
			break
	assert_not_null(press, "ui_cancel must have a keyboard binding (Escape) to press")
	if press == null:
		return
	press.pressed = true
	get_tree().root.push_input(press)


func test_escape_on_the_response_menu_says_goodbye() -> void:
	_open_response_menu()
	assert_true(DialogueManager.is_active(), "setup: the conversation is live with its response menu up")
	_push_escape()
	assert_false(DialogueManager.is_engaged(),
		"Escape on the response menu must fire the Goodbye row and end the conversation. If it is still up, a LATER "
		+ "[autoload] row ate the press first: DialogueManager must sit below OptionsMenu in project.godot")
	assert_false(OptionsMenu.is_open(), "the same Escape must not also open Options")


func test_escape_with_no_conversation_still_opens_options() -> void:
	assert_false(DialogueManager.is_engaged(), "setup: no conversation")
	assert_false(OptionsMenu.is_open(), "setup: Options starts closed")
	_push_escape()
	assert_true(OptionsMenu.is_open(),
		"with no conversation DialogueManager must leave Escape unhandled, so it still toggles Options")
