extends Node

## Autoload ("DialogueManager") that runs conversations. Builds a simple bottom text box + cinematic
## letterbox bars in code, frees the mouse while a line is up (the world keeps running — no pause,
## real-time like Deus Ex), and advances on PickUp (E) / ui_accept / left-click. The player script
## freezes locomotion while is_active() so it reads as a soft cinematic lock. Call start(resource).
##
## SETUP: register this script as an autoload named exactly "DialogueManager" (Project Settings →
## Autoload) so NPCs can reach it.

signal dialogue_started
signal dialogue_finished

var _active: DialogueResource = null
var _index: int = 0
var _speaker: Node = null               # the NPC frozen for the conversation; restored on finish
var _speaker_prior_mode: int = Node.PROCESS_MODE_INHERIT
var _voice: String = ""  ## cached OS text-to-speech voice; empty if TTS is unavailable/disabled
var _active_voice: VoiceData = null  ## the speaking character's voice for the active conversation
var _male_voice: String = ""    ## OS voice ids classified by name, for VoiceData's male/female toggle
var _female_voice: String = ""
var _intro_playing: bool = false  ## true during the pre-talk beat (box hidden, input can't advance)
var _music_bus: int = -1
var _music_prior_db: float = 0.0
var _music_tween: Tween
var _voice_bus: int = -1  ## the "voice" bus whose level scales the TTS (OS speech can't use a Godot bus)
var _layer: CanvasLayer
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _hint: Label                  # plain "continue" prompt; hidden while a line shows choices
var _choices_box: VBoxContainer   # holds one Button per choice; emptied each line
var _bar_top: ColorRect           # cinematic letterbox bars; slid in on start, collapsed on finish
var _bar_bottom: ColorRect
var _letterbox_tween: Tween
const LETTERBOX_FRACTION: float = 0.12  # each bar's height as a fraction of the screen height
const LETTERBOX_TIME: float = 0.4       # seconds for the bars to slide in
const START_DELAY: float = 0.5          # beat after interacting before the first line opens (NPC "gathers")
const MUSIC_DUCK_DB: float = -12.0      # how far the music bus drops while a conversation is up
const MUSIC_DUCK_TIME: float = 0.4      # fade time for the music duck / restore

func _ready() -> void:
	# Always-process so the box / choices / advancing + TTS keep running while the rest of the tree
	# (enemies, particles, physics) is paused during a conversation. The Music + Ambience players are
	# likewise set to process_mode = Always in the scene so audio doesn't cut out either.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Cache a TTS voice (prefer English) so _speak() can read each line aloud. Needs the
	# "audio/general/text_to_speech" project setting; the tts_* calls are silent no-ops without it.
	var en := DisplayServer.tts_get_voices_for_language("en")
	if not en.is_empty():
		_voice = en[0]  # default (prefer English)
	# Classify the voices into a male + female pick for VoiceData's toggle. Godot's TTS API exposes
	# no gender, so go by name (Windows ships "...David..." = male, "...Zira..." = female).
	for v in DisplayServer.tts_get_voices():
		var id := String(v.get("id", ""))
		if id.is_empty():
			continue
		if _voice.is_empty():
			_voice = id  # no English voice found — fall back to the first available
		if _is_female_name(String(v.get("name", ""))):
			if _female_voice.is_empty():
				_female_voice = id
		elif _male_voice.is_empty():
			_male_voice = id
	_music_bus = AudioServer.get_bus_index("music")
	_voice_bus = AudioServer.get_bus_index("voice")

func is_active() -> bool:
	return _active != null

## The letterbox bars' slide-in duration, exposed so the camera's dialogue zoom can be timed to match.
func letterbox_time() -> float:
	return LETTERBOX_TIME

## Begin a conversation. Ignored if one is already running or the resource is empty.
func start(dialogue: DialogueResource, speaker: Node = null, voice: VoiceData = null) -> void:
	if _active != null or dialogue == null or dialogue.lines.is_empty():
		return
	_active = dialogue
	_active_voice = voice
	_index = 0
	_intro_playing = true
	# Freeze the conversation partner so a talking NPC can't move, attack, or rotate-fight its
	# turn-to-face. PROCESS_MODE_DISABLED halts its whole subtree; the rest of the world runs on.
	_speaker = speaker
	if speaker != null:
		# Let the speaker react to being talked to (e.g. an enemy hides its laser sight) BEFORE we
		# disable its processing — once frozen it can't manage that itself.
		if speaker.has_method(&"set_in_dialogue"):
			speaker.set_in_dialogue(true)
		_speaker_prior_mode = speaker.process_mode
		speaker.process_mode = Node.PROCESS_MODE_DISABLED
	if _layer == null:
		_build_ui()
	_layer.visible = true
	_panel.visible = false  # keep the text box hidden during the intro beat below
	_animate_letterbox_in()
	_duck_music(true)
	# The world keeps running through the intro beat so the camera swing / NPC turn / zoom animate;
	# it gets paused once the box opens (below). Freeing the cursor lets you click choices and stops
	# mouse_input from rotating the view; player.gd freezes movement on is_active() during the intro.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	dialogue_started.emit()
	# Slight beat before they speak: the NPC turn / camera focus / zoom / letterbox play first, THEN
	# the box opens with the first line (+ TTS). Bail if the conversation ended during the wait.
	await get_tree().create_timer(START_DELAY).timeout
	if _active != dialogue:
		return
	_intro_playing = false
	_panel.visible = true
	_show_line()
	# Intro's done + the box is open: pause the world (enemies, particles, physics). DialogueManager
	# is PROCESS_MODE_ALWAYS so the box / choices / advancing keep working; TTS is OS-level and shaders
	# are GPU-side, so both keep going through the pause.
	get_tree().paused = true

