extends Node

## @system Control-Lock And Immunity
## @seam is_engaged() (_active != null) = a conversation exists at all — the unpaused intro beat + the menu-suspension that is_active() hides — feeding world_frozen() immunity, Player.die() + _on_speaker_died teardown, _suspend_for_menu's box-hide + CONNECT_ONE_SHOT closed->resume one-shot, UI._push_quest_toast's toast queue, and Radio's dialogue duck.
## @risk Dropping is_engaged() from InputManager.world_frozen() loses immunity in the unpaused intro beat — an enemy shoots the frozen player with no error (C66).
## @risk die() gating on is_active() not is_engaged() skips abort() during a sub-menu suspension — the menu's close then re-pauses + re-opens the box over the death cinematic.
## @risk A suspending sub-menu (Shop/Install/Chess/Atm/Heal/LevelUp/Loot-exchange) refuse path that returns WITHOUT emitting `closed` strands the convo _suspended forever — box hidden, tree paused, soft-lock, no crash.
## @risk Speaker menus are duck-typed via has_method/has_signal scans (buy/sell, do_heal, install_carried, ai_search_depth, deposit/withdraw, set_in_dialogue/died); a rename silently drops the option with no compile error.
## @test res://tests/test_dialogue.gd
## @test res://tests/test_dialogue_suspend_closed.gd
## @test res://tests/test_dialogue_speaker_contracts.gd
## Autoload ("DialogueManager") that runs conversations. Builds a simple bottom text box + cinematic
## letterbox bars in code, frees the mouse while a line is up (the world keeps running — no pause,
## real-time like Deus Ex), and advances on PickUp (E) / ui_accept / left-click. The player script
## freezes locomotion while is_active() so it reads as a soft cinematic lock. Call start(resource).
##
## A thin COORDINATOR + FACADE: it owns the conversation state machine (which line, who's speaking, the
## pause/mouse/freeze handshake) and delegates the rest to code-built child components — DialogueView (the
## box + letterbox visuals), MusicDucker (fades the music bus down while talking) and DialogueMusicBed (plays
## the looping dialogue music track under the conversation) — plus the CompanionRecruiter static
## for the recruit/dismiss contract. Lines are read aloud by the SpeechTts autoload (the in-game Flite TTS).
##
## DUCK-TYPING CONTRACT (M14): this reaches into ~8 subsystems via has_method / has_signal scans (Merchant buy/sell,
## Healer do_heal/heal_cost, Bonfire rest, LevelUp level_up_stat/level_up_cost, Atm deposit/withdraw, the NPC speaker's set_in_dialogue/
## note_speaking/provoke/is_following/resolved_disposition + died signal, Player add_money/notify_toast, and the
## shop/heal/level-up screens' open_* + closed signal) — NOT typed refs, deliberately, to avoid the Merchant <->
## ShopScreen <-> DialogueManager compile cycle (a typed interface would re-form it). So a rename on any of those
## SILENTLY drops the option/handshake with no compile error — the contract is pinned by tests/test_dialogue_speaker_contracts.gd.
## The children are PROCESS_MODE_ALWAYS so the box / choices / advancing keep running while the tree is paused.
##
## SETUP: register this script as an autoload named exactly "DialogueManager" (Project Settings →
## Autoload) so NPCs can reach it.

## Faction registry (preloaded by path) for the reputation-reward consequence (WR-3).
const Factions = preload("res://scripts/faction/factions.gd")

## A conversation opened. Carries the DialogueResource being played so a listener can react to WHICH
## conversation started (quest hooks, analytics, per-dialogue HUD). Direct listeners must accept that arg (or
## declare it optional), or Godot errors at emit time. A `.bind()` connection must NOT rely on arg position (the
## resource is PREPENDED before bound args): see ui.gd, which folds its crosshair-hide into a plain handler for
## that reason.
signal dialogue_started(resource: DialogueResource)
signal dialogue_finished
## A sub-menu (Trade / Heal / Level Up / Install / Play Chess / Bank / Exchange Gear) opened over a LIVE
## conversation, which is now SUSPENDED (box hidden; _speaker / _index / _active kept). `reason` names the menu
## ("trade", "heal", "level_up", "install", "chess", "bank", "exchange") so a listener can react per-menu. OBSERVABILITY ONLY:
## the resume is still driven by the sub-menu's own one-shot `closed` -> _resume_from_menu handshake (which
## also survives a mid-menu death), NOT by any listener of this signal — do not wire resume off it.
signal dialogue_suspended(reason: String)
## The suspending sub-menu closed and the conversation is back at its response menu — the mirror of
## dialogue_suspended. Fires ONLY on a successful resume; if the speaker / conversation vanished while the menu
## was up the conversation ends instead and dialogue_finished fires (never this).
signal dialogue_resumed

