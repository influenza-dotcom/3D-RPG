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

const SPEAKER_HEAD_OFFSET := 1.7  # metres above the speaker's origin the bubble tail points at
const BUBBLE_MAX_WIDTH := 340.0
const BUBBLE_GAP := 18.0          # px gap between the bubble's bottom and the speaker
var _speaker: Node3D              # who the bubble points at; set by the manager per conversation
var _arrow: Polygon2D            # the speech-bubble tail — a black triangle toward the speaker

## The 3D node the bubble points at — set by the manager so _process can place the bubble + tail.
func set_speaker(spk: Node3D) -> void:
	_speaker = spk

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
	_speaker = null
	_set_arrow_visible(false)
	if _layer:
		_layer.visible = false
	if _bar_top:
		_bar_top.offset_bottom = 0.0
		_bar_bottom.offset_top = 0.0

## Each frame, park the speech bubble just above the speaker (clamped on-screen) and draw the tail
## pointing down at them. Falls back to a bottom-centre anchor (no tail) if the speaker is gone or
## behind the camera. Runs even while the world is paused (the view is PROCESS_MODE_ALWAYS).
func _process(_delta: float) -> void:
	if _layer == null or not _layer.visible or _panel == null or not _panel.visible:
		_set_arrow_visible(false)
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null or not is_instance_valid(_speaker):
		_anchor_bottom_center()
		_set_arrow_visible(false)
		return
	var head := _speaker.global_position + Vector3.UP * SPEAKER_HEAD_OFFSET
	if cam.is_position_behind(head):
		_anchor_bottom_center()
		_set_arrow_visible(false)
		return
	var screen := cam.unproject_position(head)
	var vp_size := vp.get_visible_rect().size
	var size := _panel.size
	var pos := Vector2(screen.x - size.x * 0.5, screen.y - size.y - BUBBLE_GAP)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp_size.x - size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp_size.y - size.y - 8.0))
	_panel.position = pos
	_update_arrow(pos, size, screen)

func _anchor_bottom_center() -> void:
	if _panel == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	_panel.position = Vector2((vp_size.x - _panel.size.x) * 0.5, vp_size.y - _panel.size.y - 60.0)

## Draw the tail as a triangle from the bubble's bottom edge to the speaker (tip), only when the speaker
## is actually below the bubble (the usual case, since the bubble sits above their head).
func _update_arrow(bubble_pos: Vector2, bubble_size: Vector2, tip: Vector2) -> void:
	var bottom_y := bubble_pos.y + bubble_size.y
	if tip.y <= bottom_y + 2.0:
		_set_arrow_visible(false)
		return
	var base_x := clampf(tip.x, bubble_pos.x + 16.0, bubble_pos.x + bubble_size.x - 16.0)
	_arrow.polygon = PackedVector2Array([
		Vector2(base_x - 11.0, bottom_y - 1.0),
		Vector2(base_x + 11.0, bottom_y - 1.0),
		tip,
	])
	_set_arrow_visible(true)

func _set_arrow_visible(v: bool) -> void:
	if _arrow != null:
		_arrow.visible = v

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
	# Black speech bubble (rounded + bordered) with a tail — positioned near the speaker each frame in
	# _process. The tail (Polygon2D) is added FIRST so it draws under the bubble body.
	_arrow = Polygon2D.new()
	_arrow.color = Color(0.0, 0.0, 0.0, 0.9)
	_arrow.visible = false
	_layer.add_child(_arrow)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(BUBBLE_MAX_WIDTH, 0.0)
	var bubble := StyleBoxFlat.new()
	bubble.bg_color = Color(0.0, 0.0, 0.0, 0.9)
	bubble.set_corner_radius_all(12)
	bubble.set_content_margin_all(14)
	bubble.border_color = Color(1.0, 1.0, 1.0, 0.5)
	bubble.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", bubble)
	_layer.add_child(_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)
	# Speaker name as the bubble header, tinted by disposition (#13).
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 16)
	_speaker_label.add_theme_constant_override("outline_size", 4)
	_speaker_label.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(_speaker_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(BUBBLE_MAX_WIDTH - 32.0, 0.0)
	_text_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_text_label)
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	_choices_box.visible = false  # only shown once the menu is revealed (NV listen-first flow)
	vbox.add_child(_choices_box)
	_hint = Label.new()
	_hint.text = "[E] / click to continue"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	_hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_hint)

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
