extends Node

## Autoload ("DialogueManager") that runs conversations. Builds a simple bottom text box in code,
## pauses the game + frees the mouse while a line is up, advances on PickUp (E) / ui_accept / left-click,
## and restores pause + mouse capture when the script ends. Call DialogueManager.start(resource).
##
## SETUP: register this script as an autoload named exactly "DialogueManager" (Project Settings →
## Autoload) so NPCs can reach it. It runs with PROCESS_MODE_ALWAYS so the box still works while the
## tree is paused.

signal dialogue_started
signal dialogue_finished

var _active: DialogueResource = null
var _index: int = 0
var _layer: CanvasLayer
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _hint: Label                  # plain "continue" prompt; hidden while a line shows choices
var _choices_box: VBoxContainer   # holds one Button per choice; emptied each line

func _ready() -> void:
	# Keep processing input while the tree is paused so the box can advance/close.
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_active() -> bool:
	return _active != null

## Begin a conversation. Ignored if one is already running or the resource is empty.
func start(dialogue: DialogueResource) -> void:
	if _active != null or dialogue == null or dialogue.lines.is_empty():
		return
	_active = dialogue
	_index = 0
	if _layer == null:
		_build_ui()
	_show_line()
	_layer.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	dialogue_started.emit()

func _show_line() -> void:
	var line := _active.lines[_index]
	_speaker_label.text = line.speaker
	_speaker_label.visible = not line.speaker.is_empty()
	_text_label.text = line.text
	# Branch point vs linear line: choices swap the continue hint for selectable Buttons.
	_clear_choices()
	if line.has_choices():
		_hint.visible = false
		_choices_box.visible = true
		for choice in line.choices:
			var b := Button.new()
			b.text = choice.text
			# FOCUS_NONE so ui_accept (Enter/Space) can't re-press a focused button; selection is
			# mouse-click driven (the mouse is already MOUSE_MODE_VISIBLE per start()).
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_on_choice_pressed.bind(choice.target))
			_choices_box.add_child(b)
	else:
		_choices_box.visible = false
		_hint.visible = true

## Free the buttons spawned for the previous line so labels never stack between lines/conversations.
func _clear_choices() -> void:
	if _choices_box == null:
		return
	for c in _choices_box.get_children():
		c.queue_free()

## A choice button was pressed -> jump to its target. Thin wrapper so the connected callable and the
## jump logic are separable.
func _on_choice_pressed(target: int) -> void:
	_jump_to(target)

## Jump the cursor to `target` (an index into _active.lines) and re-render, or finish the conversation.
## Symmetric with _advance(): _advance increments, _jump_to sets. DialogueLine.END (-1), any negative,
## and out-of-range all map to _finish() so a mis-authored target ends cleanly instead of crashing.
func _jump_to(target: int) -> void:
	if target == DialogueLine.END or target < 0 or target >= _active.lines.size():
		_finish()
	else:
		_index = target
		_show_line()

func _advance() -> void:
	_index += 1
	if _index >= _active.lines.size():
		_finish()
	else:
		_show_line()

func _finish() -> void:
	_active = null
	_clear_choices()  # drop any choice buttons so none linger into the next conversation
	if _layer:
		_layer.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	dialogue_finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	# Choice lines are driven by their Buttons (Button.pressed -> _on_choice_pressed), not by
	# accept/PickUp/click, so the advance path below must NOT fire while choices are showing.
	if _active.lines[_index].has_choices():
		return
	var advance := event.is_action_pressed(&"ui_accept")
	if not advance and InputMap.has_action(&"PickUp"):
		advance = event.is_action_pressed(&"PickUp")
	if not advance and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		advance = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if advance:
		get_viewport().set_input_as_handled()
		_advance()

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90  # above the HUD
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 80
	_panel.offset_right = -80
	_panel.offset_top = -200
	_panel.offset_bottom = -40
	_layer.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_speaker_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_text_label)
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	_choices_box.visible = false  # only shown for branch lines (see _show_line)
	vbox.add_child(_choices_box)
	_hint = Label.new()
	_hint.text = "[E] / click to continue"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.55)
	_hint.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_hint)
