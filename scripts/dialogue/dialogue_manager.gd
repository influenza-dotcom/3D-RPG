extends Node

## Autoload ("DialogueManager") that runs conversations. Builds a simple bottom text box + cinematic
## letterbox bars in code, frees the mouse while a line is up (the world keeps running — no pause,
## real-time like Deus Ex), and advances on PickUp (E) / ui_accept / left-click. The player script
## freezes locomotion while is_active() so it reads as a soft cinematic lock. Call start(resource).
##
## A thin COORDINATOR + FACADE: it owns the conversation state machine (which line, who's speaking, the
## pause/mouse/freeze handshake) and delegates the rest to code-built child components — DialogueView (the
## box + letterbox visuals), TtsSpeaker (reads lines aloud), MusicDucker (fades music while talking) — plus
## the CompanionRecruiter static for the recruit/dismiss contract. The children are PROCESS_MODE_ALWAYS so
## the box / choices / advancing + TTS keep running while the rest of the tree is paused.
##
## SETUP: register this script as an autoload named exactly "DialogueManager" (Project Settings →
## Autoload) so NPCs can reach it.

signal dialogue_started
signal dialogue_finished

var _active: DialogueResource = null
var _index: int = 0
var _speaker: Node = null               # the NPC frozen for the conversation; restored on finish
var _speaker_prior_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _speaker_name: String = ""          # name for the speaker label; resolved by the caller (NPC / Talkable / DialogueNPC)
var _active_voice: VoiceData = null  ## the speaking character's voice for the active conversation
var _intro_playing: bool = false  ## true during the pre-talk beat (box hidden, input can't advance)
var _choices_shown: bool = false  ## true once the response menu is revealed for the current line (NV flow)
var _pending_end: bool = false    ## the next advance ends the conversation (the "Alright." follow ack, #9)
var _face_tween: Tween  ## turns the speaker to face the player at dialog start; owned here so it runs while the speaker is frozen
var _view: DialogueView          ## the box + letterbox visuals (code-built child)
var _tts: TtsSpeaker             ## reads each line aloud via the OS text-to-speech (code-built child)
var _ducker: MusicDucker         ## fades the music bus down while a conversation is up (code-built child)
const START_DELAY: float = 0.5          # beat after interacting before the first line opens (NPC "gathers")
const DIALOGUE_FACE_TIME: float = 0.3   # seconds for the speaker to turn and face the player as the box opens
## Speaker-name colour by the speaker's disposition toward the player (#13). NEUTRAL + non-NPC -> white.
const NAME_HOSTILE := Color(0.9, 0.1, 0.1)
const NAME_FRIENDLY := Color(0.1, 0.8, 0.2)

func _ready() -> void:
	# Always-process so the box / choices / advancing + TTS keep running while the rest of the tree
	# (enemies, particles, physics) is paused during a conversation. The Music + Ambience players are
	# likewise set to process_mode = Always in the scene so audio doesn't cut out either.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Build + add the child components. Each is PROCESS_MODE_ALWAYS so it keeps running through the
	# paused world, and caches its own bus / voices in its own _ready once parented.
	_view = DialogueView.new()
	_view.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_view)
	_tts = TtsSpeaker.new()
	_tts.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_tts)
	_ducker = MusicDucker.new()
	_ducker.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ducker)

func is_active() -> bool:
	return _active != null

## The letterbox bars' slide-in duration, exposed so the camera's dialogue zoom can be timed to match.
func letterbox_time() -> float:
	return _view.letterbox_time() if _view != null else DialogueView.LETTERBOX_TIME