var _active: DialogueResource = null
var _index: int = 0
var _speaker: Node = null               # the NPC frozen for the conversation; restored on finish
var _speaker_prior_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _speaker_name: String = ""          # name for the speaker label; resolved by the caller (NPC / Talkable / DialogueNPC)
var _active_voice: VoiceData = null  ## the speaking character's voice for the active conversation
var _intro_playing: bool = false  ## true during the pre-talk beat (box hidden, input can't advance)
var _choices_shown: bool = false  ## true once the response menu is revealed for the current line (NV flow)
var _pending_end: bool = false    ## the next advance ends the conversation (the "Alright." follow ack, #9)
var _suspended: bool = false      ## conversation paused behind a sub-menu (trade/level-up/heal/exchange); resumes on its close
var _pending_menu_closed: Signal  ## the suspended sub-menu's `closed` signal, tracked so _finish() can drop the one-shot if the conversation ends BEFORE the menu does (the player dies mid-menu) — else that stale `closed` would fire _resume_from_menu into a torn-down / next conversation
var _line_token: int = 0          ## bumped on every spoken line; a pending auto-advance timer only fires if its token still matches (so a manual click / new line cancels it)
var _speech_finished_callable: Callable = Callable()  ## current TTS completion hook, disconnected when a line is skipped before its generated audio finishes
var _face_tween: Tween  ## turns the speaker to face the player at dialog start; owned here so it runs while the speaker is frozen
var _view: DialogueView          ## the box + letterbox visuals (code-built child)
var _ducker: MusicDucker         ## fades the music bus down while a conversation is up (code-built child)
var _music_bed: DialogueMusicBed ## plays the looping dialogue music track under the conversation (code-built child); inert until GameSettings.dialogue.dialogue_music is authored
var _face_light: DialogueFaceLight  ## keys a light onto the speaker's face while talking (code-built child); fades in/out with the conversation
# The intro delay before the first line + the speaker face-turn duration are designer knobs on
# GameSettings.dialogue (dialogue_intro_delay / dialogue_speaker_face_duration). Speaker-name colour is
# resolved live by _speaker_name_color() via CBPalette.disposition_color (the old NAME_* consts were dead).

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
	_ducker = MusicDucker.new()
	_ducker.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ducker)
	# The dialogue music bed: a looping track faded in under the conversation. Sets its own
	# PROCESS_MODE_ALWAYS in _ready (it must keep PLAYING through the pause, not just processing), and
	# reads its stream/level/fades from GameSettings.dialogue there — an unauthored dialogue_music
	# leaves it inert, so conversations play dry exactly as before.
	_music_bed = DialogueMusicBed.new()
	add_child(_music_bed)
	# The dialogue face light: a single spotlight keyed onto whoever the current speaker is, faded in/out with the
	# conversation. ALWAYS so it keeps lighting the frozen speaker's face through the dialogue pause (like the others).
	_face_light = DialogueFaceLight.new()
	_face_light.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_face_light)

func is_active() -> bool:
	return _active != null and not _suspended  # suspended (a sub-menu is up) reads inactive so that menu could open

## True whenever a conversation EXISTS AT ALL — including one merely SUSPENDED behind a sub-menu (Trade / Heal /
## Level Up / Install / Exchange Gear). is_active() reports a suspension as inactive (so the sub-menu is allowed to
## open); this does NOT. The player's die() tears the conversation down on THIS, not is_active(): otherwise dying
## with a sub-menu up skips abort(), and die()'s own _close_open_modals() then closes the sub-menu, whose `closed`
## fires _resume_from_menu — re-pausing the tree + re-opening the box over the death cinematic (the very re-pause
## that freezes the node-bound death tween, which the abort exists to prevent).
func is_engaged() -> bool:
	return _active != null

## Settle the conversation music duck INSTANTLY (no fade) and drop its latch — the facade over
## MusicDucker.reset(). Called by Player.die() right after ScopeCoordinator.reset(), for the matching reason:
## abort() ends the conversation with a 0.4 s restore FADE that would still be writing the music bus while the
## death cinematic's world duck (DeathMix) writes it every frame. No-op if nothing was ducked.
func reset_music_duck() -> void:
	if _ducker != null:
		_ducker.reset()

## The NPC currently being talked to (null when no conversation is active) -- so the head-look can let ONLY the
## speaker turn its head during a conversation, while every other NPC holds still.
func current_speaker() -> Node:
	return _speaker if is_active() and is_instance_valid(_speaker) else null


## Hard-end the conversation from OUTSIDE the dialogue flow — the PLAYER died mid-conversation (an enemy can
## shoot during the unpaused intro beat, and the player is frozen on is_active so they can't dodge). Without
## this the box would open over the death cinematic and get_tree().paused would freeze the node-bound death
## tween — the mirror of the _on_speaker_died teardown, but for OUR side of the conversation. Safe to call
## when nothing is active.
func abort() -> void:
	if _active != null:
		_finish()