func _show_line() -> void:
	var line := _active.lines[_index]
	_speaker_label.text = line.speaker
	_speaker_label.visible = not line.speaker.is_empty()
	_text_label.text = line.text
	_speak(line.text)
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
	_active_voice = null
	_intro_playing = false
	get_tree().paused = false  # resume the world
	DisplayServer.tts_stop()  # stop reading the line aloud
	_duck_music(false)  # fade the music back up
	# Unfreeze the conversation partner + let it resume conversation-specific state.
	if _speaker != null and is_instance_valid(_speaker):
		_speaker.process_mode = _speaker_prior_mode
		if _speaker.has_method(&"set_in_dialogue"):
			_speaker.set_in_dialogue(false)
	_speaker = null
	_clear_choices()  # drop any choice buttons so none linger into the next conversation
	if _layer:
		_layer.visible = false
	# Collapse the bars (the layer's hidden anyway) so they re-slide in next conversation.
	if _bar_top:
		_bar_top.offset_bottom = 0.0
		_bar_bottom.offset_top = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	dialogue_finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or _intro_playing:
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
	# Speaker name, top-left like Fallout — separate from the bottom box, drawn last so it's on top.
	# Outlined so it reads against either the letterbox bar or the world. Filled/toggled in _show_line.
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
## of the screen height). _finish() collapses them instantly since the layer hides on end.
func _animate_letterbox_in() -> void:
	if _bar_top == null:
		return
	var h: float = get_viewport().get_visible_rect().size.y * LETTERBOX_FRACTION
	if _letterbox_tween and _letterbox_tween.is_valid():
		_letterbox_tween.kill()
	_letterbox_tween = create_tween().set_parallel(true)
	_letterbox_tween.tween_property(_bar_top, "offset_bottom", h, LETTERBOX_TIME)
	_letterbox_tween.tween_property(_bar_bottom, "offset_top", -h, LETTERBOX_TIME)

## Read `text` aloud via the OS text-to-speech, cutting any line still being spoken (interrupt).
func _speak(text: String) -> void:
	if text.is_empty():
		return
	# Use the speaking character's VoiceData if set (its own voice id / pitch / rate), else the default.
	var vid := _voice
	var pitch := 1.0
	var rate := 1.0
	if _active_voice != null:
		var chosen := _female_voice if _active_voice.female else _male_voice
		if not chosen.is_empty():
			vid = chosen
		pitch = _active_voice.pitch
		rate = _active_voice.rate
	if vid.is_empty():
		return
	DisplayServer.tts_speak(text, vid, _tts_volume(), pitch, rate, 0, true)

## TTS volume (0-100) derived from the "voice" bus (+ Master), since OS text-to-speech can't route
## through a Godot bus — this lets a Voice volume slider scale the spoken lines independently.
func _tts_volume() -> int:
	if _voice_bus < 0:
		return 100
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.is_bus_mute(_voice_bus) or (master >= 0 and AudioServer.is_bus_mute(master)):
		return 0
	var lin := db_to_linear(AudioServer.get_bus_volume_db(_voice_bus))
	if master >= 0:
		lin *= db_to_linear(AudioServer.get_bus_volume_db(master))
	return clampi(int(round(lin * 100.0)), 0, 100)

## Fade the music bus down while a conversation is up, back up when it ends.
func _duck_music(duck: bool) -> void:
	if _music_bus < 0:
		return
	if duck:
		_music_prior_db = AudioServer.get_bus_volume_db(_music_bus)
	var target: float = _music_prior_db + MUSIC_DUCK_DB if duck else _music_prior_db
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_method(_set_music_db, AudioServer.get_bus_volume_db(_music_bus), target, MUSIC_DUCK_TIME)

func _set_music_db(db: float) -> void:
	AudioServer.set_bus_volume_db(_music_bus, db)

## Best-effort gender-by-name (Godot's TTS API exposes no gender). Covers common Windows / SAPI
## voice names; treats anything unrecognised as male.
func _is_female_name(voice_name: String) -> bool:
	var n := voice_name.to_lower()
	for hint in ["zira", "hazel", "susan", "catherine", "linda", "heera", "eva", "female", "woman", "samantha", "victoria", "karen", "aria", "jenny", "michelle", "hortense", "caroline"]:
		if n.contains(hint):
			return true
	return false
