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
var _face_tween: Tween  ## turns the speaker to face the player at dialog start; owned here so it runs while the speaker is frozen
var _view: DialogueView          ## the box + letterbox visuals (code-built child)
var _tts: TtsSpeaker             ## reads each line aloud via the OS text-to-speech (code-built child)
var _ducker: MusicDucker         ## fades the music bus down while a conversation is up (code-built child)
const START_DELAY: float = 0.5          # beat after interacting before the first line opens (NPC "gathers")
const DIALOGUE_FACE_TIME: float = 0.3   # seconds for the speaker to turn and face the player as the box opens

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
	# Freeze the conversation partner so a talking NPC can't move, attack, or rotate-fight its
	# turn-to-face. PROCESS_MODE_DISABLED halts its whole subtree; the rest of the world runs on.
	_speaker = speaker
	_speaker_name = speaker_name
	if speaker != null:
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
	# Clear the PREVIOUS line's choice buttons first so they never stack across a re-render / branch
	# jump / the companion Follow<->Wait toggle — the view's set_choices/add_extra_choice only APPEND.
	_clear_choices()
	# The speaker name comes from the talking character (NPC / Talkable / DialogueNPC display_name,
	# resolved into _speaker_name by start()); DialogueLine carries no per-line speaker.
	_view.show_line(line.text, _speaker_name)
	_tts.speak(line.text, _active_voice)
	# Branch point vs linear line: choices swap the continue hint for selectable Buttons. The view spawns
	# one Button per choice, each firing _on_choice_pressed bound to its target; an empty choices array
	# leaves the continue hint up for a linear line.
	_view.set_choices(line.choices, _on_choice_pressed)
	# Companion recruit/dismiss: if the speaker supports the follow contract, splice in a synthesized
	# "Follow me" / "Wait here" button as an EXTRA affordance on every line. Authored .tres choices are
	# untouched; on a linear line the [E]/click continue prompt stays alongside it.
	_add_companion_choice()

## Free the buttons spawned for the previous line so labels never stack between lines/conversations.
func _clear_choices() -> void:
	if _view != null:
		_view.clear_choices()

## A choice button was pressed -> jump to its target. Thin wrapper so the connected callable and the
## jump logic are separable.
func _on_choice_pressed(target: int) -> void:
	_jump_to(target)

## Splice a synthesized recruit/dismiss button into the current line when the speaker implements the
## companion contract (can_recruit / start_following / stop_following / is_following — all has_method
## guarded). Shows "Wait here" while it's following, "Follow me" when it CAN be recruited, nothing
## otherwise — so a non-recruitable speaker (inanimate, hostile, already-leader) is wholly unaffected.
## The button rides ON TOP of the line's authored choices (or its plain continue prompt), so existing
## conversations gain the option without re-authoring any .tres. CompanionRecruiter resolves the label;
## the spawn + the press-callback wiring stay here in the coordinator.
func _add_companion_choice() -> void:
	if _speaker == null or not is_instance_valid(_speaker) or _view == null:
		return
	var label := CompanionRecruiter.label_for(_speaker)
	if label.is_empty():
		return
	var following: bool = label == "Wait here"
	_view.add_extra_choice(label, _on_companion_pressed.bind(following))

## The recruit/dismiss button was pressed. Hands off to CompanionRecruiter (resolving the player from the
## "Player" group for start_following), then RE-RENDERS the line so the button flips "Follow me" <-> "Wait
## here" live and the conversation stays open to continue. The follow BEHAVIOUR is the NPC's; we only
## invoke the contract here (all has_method guarded, so a partial implementation is safe).
func _on_companion_pressed(was_following: bool) -> void:
	if _speaker == null or not is_instance_valid(_speaker):
		return
	CompanionRecruiter.apply(_speaker, was_following, get_tree())
	# Re-render the same line so the toggled state shows immediately (no advance — conversation continues).
	if _active != null:
		_show_line()

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
		_speaker.process_mode = _speaker_prior_mode
		if _speaker.has_method(&"set_in_dialogue"):
			_speaker.set_in_dialogue(false)
	get_tree().paused = false  # resume the world LAST, once the hitchy teardown above is done
	_speaker = null
	_speaker_name = ""
	# Close the box: drops any choice buttons so none linger into the next conversation, hides the layer,
	# and collapses the bars (the layer's hidden anyway) so they re-slide in next conversation.
	_view.close()
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