## The letterbox bars' slide-in duration, exposed so the camera's dialogue zoom can be timed to match.
func letterbox_time() -> float:
	return _view.letterbox_time() if _view != null else GameSettings.dialogue.letterbox_slide_in_duration

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
	if speaker != null and speaker_name != "":
		# Only a real conversation PARTNER advances a "talk to <name>" objective — an inanimate source (a Readable
		# note / terminal passes speaker=null with a cosmetic title) must NOT complete a talk objective by name
		# collision. Keyed by the STABLE identity (Slice 3), with the resolved name as the authored-display fallback.
		GameState.notify_talk(_speaker_identity(speaker, speaker_name), StringName(speaker_name))
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
		# Key a light onto the speaker's face for the conversation (fades in, then STATIC — placed once at the face's
		# rest pose, it does not ride the head-look; a speaker with no head gets none). Set before the freeze —
		# begin() just remembers the target; the light itself is placed + driven ALWAYS from _process.
		if _face_light != null:
			_face_light.begin(speaker)
		_speaker_prior_mode = speaker.process_mode
		speaker.process_mode = Node.PROCESS_MODE_DISABLED
	# Open the box (hidden text panel + cleared name through the intro beat) and slide the bars in.
	_view.open()
	_ducker.set_ducked(true)
	_music_bed.set_bed_playing(true)  # swell the dialogue music bed in under the conversation
	# The world keeps running through the intro beat so the camera swing / NPC turn / zoom animate;
	# it gets paused once the box opens (below). The cursor is HIDDEN while a line is read and only shown once
	# the response menu is up (_sync_dialogue_cursor); look stays suppressed (MouseInput gates on CAPTURED) and
	# player.gd freezes movement on is_active() during the intro.
	_choices_shown = false  # the box opens reading the first line, not on the menu
	_sync_dialogue_cursor()
	dialogue_started.emit(_active)  # _active == dialogue (set above); hand listeners the resource being played
	# Slight beat before they speak: the NPC turn / camera focus / zoom / letterbox play first, THEN
	# the box opens with the first line (+ TTS). Bail if the conversation ended during the wait.
	await get_tree().create_timer(GameSettings.dialogue.dialogue_intro_delay).timeout
	if _active != dialogue:
		return
	_intro_playing = false
	_view.reveal_panel()  # box opens with the first line
	_show_line()
	if _active != dialogue:
		return
	# Intro's done + the box is open: pause the world (enemies, particles, physics). DialogueManager
	# is PROCESS_MODE_ALWAYS so the box / choices / advancing keep working; TTS is OS-level and shaders
	# are GPU-side, so both keep going through the pause.
	get_tree().paused = true

func _show_line() -> void:
	var line := _current_line_or_finish("showing line")
	if line == null:
		return
	_choices_shown = false
	# "Stranger until introduced": if THIS line is the one where the speaker names themselves (reveals_name),
	# learn the name NOW — before we compute the label — so the revealing line already shows the real name in
	# its own speaker slot (and every surface from here on). Only a real character speaker has a name to reveal.
	if line.reveals_name and _speaker_is_character():
		GameState.reveal_name(_speaker_name, _speaker_identity(_speaker, _speaker_name))
	# New Vegas flow: show + speak the line FIRST with only a continue prompt; the response menu (if any)
	# is revealed on the next click (_reveal_menu), so the player HEARS the line before being asked to
	# pick. The name is tinted by the speaker's disposition (#13).
	_view.show_line(line.text, _displayed_speaker_name(), _speaker_name_color())
	_begin_line_speech(line.text)
	_view.show_continue_hint()
	_sync_dialogue_cursor()  # reading a line -> hide the cursor (the menu reveal shows it)

## Speak `text` (TTS), pulse the speaker's talking presentation (head-bob + Tomodachi mouth), and when
## auto_advance is on, advance after the real TTS completion if audio is playing, else the text estimate.
## Shared by every spoken line (normal lines + the recruit "Alright." ack).
func _begin_line_speech(text: String) -> void:
	_disconnect_speech_finished()
	var speech_token := SpeechTts.speak_dialogue(text, _active_voice)
	var secs := _line_seconds(text)
	# Drive the speaker's mouth + head-bob for the utterance (no-op for an inanimate speaker / one with no body).
	if _speaker != null and is_instance_valid(_speaker) and _speaker.has_method(&"note_speaking"):
		_speaker.note_speaking(secs)
	# Seat the dialogue music bed slightly under the voice for the same spoken window (the bed's talk duck —
	# a designer knob, dialogue_music_talk_duck_db). Pulsed for EVERY spoken line, including an inanimate /
	# null speaker's (a terminal, a Readable note): the voice reads aloud either way, and it's the voice the
	# duck makes room for. Released by _stop_speaker_talking (menu up / conversation end) or its own estimate.
	if _music_bed != null:
		_music_bed.note_line_speech(secs)
	_line_token += 1  # invalidates any still-pending auto-advance timer from the previous line
	if GameSettings.dialogue.auto_advance:
		var tok := _line_token
		if speech_token > 0:
			_speech_finished_callable = _auto_advance_from_speech.bind(tok, speech_token)
			SpeechTts.dialogue_speech_finished.connect(_speech_finished_callable, CONNECT_ONE_SHOT)
		else:
			# process_always so it ticks through the paused conversation; token-guarded so a manual click wins.
			get_tree().create_timer(secs, true).timeout.connect(_auto_advance.bind(tok))

## Estimated seconds a line is "spoken" -- its character count at the designer's per-char rate, clamped. Drives
## the talking-animation envelope, and the auto-advance delay when no TTS audio is playing.
func _line_seconds(text: String) -> float:
	var d: DialogueSettings = GameSettings.dialogue
	return clampf(float(text.length()) * d.auto_advance_seconds_per_char, d.auto_advance_min_seconds, d.auto_advance_max_seconds)

func _auto_advance_from_speech(finished_speech_token: int, tok: int, expected_speech_token: int) -> void:
	if finished_speech_token != expected_speech_token:
		return
	_speech_finished_callable = Callable()
	_auto_advance(tok)

