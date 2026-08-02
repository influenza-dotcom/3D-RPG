extends CanvasLayer
## NameEntryDialog — a small, real-time MODAL text box for naming things (right now: a claimed pet, via
## [[claim_interaction.gd]]). Code-built and registered as an autoload so ONE instance survives scene changes,
## mirroring the other screen overlays (StatsScreen et al.).
##
## REAL-TIME, like the backpack / stats screen: it does NOT pause the world — enemies keep moving and you stay
## vulnerable while you type (Deus Ex / immersive-sim ethos). It frees the mouse for the box (restored on close), and
## player CONTROL is suppressed while it's up because it registers in InputManager.gameplay_suppressed() — so the
## WASD you type goes into the text field instead of walking the character. (The hotbar / interact keys are
## event-driven, and a focused LineEdit consumes printable keys as handled, so typing digits/letters can't switch
## weapons or fire other verbs.)
##
## Usage: NameEntryDialog.open(title, default_text, on_confirm) where on_confirm is a Callable(String). Enter (or the
## Confirm button) commits the typed name; Esc (or Cancel) closes without calling back. The caller is responsible for
## validating / defaulting an empty name — we pass the raw stripped text through.

signal confirmed(text: String)
signal cancelled


const MAX_NAME_LENGTH := 24  ## keep names sane / fit the prompt; designers can't author past this from the box

var _root: Control
var _title: Label
var _line: LineEdit
var _is_open := false
var _on_confirm: Callable = Callable()
var _prev_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED  ## OS mouse mode before we opened (restored on close)


func _ready() -> void:
	layer = 121                                  # above the player menus (120), below OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep receiving input even if something else pauses the tree
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _is_open


## Open the box seeded with `default_text`, titled `title`; on confirm, call `on_confirm` with the typed (stripped)
## name. No-op if already open or while a conversation is up (typing a name mid-dialogue would be nonsense). The box
## frees the cursor and selects the seed text so a single keystroke replaces it (or Enter keeps it as-is).
func open(title: String, default_text: String, on_confirm: Callable) -> void:
	if _is_open or DialogueManager.is_active():
		return
	_on_confirm = on_confirm
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = MenuStyle.title_text(title)  # runtime re-title must re-apply the skin's casing (make_title only cases its ctor arg)
	_line.text = default_text
	_is_open = true
	_root.visible = true
	# Grab focus + select-all here (we run from the caller's _physics_process, AFTER this frame's key events were
	# delivered) so the keystroke that TRIGGERED the claim has already passed and won't land in the field.
	_line.grab_focus()
	_line.select_all()


## Commit: hand the stripped text to the callback, then close. Closing first keeps our state clean before the callback
## runs (it may do anything, incl. opening another dialog).
func _confirm() -> void:
	if not _is_open:
		return
	var text := _line.text.strip_edges()
	var cb := _on_confirm
	close()
	confirmed.emit(text)
	if cb.is_valid():
		cb.call(text)


func _cancel() -> void:
	if not _is_open:
		return
	close()
	cancelled.emit()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	_on_confirm = Callable()
	Input.mouse_mode = _prev_mouse


## Esc cancels (consume it so OptionsMenu doesn't also open behind us). Enter is handled by the LineEdit's
## text_submitted; we also accept ui_accept here for controller/keyboard parity when focus drifted off the field.
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		_confirm()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)
	add_child(_root)
	_root.add_child(MenuStyle.make_dim())

	# A FIXED-WIDTH centered card (MenuStyle.make_dialog): pinned to skin.dialog_width so a longer prompt
	# ("Name your rottweiler" vs "Name your dog", any claim_name()) can't grow the card or slide it off-centre.
	# The helper's CenterContainer keeps it dead-centre at every canvas height (792x432..495); we cap the title
	# + buttons so the fixed width holds.
	var vbox := MenuStyle.make_dialog(_root)

	_title = MenuStyle.cap_label(MenuStyle.make_title(PlayerText.NAME_DIALOG_TITLE))  # a long prompt clips with "…", never widens the card
	vbox.add_child(_title)

	_line = LineEdit.new()
	# Player-TYPED text lives in this field — it must never be looked up as a translation msgid by Godot's
	# automatic Control-text translation (atr), so the control opts out wholesale.
	_line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# The right-click menu is ENGINE-provided ("Cut"/"Copy"/"Paste"/…) and untranslatable by this project —
	# it would paint English into an otherwise localized screen. Disabled here (and on every other LineEdit
	# we build); the keyboard shortcuts it duplicates keep working.
	_line.context_menu_enabled = false
	_line.max_length = MAX_NAME_LENGTH
	_line.placeholder_text = PlayerText.CHARACTER_NAME_PLACEHOLDER
	_line.caret_blink = true
	_line.text_submitted.connect(_on_text_submitted)
	vbox.add_child(_line)

	# Confirm + Cancel split the fixed card width via EXPAND_FILL (no per-button min); both captions are static
	# and short, so clip_text never actually engages — it's just the shared discipline.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	vbox.add_child(buttons)
	var ok := MenuStyle.cap_button(Button.new())
	ok.text = PlayerText.CONFIRM
	ok.focus_mode = Control.FOCUS_NONE  # keep keyboard focus on the field so typing never leaves it
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(_confirm)
	buttons.add_child(ok)
	var cancel := MenuStyle.cap_button(Button.new())
	cancel.text = PlayerText.CANCEL
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_cancel)
	buttons.add_child(cancel)



## LineEdit Enter — text_submitted passes the field text; we ignore it and read _line in _confirm (one source).
func _on_text_submitted(_text: String) -> void:
	_confirm()