## Begin a conversation. Ignored if one is already running or the resource is empty.
func start(dialogue: DialogueResource, speaker: Node = null, voice: VoiceData = null, speaker_name: String = "") -> void:
	if _active != null or dialogue == null or dialogue.lines.is_empty():
		return
	_active = dialogue
	_active_voice = voice
	_index = 0
	_intro_playing = true
	_choices_shown = false
	_pending_end = false
	# Freeze the conversation partner so a talking NPC can't move, attack, or rotate-fight its
	# turn-to-face. PROCESS_MODE_DISABLED halts its whole subtree; the rest of the world runs on.
	_speaker = speaker
	_speaker_name = speaker_name
	if speaker != null:
		# End the conversation immediately if the speaker is killed mid-sentence (#5) — e.g. shot during
		# the intro beat before the world pauses. Auto-disconnected in _finish.
		if speaker.has_signal(&"died") and not speaker.died.is_connected(_on_speaker_died):
			speaker.died.connect(_on_speaker_died)
		# Let the speaker react to being talked to (e.g. an enemy hides its laser sight) BEFORE we
		# disable its processing — once frozen it can't manage that itself.
		if speaker.has_method(&"set_in_dialogue"):
			speaker.set_in_dialogue(true)
		# Guarantee the speaker faces the player as the box opens — the pre-talk turn may not have
		# finished (approach timed out / still mid-pivot). Tweened from THIS autoload (PROCESS_MODE_ALWAYS)
		# so the turn completes during the intro beat even though the speaker is about to be frozen.
		_face_speaker_to_player(speaker)
		_speaker_prior_mode = speaker.process_mode
		speaker.process_mode = Node.PROCESS_MODE_DISABLED
	# Open the box (hidden text panel + cleared name through the intro beat) and slide the bars in.
	_view.open()
	_view.set_speaker(speaker as Node3D)  # the bubble points its tail at the speaker
	_ducker.set_ducked(true)
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
	_view.reveal_panel()  # box opens with the first line
	_show_line()
	# Intro's done + the box is open: pause the world (enemies, particles, physics). DialogueManager
	# is PROCESS_MODE_ALWAYS so the box / choices / advancing keep working; TTS is OS-level and shaders
	# are GPU-side, so both keep going through the pause.
	get_tree().paused = true

func _show_line() -> void:
	var line := _active.lines[_index]
	_choices_shown = false
	# New Vegas flow: show + speak the line FIRST with only a continue prompt; the response menu (if any)
	# is revealed on the next click (_reveal_menu), so the player HEARS the line before being asked to
	# pick. The name is tinted by the speaker's disposition (#13).
	_view.show_line(line.text, _speaker_name, _speaker_name_color())
	_tts.speak(line.text, _active_voice)
	_view.show_continue_hint()

## Free the buttons spawned for the previous line so labels never stack between lines/conversations.
func _clear_choices() -> void:
	if _view != null:
		_view.clear_choices()

## Reveal the response menu for the current line AFTER the player has heard it (listen-first, #14): the
## authored choices, then the synthesized "Follow me"/"Wait here" companion affordance (if the speaker
## supports it), then a generic "Goodbye." to leave (#1). Runs on the click after the line is shown.
func _reveal_menu() -> void:
	if _view == null:
		return
	_choices_shown = true
	_view.clear_choices()
	var line := _active.lines[_index]
	if not line.choices.is_empty():
		_view.set_choices(line.choices, _on_choice_pressed)
	var follow_label := CompanionRecruiter.label_for(_speaker)
	if not follow_label.is_empty():
		_view.add_extra_choice(follow_label, _on_companion_pressed.bind(follow_label == "Wait here"))
	_view.add_extra_choice("Goodbye.", _on_goodbye_pressed)

## A choice button was pressed -> jump to its target (which re-enters the listen-first flow for that line).
func _on_choice_pressed(target: int) -> void:
	_jump_to(target)

## The generic leave option (#1): end the conversation.
func _on_goodbye_pressed() -> void:
	_finish()

## The recruit/dismiss button was pressed. Recruiting ("Follow me") acknowledges with a spoken "Alright."
## then ends on the next advance (#9); dismissing ("Wait here") re-reveals the menu so the button flips
## back to "Follow me". The follow BEHAVIOUR is the NPC's; we only invoke the contract (has_method guarded).
func _on_companion_pressed(was_following: bool) -> void:
	if _speaker == null or not is_instance_valid(_speaker):
		return
	CompanionRecruiter.apply(_speaker, was_following, get_tree())
	if was_following:
		_reveal_menu()  # dismissed — re-show the menu with the button flipped back to "Follow me"
		return
	# Recruited: acknowledge with "Alright." and end on the next advance.
	_choices_shown = false
	_pending_end = true
	_view.show_line("Alright.", _speaker_name, _speaker_name_color())
	_tts.speak("Alright.", _active_voice)
	_view.show_continue_hint()

