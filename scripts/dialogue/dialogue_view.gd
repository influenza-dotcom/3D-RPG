class_name DialogueView
extends Node

## The dialogue box's VISUALS — the bottom text panel + cinematic letterbox bars, built in code, pulled
## out of DialogueManager. A code-built child of the manager (PROCESS_MODE_ALWAYS owner, so the box /
## choices keep rendering + advancing while the world is paused). Owns the CanvasLayer and every Control
## under it; the manager drives it through open() / close() / show_line() / set_choices() /
## add_extra_choice() / clear_choices(). Choice buttons fire back a Callable the manager supplies, so the
## jump / re-render logic stays in the coordinator.

const LETTERBOX_FRACTION: float = 0.12  # each bar's height as a fraction of the screen height
const LETTERBOX_TIME: float = 0.4       # seconds for the bars to slide in

var _layer: CanvasLayer
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _hint: Label                  # plain "continue" prompt; hidden while a line shows choices
var _choices_box: VBoxContainer   # holds one Button per choice; emptied each line
var _bar_top: ColorRect           # cinematic letterbox bars; slid in on start, collapsed on finish
var _bar_bottom: ColorRect
var _letterbox_tween: Tween

## The letterbox bars' slide-in duration, exposed so the camera's dialogue zoom can be timed to match.
func letterbox_time() -> float:
	return LETTERBOX_TIME

## Open the box for a new conversation: build the UI lazily, show the layer, and keep the text panel +
## speaker name hidden through the intro beat (so the PRIOR conversation's speaker name doesn't flash
## before show_line() sets the new one). Slides the letterbox bars in.
func open() -> void:
	if _layer == null:
		_build_ui()
	_layer.visible = true
	_panel.visible = false  # keep the text box hidden during the intro beat
	# Hide + clear the name label during the intro too, so the PRIOR conversation's speaker name
	# doesn't flash for the half-second before show_line() sets the new one.
	_speaker_label.text = ""
	_speaker_label.visible = false
	_animate_letterbox_in()

## Reveal the text panel once the intro beat is over (the box "opens" with the first line).
func reveal_panel() -> void:
	if _panel != null:
		_panel.visible = true

## Tear down the box on finish: drop any lingering choice buttons, hide the layer, and collapse the
## bars (the layer's hidden anyway) so they re-slide in next conversation.
func close() -> void:
	clear_choices()  # drop any choice buttons so none linger into the next conversation
	if _layer:
		_layer.visible = false
	if _bar_top:
		_bar_top.offset_bottom = 0.0
		_bar_bottom.offset_top = 0.0

## Show one line's text + speaker name. The speaker name comes from the talking character (resolved by
## the manager); an empty name hides the label. Caller drives TTS + choices separately, in order.
func show_line(text: String, speaker_name: String, name_color: Color = Color.WHITE) -> void:
	_speaker_label.text = speaker_name
	_speaker_label.visible = not speaker_name.is_empty()
	_speaker_label.add_theme_color_override("font_color", name_color)  # tinted by disposition (#13)
	_text_label.text = text

## Populate the line's authored choices: swap the continue hint for one selectable Button per choice.
## Each button fires `cb` bound to its target index (FOCUS_NONE so ui_accept can't re-press a focused
## button — selection is mouse-click driven). An empty `choices` leaves the hint up for a linear line.
func set_choices(choices: Array, cb: Callable) -> void:
	if choices.is_empty():
		_choices_box.visible = false
		_hint.visible = true
		return
	_hint.visible = false
	_choices_box.visible = true
	for choice in choices:
		var b := Button.new()
		b.text = choice.text
		# FOCUS_NONE so ui_accept (Enter/Space) can't re-press a focused button; selection is
		# mouse-click driven (the mouse is already MOUSE_MODE_VISIBLE per the manager's start()).
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(cb.bind(choice.target))
		_choices_box.add_child(b)

## Splice one EXTRA button (label `text`) on top of the line's authored choices / continue prompt, firing
## `cb` when pressed — the synthesized companion recruit/dismiss affordance. Forces the choices box visible
## even on an otherwise-linear line.
func add_extra_choice(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # mouse-click driven, like the authored choice buttons
	b.pressed.connect(cb)
	_choices_box.add_child(b)
	_choices_box.visible = true  # ensure the box shows even on an otherwise-linear line
	_hint.visible = false        # a response menu is up — drop the "continue" prompt

## Listen-first state: show the line's text with only a continue affordance (no response menu yet). The
## menu, if any, is revealed by the manager on the next click — New Vegas-style: hear it, THEN choose.
func show_continue_hint() -> void:
	clear_choices()
	_choices_box.visible = false
	_hint.visible = true

## Free the buttons spawned for the previous line so labels never stack between lines/conversations.
func clear_choices() -> void:
	if _choices_box == null:
		return
	for c in _choices_box.get_children():
		c.queue_free()

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90  # above the HUD
	add_child(_layer)
	# Cinematic letterbox bars, added first so they draw BEHIND the text box. Collapsed to zero
	# height; _animate_letterbox_in() slides them in on start.
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.offset_bottom = 0.0
	_layer.add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.offset_top = 0.0
	_layer.add_child(_bar_bottom)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 80
	_panel.offset_right = -80
	_panel.offset_top = -200
	_panel.offset_bottom = -40
	# Invisible background — drop the PanelContainer's default box (the "ugly" bg). The text carries its
	# own outline (below) so it stays readable floating over the world.
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_layer.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 18)
	# Outlined so the text reads against the world now that the panel box is gone.
	_text_label.add_theme_constant_override("outline_size", 6)
	_text_label.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(_text_label)
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	_choices_box.visible = false  # only shown for branch lines (see set_choices)
	vbox.add_child(_choices_box)
	_hint = Label.new()
	_hint.text = "[E] / click to continue"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.55)
	_hint.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_hint)
	# Speaker name, top-left like Fallout — separate from the bottom box, drawn last so it's on top.
	# Outlined so it reads against either the letterbox bar or the world. Filled/toggled in show_line.
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 26)
	_speaker_label.add_theme_constant_override("outline_size", 6)
	_speaker_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_speaker_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_speaker_label.offset_left = 32
	_speaker_label.offset_top = 60
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_speaker_label)

## Slide the cinematic letterbox bars in from the top and bottom edges (each to LETTERBOX_FRACTION
## of the screen height). close() collapses them instantly since the layer hides on end.
func _animate_letterbox_in() -> void:
	if _bar_top == null:
		return
	var h: float = get_viewport().get_visible_rect().size.y * LETTERBOX_FRACTION
	if _letterbox_tween and _letterbox_tween.is_valid():
		_letterbox_tween.kill()
	_letterbox_tween = create_tween().set_parallel(true)
	_letterbox_tween.tween_property(_bar_top, "offset_bottom", h, LETTERBOX_TIME)
	_letterbox_tween.tween_property(_bar_bottom, "offset_top", -h, LETTERBOX_TIME)