func _disconnect_speech_finished() -> void:
	if _speech_finished_callable.is_valid() and SpeechTts.dialogue_speech_finished.is_connected(_speech_finished_callable):
		SpeechTts.dialogue_speech_finished.disconnect(_speech_finished_callable)
	_speech_finished_callable = Callable()

## A line's spoken time elapsed: advance exactly as a click would (next line, or reveal the menu on a choice /
## last line), UNLESS the player already advanced (token moved), the menu is up, or the convo ended.
func _auto_advance(tok: int) -> void:
	if _active == null or _intro_playing or _choices_shown or tok != _line_token:
		return
	_on_advance_click()

## Free the buttons spawned for the previous line so labels never stack between lines/conversations.
func _clear_choices() -> void:
	if _view != null:
		_view.clear_choices()

## Stop the speaker's talking presentation (head-bob + mouth) the instant it's no longer delivering a spoken line —
## the response menu is going up, or the conversation is ending. The talking animation runs on an ESTIMATED
## per-line duration (NPC.note_speaking), so without this cut the head keeps bobbing while the player reads the
## choices, and for a beat after the box closes as the NPC returns to idle — reading as "bobbing when it isn't
## talking". Duck-typed + validity-guarded like the note_speaking pulse; no-op for a speaker without the method.
## The music bed's talk duck tracks this exact envelope, so its swell-back rides the same call — released
## BEFORE the speaker guard, since a null/inanimate speaker never bobbed but did duck the bed.
func _stop_speaker_talking() -> void:
	if _music_bed != null:
		_music_bed.note_line_speech_stop()
	if _speaker != null and is_instance_valid(_speaker) and _speaker.has_method(&"note_speaking_stop"):
		_speaker.note_speaking_stop()

## Reveal the response menu for the current line AFTER the player has heard it (listen-first, #14): the
## authored choices, then the synthesized "Follow me"/"Wait here" companion affordance (if the speaker
## supports it), then a generic "Goodbye." to leave (#1). Runs on the click after the line is shown.
func _reveal_menu() -> void:
	if _view == null or _active == null:
		return  # _active can be null if a stale choice/companion button fires after _finish() (buttons queue_free deferred)
	_stop_speaker_talking()  # the line's been heard; the player's now reading choices, so the NPC should hold still
	_choices_shown = true
	_view.clear_choices()
	var line := _current_line_or_finish("revealing choices")
	if line == null:
		return
	if not line.choices.is_empty():
		_view.set_choices(line.choices, _on_choice_pressed)
	var follow_label := CompanionRecruiter.label_for(_speaker)
	if not follow_label.is_empty():
		# Bind the BEHAVIOUR predicate, not a comparison against the label text: the label is display-only
		# (rewording/localizing "Wait here" must never flip recruit into dismiss).
		_view.add_extra_choice(follow_label, _on_companion_pressed.bind(CompanionRecruiter.following(_speaker)))
	if _speaker_merchant() != null:
		_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_TRADE, _on_trade_pressed)
	if _speaker_healer() != null:
		_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_HEAL, _on_heal_pressed)
	if _speaker_bonfire() != null:
		_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_REST, _on_rest_pressed)
	if _speaker_levelup() != null:
		_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_LEVEL_UP, _on_level_up_pressed)
	if _speaker_installer() != null:
		_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_INSTALL, _on_install_pressed)
	if _speaker_chess() != null:
		_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_PLAY_CHESS, _on_chess_pressed)
	if _speaker_atm() != null:
		_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_BANK, _on_bank_pressed)
	if _speaker_exchange_npc() != null:
		_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_EXCHANGE_GEAR, _on_exchange_pressed)
	_view.add_extra_choice(PlayerText.DIALOGUE_OPTION_GOODBYE, _on_goodbye_pressed)
	_sync_dialogue_cursor()  # the response menu is up -> show the cursor so the player can click an option

## A choice button was pressed -> apply its consequences (on a passed gate), then jump to its target (which
## re-enters the listen-first flow for that line). `passed` is the gate result from DialogueView.set_choices.
func _on_choice_pressed(choice: DialogueChoice, passed: bool = true) -> void:
	if passed:
		_apply_choice_effects(choice)
		_jump_to(choice.target)
	else:
		_jump_to(choice.target_on_fail)  # a failed gate routes to its fail branch (default END), no consequences