## Speaker-name colour from the speaker's disposition toward the player (#13): HOSTILE red, FRIENDLY green,
## NEUTRAL and any non-NPC speaker white.
func _speaker_name_color() -> Color:
	if _speaker != null and is_instance_valid(_speaker) and _speaker.has_method(&"resolved_disposition"):
		match _speaker.resolved_disposition():
			Disposition.Kind.HOSTILE:
				return CBPalette.hostile()
			Disposition.Kind.FRIENDLY:
				return CBPalette.friendly()
	return Color.WHITE

## The speaker was killed mid-conversation (#5) — end immediately rather than leave the box on a corpse.
func _on_speaker_died() -> void:
	if is_active():
		_finish()

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
	# Order matters for a smooth exit — do every potentially-hitchy teardown step while the world is
	# STILL paused, then unpause last so control returns on a clean frame:
	#   • TtsSpeaker.stop() is a synchronous OS call that can stall a frame; cutting the line
	#     here (pre-unpause) hides that stall behind the frozen world instead of stuttering a live one.
	#   • Restoring the speaker's process_mode while paused lets it rejoin a still-frozen tree and then
	#     resume in lockstep with everything else, rather than taking one isolated catch-up tick.
	_tts.stop()  # stop reading the line aloud (before the world resumes — see note above)
	_ducker.set_ducked(false)  # fade the music back up
	# Unfreeze the conversation partner + let it resume conversation-specific state.
	if _speaker != null and is_instance_valid(_speaker):
		if _speaker.has_signal(&"died") and _speaker.died.is_connected(_on_speaker_died):
			_speaker.died.disconnect(_on_speaker_died)
		_speaker.process_mode = _speaker_prior_mode
		if _speaker.has_method(&"set_in_dialogue"):
			_speaker.set_in_dialogue(false)
	get_tree().paused = false  # resume the world LAST, once the hitchy teardown above is done
	_speaker = null
	_choices_shown = false
	_pending_end = false
	_speaker_name = ""
	# Close the box: drops any choice buttons so none linger into the next conversation, hides the layer,
	# and collapses the bars (the layer's hidden anyway) so they re-slide in next conversation.
	_view.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	dialogue_finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or _intro_playing:
		return
	# When the response menu is up, its Buttons drive selection — a stray click must NOT advance/skip.
	if _choices_shown:
		return
	var advance := event.is_action_pressed(&"ui_accept")
	if not advance and InputMap.has_action(&"PickUp"):
		advance = event.is_action_pressed(&"PickUp")
	if not advance and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		advance = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if advance:
		get_viewport().set_input_as_handled()
		_on_advance_click()

## A click/accept while a line is shown (listen-first, #14). Ends if we're on the "Alright." ack;
## reveals the response menu on a decision line OR the final line (authored choices + Follow me +
## Goodbye); otherwise advances to the next spoken line — so clicking "skips through" the monologue.
func _on_advance_click() -> void:
	if _pending_end:
		_finish()
		return
	var is_last := _index + 1 >= _active.lines.size()
	if _active.lines[_index].has_choices() or is_last:
		_reveal_menu()
	else:
		_advance()

## Rotate the speaker to face the player as a conversation opens. Only turns things that SHOULD face you
## (a Character/NPC, or a DialogueNPC/Talkable that opted in via turn_to_face); an inanimate speaker (a
## car / terminal) stays put. Tweened on THIS autoload (PROCESS_MODE_ALWAYS) so it turns the speaker even
## after start() freezes it, and the short turn finishes within START_DELAY's intro beat.
func _face_speaker_to_player(speaker: Node) -> void:
	var spk := speaker as Node3D
	if spk == null:
		return
	var should_face: bool = spk is Character or ("turn_to_face" in spk and spk.turn_to_face)
	if not should_face:
		return
	var player := get_tree().get_first_node_in_group(&"Player") as Node3D
	if not is_instance_valid(player):
		return
	var to := player.global_position - spk.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	# This model's front is +Z (matches NPC._face_point); take the SHORT way around the ±PI seam.
	var target_yaw := spk.rotation.y + angle_difference(spk.rotation.y, atan2(to.x, to.z))
	if absf(target_yaw - spk.rotation.y) < 0.05:
		return  # already facing closely enough — no turn needed
	if _face_tween and _face_tween.is_valid():
		_face_tween.kill()
	_face_tween = create_tween()
	_face_tween.tween_property(spk, "rotation:y", target_yaw, DIALOGUE_FACE_TIME)
