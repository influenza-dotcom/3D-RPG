extends PanelContainer

## The smallest on-screen keyboard that lets a PAD player type into a LineEdit: a focusable grid of A-Z / 0-9
## plus Space / Delete / Done. open(target) shows it and seats focus on the first key; D-pad/stick walk the
## grid, A presses a key (the keys are plain Buttons under ui_accept), START (ui_cancel) or Done closes it and
## hands focus back to the field. Text is written straight to target.text and text_changed is emitted by hand
## (setting .text in code never emits it). Deliberately no shift, no symbols, no layout budget — a quick door
## for the one screen (character creation) that gates Begin on a typed name.

const KEYS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const COLUMNS := 12
const MAX_LEN := 24

var _target: LineEdit = null
var _first: Button = null

func _init() -> void:
	visible = false
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	add_child(grid)
	for ch in KEYS:
		var b := _add_key(grid, ch, _type.bind(ch))
		if _first == null:
			_first = b
	_add_key(grid, PlayerText.PAD_KEY_SPACE, _type.bind(" "))
	_add_key(grid, PlayerText.PAD_KEY_DELETE, _delete)
	_add_key(grid, PlayerText.PAD_KEY_DONE, close)

func _add_key(grid: GridContainer, label: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(22, 0)
	b.pressed.connect(on_press)
	grid.add_child(b)
	return b

func open(target: LineEdit) -> void:
	_target = target
	visible = true
	if _first != null:
		_first.grab_focus()

func close() -> void:
	visible = false
	if _target != null and is_instance_valid(_target):
		_target.grab_focus()
	_target = null

func _type(ch: String) -> void:
	if _target == null or _target.text.length() >= MAX_LEN:
		return
	_target.text += ch
	_target.text_changed.emit(_target.text)

func _delete() -> void:
	if _target == null or _target.text.is_empty():
		return
	_target.text = _target.text.left(_target.text.length() - 1)
	_target.text_changed.emit(_target.text)

## Runs BEFORE the owning screen's _input (a later child gets _input first), so ui_cancel closes the keyboard
## instead of backing out of the whole screen.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