## Apply a choice's authored consequences: world flags + quest start/advance/complete go through the GameState
## autoload; give-item / give-money resolve the live player. All optional (each empty/null/zero field skips).
func _apply_choice_effects(choice: DialogueChoice) -> void:
	if choice.set_flag != &"":
		GameState.set_flag(choice.set_flag, choice.set_flag_value)
	if choice.start_quest_on_choice != null:
		GameState.start_quest(choice.start_quest_on_choice)
	if choice.advance_quest_id != &"" and choice.advance_objective_id != &"":
		GameState.advance_objective(choice.advance_quest_id, choice.advance_objective_id)
	if choice.complete_quest_id != &"":
		GameState.complete_quest(choice.complete_quest_id)
	if choice.give_money != 0.0 or choice.give_item_id != &"":
		var player := _find_player()
		if is_instance_valid(player):
			if choice.give_money != 0.0:
				player.add_money(choice.give_money)
			if choice.give_item_id != &"" and choice.give_item_count > 0 and player.inventory != null:
				var item := ItemDb.restore_item(choice.give_item_id)
				if item != null:
					var added := player.inventory.add(item, choice.give_item_count)
					if added < choice.give_item_count:
						# Bag full — surface the shortfall instead of silently eating a (possibly quest-critical) item;
						# a soft-lock risk if a key handed via dialogue just vanishes. Uses the NEUTRAL inventory_full
						# line: a dialogue GIFT isn't a quest reward, so the quest_rewards_full wording (which names
						# "quest reward items") stays exclusive to QuestTracker._grant_quest_rewards.
						var msg := PlayerText.inventory_full(choice.give_item_count - added)
						if player.has_method(&"notify_toast"):
							player.notify_toast(msg, Color(1.0, 0.6, 0.3))
						else:
							push_warning("DialogueManager: " + msg)
	# WR-3 writes: reputation change (a faction warms/sours to the player's words) + aggro (a rude/threatening
	# line provokes the speaker, who attacks on exit). Both optional (empty/zero/false skips).
	if choice.reward_reputation_faction_id != "" and choice.reward_reputation != 0.0:
		var fac := Factions.by_id(choice.reward_reputation_faction_id)
		if fac != null:
			Reputation.add_reputation(fac, choice.reward_reputation)
	if choice.aggro_speaker and _speaker != null and is_instance_valid(_speaker) and _speaker.has_method(&"provoke"):
		_speaker.provoke(_find_player())

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
	_view.show_line("Alright.", _displayed_speaker_name(), _speaker_name_color())
	_begin_line_speech("Alright.")
	_view.show_continue_hint()
	_sync_dialogue_cursor()  # back to reading a line -> hide the cursor

## Suspend the conversation (hide the box, KEEP _speaker / _index / _active) and open a sub-menu via
## `open_call`; when the menu emits `closed`, resume right back at the response menu instead of booting the
## player out. is_active() reads false while suspended, so the sub-menu (which refuses to open during an
## ACTIVE dialogue) is allowed to open.
func _suspend_for_menu(reason: String, open_call: Callable, closed: Signal) -> void:
	_suspended = true
	_pending_menu_closed = closed  # remembered so _finish() can drop this one-shot if the convo ends before the menu (mid-menu death)
	_view.set_layer_hidden(true)
	if not closed.is_connected(_resume_from_menu):
		closed.connect(_resume_from_menu, CONNECT_ONE_SHOT)
	# Announce the suspension BEFORE opening the menu: a screen that refuses to open emits `closed` synchronously
	# inside open_call (-> _resume_from_menu -> dialogue_resumed), so emitting here first keeps suspended->resumed
	# in order even on that instant-refuse path.
	dialogue_suspended.emit(reason)
	open_call.call()

## A suspending sub-menu just closed: re-show the box and drop the player back at the choices. If the
## speaker / conversation vanished while the menu was up, end cleanly instead of restoring a dead box.
func _resume_from_menu() -> void:
	if not _suspended:
		return
	_suspended = false
	if _speaker == null or not is_instance_valid(_speaker) or _active == null:
		_finish()
		return
	get_tree().paused = true  # re-assert OUR pause. Since 2026-08-09 no sub-menu unpauses on close (the station screens are real-time), so this is normally a no-op — kept because a resumed conversation MUST be frozen, and that must not depend on what a sub-menu did or didn't do to the tree.
	_view.set_layer_hidden(false)
	_reveal_menu()  # back at the choices where you picked Trade / Heal / Level Up / Exchange (re-shows the cursor)
	if _active == null:
		return
	dialogue_resumed.emit()  # mirror of dialogue_suspended; only the successful-resume path reaches here (the vanished path _finish()ed above)

## The "Trade" option (Merchant component): SUSPEND the conversation and open the shop — closing the shop
## returns you to the dialogue rather than ending it.
func _on_trade_pressed() -> void:
	var merchant := _speaker_merchant()
	var player := _find_player()
	if merchant != null and is_instance_valid(player):
		_suspend_for_menu("trade", func() -> void: ShopScreen.open_shop(merchant, player), ShopScreen.closed)
	else:
		_finish()

## The speaker NPC's Merchant child (its shop), or null. Shallow scan — it sits as a direct child, like
## Talkable. DUCK-TYPED (has buy + sell) + returned as a bare Node deliberately: typing it `Merchant` would
## pull this autoload into a Merchant <-> ShopScreen <-> DialogueManager class-compile cycle.
func _speaker_merchant() -> Node:
	if _speaker == null or not is_instance_valid(_speaker):
		return null
	for c in _speaker.get_children():
		if c.has_method(&"buy") and c.has_method(&"sell"):
			return c
	return null

## The "Exchange Gear" option (any conversational NPC with a backpack): SUSPEND the conversation and open the
## two-way transfer screen on their gear — the consensual sibling of pickpocketing, with the NPC's carry
## capacity capping what you can hand them. Closing it returns you to the dialogue rather than ending it;
## LootScreen refuses while is_active, and suspension flips is_active() false so it can open. The else branch
## (missing NPC / no player) _finish()es instead.
func _on_exchange_pressed() -> void:
	var npc := _speaker_exchange_npc()
	var player := _find_player()
	if npc != null and is_instance_valid(player):
		_suspend_for_menu("exchange", func() -> void: LootScreen.exchange(npc, player), LootScreen.closed)
	else:
		_finish()

## The speaker when it's an ALLY actively FOLLOWING the player and carrying a backpack — gear exchange is
## a companion privilege (you kit out your crew), not something every stranger in the street offers. Same
## duck-typed shape as the merchant/healer scans (is_following lives on NPC; an inanimate Talkable speaker
## has neither it nor an `inventory`). Re-checked at press time too, so a companion dismissed from this
## same menu can't still open the exchange.
func _speaker_exchange_npc() -> Node:
	if _speaker == null or not is_instance_valid(_speaker):
		return null
	if not _speaker.has_method(&"is_following") or not _speaker.is_following():
		return null
	var inv: Variant = _speaker.get(&"inventory")
	return _speaker if inv is CharacterInventory else null

## The "Heal" option (shown when the speaker has a Healer component): SUSPEND the conversation and open the
## heal screen — closing it returns you to the dialogue rather than ending it. HealScreen.open_heal refuses
## while DialogueManager.is_active(), and suspension makes is_active() false so it can open; the else branch
## (missing healer / no player) _finish()es instead.
func _on_heal_pressed() -> void:
	var healer := _speaker_healer()
	var player := _find_player()
	if healer != null and is_instance_valid(player):
		_suspend_for_menu("heal", func() -> void: HealScreen.open_heal(healer, player), HealScreen.closed)
	else:
		_finish()

## The speaker NPC's Healer child (its medic), or null. Shallow scan + DUCK-TYPED (has do_heal + heal_cost),
## returned as a bare Node like _speaker_merchant — typing it Healer would form a class-compile cycle.
func _speaker_healer() -> Node:
	if _speaker == null or not is_instance_valid(_speaker):
		return null
	for c in _speaker.get_children():
		if c.has_method(&"do_heal") and c.has_method(&"heal_cost"):
			return c
	return null

## The "Rest" option (shown when the speaker has a Bonfire component): rest at it (full heal + set the
## respawn point), then close the conversation.
func _on_rest_pressed() -> void:
	var bonfire := _speaker_bonfire()
	var player := _find_player()
	if bonfire != null and is_instance_valid(player):
		bonfire.rest(player)
	_finish()

## The speaker NPC's Bonfire child (its checkpoint), or null. Shallow scan + DUCK-TYPED (has rest), returned
## as a bare Node like the merchant / healer scans.
func _speaker_bonfire() -> Node:
	if _speaker == null or not is_instance_valid(_speaker):
		return null
	for c in _speaker.get_children():
		if c.has_method(&"rest"):
			return c
	return null

## The "Level Up" option (shown when the speaker has a LevelUp component): SUSPEND the conversation and open
## the level-up menu — closing it returns you to the dialogue rather than ending it. LevelUpScreen refuses
## while DialogueManager.is_active(), and suspension makes is_active() false so it can open; the else branch
## (missing station / no player) _finish()es instead.
func _on_level_up_pressed() -> void:
	var station := _speaker_levelup()
	var player := _find_player()
	if station != null and is_instance_valid(player):
		_suspend_for_menu("level_up", func() -> void: LevelUpScreen.open_level_up(station, player), LevelUpScreen.closed)
	else:
		_finish()

## The speaker NPC's LevelUp child (its level-up station), or null. Shallow scan + DUCK-TYPED (has
## level_up_stat + level_up_cost), a bare Node like the merchant / healer / bonfire scans.
func _speaker_levelup() -> Node:
	if _speaker == null or not is_instance_valid(_speaker):
		return null
	for c in _speaker.get_children():
		if c.has_method(&"level_up_stat") and c.has_method(&"level_up_cost"):
			return c
	return null

## The "Install" option (ChipInstaller component): SUSPEND the conversation and open the install screen — closing
## it returns you to the dialogue rather than ending it (mirrors _on_trade_pressed).
func _on_install_pressed() -> void:
	var installer := _speaker_installer()
	var player := _find_player()
	if installer != null and is_instance_valid(player):
		_suspend_for_menu("install", func() -> void: ChipInstallScreen.open_install(installer, player), ChipInstallScreen.closed)
	else:
		_finish()

## The speaker NPC's ChipInstaller child (its upgrade mechanic), or null. Shallow scan + DUCK-TYPED (has
## install_carried + install_fee), a bare Node like the merchant / healer scans — typing it ChipInstaller would
## pull this autoload into a ChipInstaller <-> ChipInstallScreen <-> DialogueManager class-compile cycle.
func _speaker_installer() -> Node:
	if _speaker == null or not is_instance_valid(_speaker):
		return null
	for c in _speaker.get_children():
		if c.has_method(&"install_carried") and c.has_method(&"install_fee"):
			return c
	return null

## The "Play Chess" option (ChessMatch component): SUSPEND the conversation and open the blindfold-chess board —
## closing the match returns you to the dialogue rather than ending it (mirrors _on_install_pressed).
func _on_chess_pressed() -> void:
	var match_node := _speaker_chess()
	var player := _find_player()
	if match_node != null and is_instance_valid(player):
		_suspend_for_menu("chess", func() -> void: ChessScreen.open_match(match_node, player), ChessScreen.closed)
	else:
		_finish()

## The speaker NPC's ChessMatch child (its blindfold-chess opponent), or null. Shallow scan + DUCK-TYPED (has
## ai_search_depth + display_opponent_name), a bare Node like the merchant / healer scans — typing it ChessMatch
## would pull this autoload into a ChessMatch <-> ChessScreen <-> DialogueManager class-compile cycle.
func _speaker_chess() -> Node:
	if _speaker == null or not is_instance_valid(_speaker):
		return null
	for c in _speaker.get_children():
		if c.has_method(&"ai_search_depth") and c.has_method(&"display_opponent_name"):
			return c
	return null

## The "Bank" option (Atm component): SUSPEND the conversation and open the ledger terminal — closing it returns
## you to the dialogue rather than ending it (mirrors _on_chess_pressed). ONE option covers both directions and
## both signs of the account: the terminal's own screen owns deposit / withdraw / pay-down, so a teller NPC needs
## no extra buttons here. AtmScreen.open_atm refuses while DialogueManager.is_active(), and suspension makes
## is_active() false so it can open; every one of its refuse paths emits `closed`, which is what keeps the
## suspension from stranding (the @risk at the top of this file).
func _on_bank_pressed() -> void:
	var atm := _speaker_atm()
	var player := _find_player()
	if atm != null and is_instance_valid(player):
		_suspend_for_menu("bank", func() -> void: AtmScreen.open_atm(atm, player), AtmScreen.closed)
	else:
		_finish()

## The speaker NPC's Atm child (its ledger terminal), or null. Shallow scan + DUCK-TYPED (has deposit +
## withdraw), a bare Node like the merchant / healer scans — typing it Atm would pull this autoload into an
## Atm <-> AtmScreen <-> DialogueManager class-compile cycle (the same cycle AtmScreen itself dodges by holding
## its terminal as a plain Node).
func _speaker_atm() -> Node:
	if _speaker == null or not is_instance_valid(_speaker):
		return null
	for c in _speaker.get_children():
		if c.has_method(&"deposit") and c.has_method(&"withdraw"):
			return c
	return null

## The real human player (NOT a companion — companions join the &"Player" group for targeting but are NPCs).
func _find_player() -> Player:
	for n in get_tree().get_nodes_in_group(Groups.PLAYER):
		if n is Player:
			return n as Player
	return null

## Is the current speaker a real CHARACTER (an NPC) rather than an inanimate DialogueNPC (terminal / sign) or a
## null-speaker note? resolved_disposition() is the NPC-only marker (the same one _speaker_name_color keys on), so
## a terminal / readable never gets Stranger-masked — only actual people hide their names.
func _speaker_is_character() -> bool:
	return _speaker != null and is_instance_valid(_speaker) and _speaker.has_method(&"resolved_disposition")

## Slice 3 (stable identity): the quest/known-names key for a conversation partner — the speaker's identity_key()
## (NPC: NpcData.id, falling back to the authored display name) when it exposes one (duck-typed, like the NPC
## probes above), else the resolved speaker-name string, so an inanimate DialogueNPC / any non-NPC speaker keeps
## today's name key. Feeds notify_talk (start) and reveal_name (_show_line); display labels never read this.
func _speaker_identity(speaker: Node, speaker_name: String) -> StringName:
	if speaker != null and is_instance_valid(speaker) and speaker.has_method(&"identity_key"):
		var key: StringName = speaker.identity_key()
		if key != &"":
			return key
	return StringName(speaker_name)

## The name to actually PAINT on the speaker label: the real name masked to "Stranger" until introduced when the
## speaker is a character (see _speaker_is_character / GameState.public_name), else the raw resolved name (a note's
## cosmetic title, a terminal's label — never masked). _speaker_name always holds the TRUE resolved name.
func _displayed_speaker_name() -> String:
	return GameState.public_name(_speaker_name) if _speaker_is_character() else _speaker_name

## Speaker-name colour (#13): a recruited COMPANION is blue (ally), else by disposition toward the player —
## HOSTILE red, FRIENDLY green, NEUTRAL and any non-NPC speaker white.
func _speaker_name_color() -> Color:
	if _speaker != null and is_instance_valid(_speaker) and _speaker.has_method(&"resolved_disposition"):
		var is_ally: bool = _speaker.has_method(&"is_following") and _speaker.is_following()
		return CBPalette.disposition_color(is_ally, _speaker.resolved_disposition(), Color.WHITE)
	return Color.WHITE

## The speaker was killed mid-conversation (#5) — end immediately rather than leave the box on a corpse.
## is_ENGAGED, not is_active: the conversation still EXISTS while suspended behind a sub-menu (is_active()
## reads false there), and a speaker death mid-suspension must still tear it down — mirrors the player-side
## death gate in Player.die(), and _finish() already drops the pending menu-closed one-shot for this case.
func _on_speaker_died() -> void:
	if is_engaged():
		_finish()

## Jump the cursor to `target` (an index into _active.lines) and re-render, or continue/finish the convo.
## Symmetric with _advance(): _advance increments, _jump_to sets. CONTINUE (-2, the default) carries on to
## the NEXT line so an unconfigured choice doesn't dead-end; END (-1) and out-of-range map to _finish() so a
## mis-authored target ends cleanly instead of crashing.
func _jump_to(target: int) -> void:
	if _active == null:
		return  # a stale choice button firing after _finish() (deferred queue_free) would deref _active.lines below
	if target == DialogueLine.CONTINUE:
		_advance()  # the default: keep the conversation going to the next line
	elif target == DialogueLine.END or target < 0 or target >= _active.lines.size():
		_finish()
	else:
		_index = target
		_show_line()

func _current_line_or_finish(context: String) -> DialogueLine:
	if _active == null:
		return null
	if _index < 0 or _index >= _active.lines.size():
		push_warning("DialogueManager: invalid line index %d while %s; ending conversation" % [_index, context])
		_finish()
		return null
	var line: DialogueLine = _active.lines[_index]
	if line == null:
		push_warning("DialogueManager: missing DialogueLine at index %d while %s; ending conversation" % [_index, context])
		_finish()
		return null
	return line

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
	_disconnect_speech_finished()
	# Order matters for a smooth exit — do every potentially-hitchy teardown step while the world is
	# STILL paused, then unpause last so control returns on a clean frame:
	#   • Cut the spoken line during the still-paused teardown so it ends cleanly with the box (the addon's
	#     stop is a cheap AudioStreamPlayer.stop(), but keeping it here preserves the tidy exit ordering).
	#   • Restoring the speaker's process_mode while paused lets it rejoin a still-frozen tree and then
	#     resume in lockstep with everything else, rather than taking one isolated catch-up tick.
	SpeechTts.stop_dialogue()  # stop reading the line aloud (before the world resumes — see note above)
	_ducker.set_ducked(false)  # fade the music back up
	_music_bed.set_bed_playing(false)  # fade the dialogue music bed back out (it stops once the fade lands)
	if _face_light != null:
		_face_light.end()  # release the face light — it fades out as the conversation closes
	# Unfreeze the conversation partner + let it resume conversation-specific state.
	if _speaker != null and is_instance_valid(_speaker):
		if _speaker.has_signal(&"died") and _speaker.died.is_connected(_on_speaker_died):
			_speaker.died.disconnect(_on_speaker_died)
		_speaker.process_mode = _speaker_prior_mode
		if _speaker.has_method(&"set_in_dialogue"):
			_speaker.set_in_dialogue(false)
		_stop_speaker_talking()  # kill any leftover talk envelope so the NPC doesn't bob its head as it returns to idle
	get_tree().paused = false  # resume the world LAST, once the hitchy teardown above is done
	_speaker = null
	_choices_shown = false
	_pending_end = false
	_suspended = false  # if we ended while suspended behind a menu, a later menu-close must not restore a dead box
	# Drop the suspended sub-menu's one-shot `closed` -> _resume_from_menu if it's still pending (we're ending
	# WHILE suspended — the player died mid-menu; die() aborts the conversation, THEN _close_open_modals() closes
	# the sub-menu). Without this, that close would fire _resume_from_menu and re-pause + re-open the box over the
	# death cinematic. Normally the one-shot already fired via _resume_from_menu and auto-disconnected, so the
	# is_connected guard makes this a no-op. (get_object() null-guards the default/empty Signal before any suspend.)
	if _pending_menu_closed.get_object() != null and _pending_menu_closed.is_connected(_resume_from_menu):
		_pending_menu_closed.disconnect(_resume_from_menu)
	_speaker_name = ""
	# Close the box: drops any choice buttons so none linger into the next conversation, hides the layer,
	# and collapses the bars (the layer's hidden anyway) so they re-slide in next conversation.
	_view.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	dialogue_finished.emit()

## The cursor mode for the CURRENT dialogue phase: VISIBLE while the response menu is up (so the player can
## click an option), HIDDEN while a line is being read (listen-first — nothing to click yet). Pure (reads only
## _choices_shown), so a test pins the "cursor shown iff choices" contract.
func dialogue_cursor_mode() -> int:
	return Input.MOUSE_MODE_VISIBLE if _choices_shown else Input.MOUSE_MODE_HIDDEN

## Apply dialogue_cursor_mode() to the live cursor. Called whenever the phase flips (line shown / menu
## revealed). Look stays suppressed in BOTH modes (MouseInput only rotates while CAPTURED); _finish restores
## CAPTURED for gameplay.
func _sync_dialogue_cursor() -> void:
	Input.mouse_mode = dialogue_cursor_mode() as Input.MouseMode

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
	SpeechTts.stop_dialogue()
	_disconnect_speech_finished()
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
## after start() freezes it, and the short turn finishes within the dialogue_intro_delay beat.
func _face_speaker_to_player(speaker: Node) -> void:
	var spk := speaker as Node3D
	if spk == null:
		return
	var should_face: bool = spk is Character or ("turn_to_face" in spk and spk.turn_to_face)
	if not should_face:
		return
	var player := get_tree().get_first_node_in_group(Groups.PLAYER) as Node3D
	if not is_instance_valid(player):
		return
	# Shortest-path yaw maths is shared with TalkHelpers.face_yaw (ONE source of truth), but the TWEEN is owned
	# HERE on the DialogueManager autoload (PROCESS_MODE_ALWAYS): dialogue freezes the speaker AND pauses the
	# world, so a tween bound to the player (or the frozen speaker) would stall and the turn would never finish.
	# Ours runs through the pause and completes within the dialogue_intro_delay beat.
	var shortest := TalkHelpers.face_yaw(spk, player)
	if is_nan(shortest):
		return
	if is_instance_valid(_face_tween):
		_face_tween.kill()
	_face_tween = create_tween()
	_face_tween.tween_property(spk, "global_rotation:y", shortest, GameSettings.dialogue.dialogue_speaker_face_duration)
