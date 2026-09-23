extends GutTest

## GUT suite for the dialogue subsystem: the DialogueLine / DialogueChoice data contract, the DialogueManager
## conversation lifecycle (start, suspend/resume, speaker death, choice routing, TTS-paced auto-advance), DialogueView
## choice painting, the DialogueController holster fences, the DialogueSelector world-state pick, and the Talkable /
## DialogueNPC components. Each assert message says what broke for the player.
##
## DRIVING THE MANAGER. DialogueManager is an autoload with NO class_name, so a test builds a throwaway with
## load(DIALOGUE_MANAGER_PATH).new() and add_child_autofree()s it; its _ready only builds code-made children (the view,
## the music ducker + bed, the face light). A conversation is opened for real with start() -- which awaits
## GameSettings.dialogue.dialogue_intro_delay and then PAUSES THE TREE -- or, like test_dialogue_escape_goodbye.gd, by
## seating _active / _index directly when the intro beat is not what the test is about. before_each shortens that
## intro and turns TTS off (so no native Flite engine spins up headless); after_each puts back the tree pause, the
## cursor mode, the music bus level (first settling every built manager's duck fade, which would otherwise outlive the
## restore), the TTS switch, the tuning knobs, SpeechTts's dialogue pool and the live autoload's conversation fields. A test that needs spoken audio seats _ScriptedDialogueVoice in SpeechTts's
## dialogue pool: it never synthesises, and each utterance "finishes" only when the test releases it.
##
## STILL A SOURCE SCAN, and why: Player.die() runs the death cinematic on a Player that cannot be built in-tree under
## GUT, so that one test reads the code of die() alone (comments dropped) and pins the order that matters. The level
## swap's conversation teardown IS driven (GameRoot.load_level on an in-tree GameRoot with stand-in levels). NOT
## covered here: the abort in the two scene-RELOAD paths (GameState._load_and_reload, the console's `reload`) -- both
## end in reload_current_scene(), which would tear down the runner.
##
## Covered elsewhere: id addressing + the shipped .tres conversations (test_dialogue_ids.gd), choice consequences
## against QuestTracker (test_quest_stages.gd), every sub-menu's refuse -> closed contract
## (test_dialogue_suspend_closed.gd), Escape = Goodbye (test_dialogue_escape_goodbye.gd), the face light and music bed
## (test_dialogue_face_light.gd / test_dialogue_music_bed.gd), the look-at alpha opt-out (test_ink_outline.gd).
##
## Freeing: Resources (RefCounted) are released by scope; bare Nodes built off-tree are .free()'d by hand.

const DIALOGUE_MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"
const DIALOGUE_NPC_PATH := "res://scripts/components/dialogue_npc.gd"
const TALKABLE_PATH := "res://scripts/components/talkable.gd"
const SPEECH_TTS_PATH := "res://managers/SpeechTts.gd"
const GAME_ROOT_PATH := "res://scripts/world/game_root.gd"
## Longer than the shortened intro beat (before_each) and than the shortened auto-advance estimate, so an await of
## this many seconds proves the pending timer has fired.
const OUTLAST_TIMERS_SEC := 0.3

class _ForgiveRecorder extends Node:
	var forgive_count: int = 0

	func forgive_provoke() -> void:
		forgive_count += 1

class _StatBuffPlayerStub extends Node:
	var sheet := CharacterStats.new()
	var mods := {}

	func stats_or_default() -> CharacterStats:
		return sheet

	func status_stat_modifier(stat: StringName) -> float:
		return float(mods.get(String(stat), 0.0))

## A conversation partner that can be killed mid-conversation: DialogueManager.start() connects its `died`.
class _MortalSpeaker extends Node:
	signal died

## A speaker that records being provoked -- the observable for a choice's aggro_speaker consequence.
class _ProvokeRecorder extends Node:
	var provoked: int = 0

	func provoke(_by: Node) -> void:
		provoked += 1

## A conversation partner standing in a level. DialogueManager._finish hands its speaker back through
## set_in_dialogue(false); this records, each time, whether the speaker was still in the world at that moment.
class _LevelSpeaker extends Node3D:
	var released_in_world: Array = []

	func set_in_dialogue(on: bool) -> void:
		if not on:
			released_in_world.append(is_inside_tree())

## Stand-in for a sub-menu (Trade / Heal / ...): all _suspend_for_menu needs is its `closed` signal.
class _FakeMenu extends Node:
	signal closed

## One utterance of _ScriptedDialogueVoice; its audio "ends" when the test emits `finished`.
class _Utterance extends RefCounted:
	signal finished

## A dialogue voice that never synthesises: seated in SpeechTts's dialogue pool it lets speak_dialogue() start "audio"
## (a real token) whose completion the test controls utterance by utterance.
class _ScriptedDialogueVoice extends TextToSpeech1D:
	var utterances: Array[_Utterance] = []

	func _ready() -> void:
		pass  # no native TextToSpeechEngine -- say() below never needs one

	func say(_text, _voice = "cmu_us_aew", _speed = 1.0) -> void:
		var u := _Utterance.new()
		utterances.append(u)
		await u.finished

var _prior_paused: bool
var _prior_mouse_mode: Input.MouseMode
var _prior_tts_enabled: bool
var _prior_intro_delay: float
var _prior_auto_advance: bool
var _prior_advance_min: float
var _prior_advance_max: float
var _prior_music_db: float
var _music_bus: int = -1
var _prior_live_active: DialogueResource
var _prior_live_suspended: bool
var _scripted_voice: _ScriptedDialogueVoice = null
var _had_pool_voice: bool = false
var _prior_pool_voice: Variant = null
## Every manager _live_manager() built this test. after_each settles their music ducks BEFORE restoring the bus:
## an abort()/_finish() starts a 0.4 s restore fade that would otherwise keep writing the shared "music" bus after
## the restore (GUT frees the manager only once after_each returns), leaking a quieter bus into every later file.
var _managers: Array = []


func before_each() -> void:
	_prior_paused = get_tree().paused
	_prior_mouse_mode = Input.mouse_mode
	_prior_tts_enabled = Settings.tts_enabled
	var d: DialogueSettings = GameSettings.dialogue
	_prior_intro_delay = d.dialogue_intro_delay
	_prior_auto_advance = d.auto_advance
	_prior_advance_min = d.auto_advance_min_seconds
	_prior_advance_max = d.auto_advance_max_seconds
	_music_bus = AudioServer.get_bus_index(MusicDucker.MUSIC_BUS)
	if _music_bus >= 0:
		_prior_music_db = AudioServer.get_bus_volume_db(_music_bus)
	_prior_live_active = DialogueManager._active
	_prior_live_suspended = DialogueManager._suspended
	Settings.tts_enabled = false
	d.dialogue_intro_delay = 0.05


func after_each() -> void:
	if _scripted_voice != null:
		SpeechTts.stop_dialogue()  # every pending utterance is now stale, so releasing them below reports nothing
		if is_instance_valid(_scripted_voice):
			for u in _scripted_voice.utterances:
				u.finished.emit()
		if _had_pool_voice:
			SpeechTts._dialogue_pool[VoiceData.MALE_DEFAULT] = _prior_pool_voice
		else:
			SpeechTts._dialogue_pool.erase(VoiceData.MALE_DEFAULT)
		_scripted_voice = null
	DialogueManager._active = _prior_live_active
	DialogueManager._suspended = _prior_live_suspended
	Settings.tts_enabled = _prior_tts_enabled
	var d: DialogueSettings = GameSettings.dialogue
	d.dialogue_intro_delay = _prior_intro_delay
	d.auto_advance = _prior_auto_advance
	d.auto_advance_min_seconds = _prior_advance_min
	d.auto_advance_max_seconds = _prior_advance_max
	# Kill any duck / restore fade still in flight (reset_music_duck() is the no-fade settle Player.die() uses), THEN
	# put the bus back -- in that order, or the fade overwrites the restore on the next frame.
	for m in _managers:
		if is_instance_valid(m):
			m.reset_music_duck()
	_managers.clear()
	if _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, _prior_music_db)
	get_tree().paused = _prior_paused
	Input.mouse_mode = _prior_mouse_mode
	# A closed box detaches its choice rows and queue_free()s them; let that land so they don't report as orphans.
	await wait_process_frames(1)


## A fresh, in-tree DialogueManager (its _ready builds the view / ducker / bed / face light). Untyped: no class_name.
func _live_manager():
	var m = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(m)
	_managers.append(m)
	return m


func _convo(texts: Array) -> DialogueResource:
	var convo := DialogueResource.new()
	for t in texts:
		var line := DialogueLine.new()
		line.text = String(t)
		convo.lines.append(line)
	return convo


## Seat `m` on line 0 of a conversation past its intro beat, the box open -- without start()'s timer + tree pause.
func _open_convo(m, texts: Array, speaker: Node = null) -> DialogueResource:
	var convo := _convo(texts)
	m._active = convo
	m._index = 0
	m._intro_playing = false
	m._speaker = speaker
	m._view.open()
	return convo


## Seat a _ScriptedDialogueVoice as SpeechTts's default dialogue voice and switch TTS on; after_each undoes both.
func _install_scripted_voice() -> _ScriptedDialogueVoice:
	var voice := _ScriptedDialogueVoice.new()
	add_child_autofree(voice)
	_had_pool_voice = SpeechTts._dialogue_pool.has(VoiceData.MALE_DEFAULT)
	_prior_pool_voice = SpeechTts._dialogue_pool.get(VoiceData.MALE_DEFAULT)
	SpeechTts._dialogue_pool[VoiceData.MALE_DEFAULT] = voice
	_scripted_voice = voice
	Settings.tts_enabled = true
	return voice


# ---------------------------------------------------------------------------
# DialogueLine -- branching extension. choices defaults empty (so EVERY pre-branching line and
# .tres stays linear by construction), has_choices() is the pure linear-vs-branch predicate the
# manager keys on, and END / CONTINUE are the reserved int targets a choice can carry.
# ---------------------------------------------------------------------------

func test_choice_sentinels_sit_outside_every_line_index() -> void:
	# A choice's int target shares the line-index space (0..lines.size()-1). The two sentinels must live below it,
	# or a conversation long enough to own that index would route "end the conversation" into a real line instead.
	# The exact numbers are a separate cross-file contract (DialogueChoice spells its defaults as the literals -2 / -1
	# to dodge a class_name cycle), pinned by the two DialogueChoice default tests below.
	assert_lt(DialogueLine.END, 0,
		"DialogueLine.END must be negative -- a non-negative END is a real line index, so a Goodbye-style choice would jump into that line instead of closing the box")
	assert_lt(DialogueLine.CONTINUE, 0,
		"DialogueLine.CONTINUE must be negative -- a non-negative CONTINUE would send every unconfigured choice to that fixed line")
	assert_ne(DialogueLine.CONTINUE, DialogueLine.END,
		"CONTINUE and END must be different sentinels -- one keeps the conversation going, the other stops it")


func test_dialogue_line_has_choices_false_when_empty() -> void:
	var l := DialogueLine.new()
	assert_false(l.has_choices(),
		"has_choices() must be false on a fresh line so the manager shows the continue hint and runs the linear _advance path, exactly as before branching existed")


func test_dialogue_line_has_choices_true_after_append() -> void:
	var l := DialogueLine.new()
	l.choices.append(DialogueChoice.new())
	assert_true(l.has_choices(),
		"has_choices() must be true once a choice is added so _show_line spawns buttons and _unhandled_input early-returns (input can't skip the menu)")


# ---------------------------------------------------------------------------
# DialogueChoice -- pure Resource (no _init/_ready), safe to .new() without the tree.
# RefCounted: no .free() (auto-released at scope exit). One selectable branch option:
# a button label (text) + where picking it leads (target_id, else the legacy int target).
# ---------------------------------------------------------------------------

func test_dialogue_choice_target_default_is_continue() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.target, DialogueLine.CONTINUE,
		"DialogueChoice.target must default to DialogueLine.CONTINUE (-2) so a freshly-made, unconfigured choice CARRIES THE CONVERSATION ON to the next line instead of dead-ending it")



# DialogueChoice -- the consequence block (rank 6b/7) and the WR-1/WR-3 gates are OPT-IN: a choice an author added and
# left untouched must behave exactly as a choice did before those fields existed. Driven below through the real
# response menu; each consequence's own application is driven in tests/test_quest_stages.gd and by the choice-routing
# tests further down.

func test_a_choice_left_at_its_defaults_is_ungated_and_applies_nothing() -> void:
	# The real menu path: _reveal_menu paints the line's rows (DialogueView.set_choices folds the gates into `passed`)
	# and press_numbered_choice(1) is the digit-key press that fires row 1. An untouched choice must read as PASSED --
	# a failed gate routes to target_on_fail, END by default, and closes the conversation -- and carry the conversation
	# on without writing a story flag or turning the speaker hostile. Two controls on the same menu prove each
	# observable can move: authored consequence fields DO write the flag and provoke the speaker, and an authored gate
	# (an item nobody here carries -- there is no player in the tree) DOES fail and end the conversation.
	var m = _live_manager()
	var speaker := _ProvokeRecorder.new()
	add_child_autofree(speaker)
	var convo := _open_convo(m, ["What do you want?", "Go on, then.", "Show me the pass."], speaker)
	var control_flag := &"__test_dialogue_authored_choice_flag"
	convo.lines[0].choices.append(DialogueChoice.new())
	var authored := DialogueChoice.new()
	authored.set_flag = control_flag
	authored.aggro_speaker = true
	convo.lines[1].choices.append(authored)
	var gated := DialogueChoice.new()
	gated.required_item_id = &"__test_dialogue_item_nobody_carries"
	convo.lines[2].choices.append(gated)
	var flags_before: Dictionary = GameState.flags.duplicate(true)

	m._reveal_menu()
	assert_true(m._view.press_numbered_choice(1), "setup: the untouched choice is painted as row 1")
	assert_true(m.is_engaged(),
		"a choice left at its defaults must read as PASSED -- an unset gate that read as failed would route to target_on_fail and END the conversation")
	assert_eq(m._index, 1, "a choice left at its defaults carries the conversation on to the next line")
	assert_true(GameState.flags == flags_before,
		"a choice left at its defaults must write no story flag -- the consequence block is opt-in")
	assert_eq(speaker.provoked, 0, "a choice left at its defaults must not turn the speaker hostile")

	m._reveal_menu()
	assert_true(m._view.press_numbered_choice(1), "setup: the authored choice is painted as row 1")
	assert_eq(GameState.get_flag(control_flag), true, "control: an authored set_flag IS written when the choice is picked")
	assert_eq(speaker.provoked, 1, "control: an authored aggro_speaker DOES provoke the speaker")
	assert_eq(m._index, 2, "control: and the conversation carries on")

	m._reveal_menu()
	assert_true(m._view.press_numbered_choice(1), "setup: the gated choice is painted as row 1 (a non-stat gate stays selectable)")
	assert_false(m.is_engaged(),
		"control: an authored gate the player fails DOES read as failed -- target_on_fail's default END closes the conversation")

	GameState.flags.clear()
	GameState.flags.merge(flags_before)

func test_choice_item_and_faction_dropdowns_list_their_registries() -> void:
	# The inspector dropdowns are SUGGESTIONS fed live from the on-disk registries (no hand-kept list), so a new item
	# or faction shows up without editing this Resource and a typo'd id is far less likely to be authored.
	var c := DialogueChoice.new()
	var props := {}
	for prop in c.get_property_list():
		props[prop.get("name", "")] = prop
	var feeds := {
		"give_item_id": DialogueChoice.ItemIds.ids_csv(),
		"required_item_id": DialogueChoice.ItemIds.ids_csv(),
		"required_faction_id": DialogueChoice.Factions.ids_csv(),
		"reward_reputation_faction_id": DialogueChoice.Factions.ids_csv(),
	}
	for field: String in feeds:
		var p: Dictionary = props.get(field, {})
		assert_false(p.is_empty(), "DialogueChoice must expose %s" % field)
		assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
			"%s must be a SUGGESTION dropdown so a blank 'no gate / no reward' stays valid" % field)
		assert_eq(p.get("hint_string", ""), feeds[field],
			"%s must offer exactly the ids its registry scans off disk -- a stale or empty list leaves the designer typing ids blind" % field)
	assert_false(String(feeds["give_item_id"]).is_empty(), "the item registry must find the shipped items, or every item dropdown is empty")
	assert_false(String(feeds["required_faction_id"]).is_empty(), "the faction registry must find the shipped factions, or every faction dropdown is empty")
	c = null

func test_dialogue_choice_target_on_fail_default_is_end() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.target_on_fail, DialogueLine.END,
		"DialogueChoice.target_on_fail must default to DialogueLine.END (-1) -- a failed gated choice finishes the conversation unless an author points it at a fail line (rank 22)")


func test_required_stat_dropdown_offers_every_stat_a_check_can_read() -> void:
	# required_stat is @tool + _validate_property, so its inspector dropdown (a PROPERTY_HINT_ENUM_SUGGESTION, so a blank
	# "no check" stays valid) is fed from CharacterStats rather than a hand-typed copy. What the designer needs from it:
	# every name offered is a stat the dialogue skill check actually reads -- a stale or typo'd name silently reads
	# CharacterStats.BASELINE, so the check ignores the player's build -- and no attribute on the sheet is missing.
	var c := DialogueChoice.new()
	var p := {}
	for prop in c.get_property_list():
		if prop.get("name", "") == "required_stat":
			p = prop
			break
	assert_false(p.is_empty(), "DialogueChoice must expose a required_stat property")
	assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
		"required_stat must be a SUGGESTION dropdown (set in _validate_property) so a blank 'no check' stays valid")
	var offered := String(p.get("hint_string", "")).split(",", false)
	assert_false(offered.is_empty(),
		"the required_stat dropdown must offer the stats -- an empty list leaves the designer typing stat ids blind")
	var player := _StatBuffPlayerStub.new()
	for stat_name: String in offered:
		player.sheet.set(stat_name, 7)
		assert_almost_eq(DialogueView._effective_player_stat(player, StringName(stat_name)), 7.0, 0.001,
			"the dropdown offers '%s', so a skill check on it must read the player's value -- a name the check can't read silently scores BASELINE" % stat_name)
	# The sheet's attributes are its exported int fields; each one must be offered.
	var attributes := 0
	for prop in CharacterStats.new().get_property_list():
		var usage: int = prop.get("usage", 0)
		if prop.get("type", -1) != TYPE_INT or (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		attributes += 1
		assert_true(offered.has(String(prop.get("name", ""))),
			"CharacterStats.%s is an attribute on the sheet, so the required_stat dropdown must offer it" % prop.get("name", ""))
	assert_gt(attributes, 0, "setup: the CharacterStats sheet exposes its attributes as exported int fields")
	player.free()


# ---------------------------------------------------------------------------
# DialogueResource -- the id resolver, find_line and the shipped conversations are driven in
# tests/test_dialogue_ids.gd; the empty-resource start() guard is driven below.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# TalkHelpers.speaker_name -- the dialogue speaker-label name resolver (pure/static),
# used so a DialogueLine with a blank `speaker` falls back to the character's name.
# ---------------------------------------------------------------------------

func test_speaker_name_prefers_explicit_over_node() -> void:
	var n = load("res://scripts/npc/npc.gd").new()  # NPC exposes display_name; built off-tree (no _ready)
	n.display_name = "Raider"
	assert_eq(TalkHelpers.speaker_name("", n), "Raider",
		"control: with no explicit name, this node does supply the speaker name")
	assert_eq(TalkHelpers.speaker_name("Bob", n), "Bob",
		"An explicit speaker name (set on the Talkable / DialogueNPC) must win over the node's own display_name")
	n.free()

func test_speaker_name_empty_when_nothing_provides_one() -> void:
	assert_eq(TalkHelpers.speaker_name("", null), "",
		"No explicit name + no node must resolve to \"\" so the dialogue speaker label stays hidden")

func test_speaker_name_falls_back_to_node_display_name() -> void:
	var n = load("res://scripts/npc/npc.gd").new()  # NPC exposes display_name; built off-tree (no _ready)
	n.display_name = "Raider"
	assert_eq(TalkHelpers.speaker_name("", n), "Raider",
		"With no explicit name, speaker_name must read the node's display_name (a talkable NPC is named once, on the NPC)")
	n.free()



# ---------------------------------------------------------------------------
# DialogueManager -- NO class_name: see the header for how a throwaway is built and driven.
# ---------------------------------------------------------------------------

func test_dialogue_manager_starts_inactive() -> void:
	# No add_child: is_active() only reads `_active != null` (defaults null), so it is
	# safe even though _ready never ran.
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_false(m.is_active(),
		"DialogueManager must start idle (_active == null) so an NPC is free to begin a conversation")
	m.free()


func test_dialogue_cursor_hidden_while_reading_visible_for_choices() -> void:
	# The cursor follows the dialogue phase: hidden while a line is read (listen-first, nothing to click),
	# shown once the response menu is up so the player can click an option. dialogue_cursor_mode() is pure
	# (reads only _choices_shown), so it pins the contract without driving the live Input singleton.
	var m = load(DIALOGUE_MANAGER_PATH).new()
	m._choices_shown = false
	assert_eq(m.dialogue_cursor_mode(), Input.MOUSE_MODE_HIDDEN,
		"while a line is being read the cursor must be HIDDEN (nothing to click yet)")
	m._choices_shown = true
	assert_eq(m.dialogue_cursor_mode(), Input.MOUSE_MODE_VISIBLE,
		"once the response menu is up the cursor must be VISIBLE so the player can click an option")
	m.free()


func test_is_engaged_covers_suspended_conversations_that_is_active_hides() -> void:
	# Regression for "dialog > trade/heal/exchange > death corrupts the menus & UI": while a conversation is
	# SUSPENDED behind a sub-menu (Trade / Heal / Level Up / Install / Exchange Gear), is_active() reads FALSE
	# BY DESIGN (so the sub-menu -- which refuses to open over an ACTIVE dialogue -- is allowed to open). But
	# the conversation still EXISTS. Player.die() gates its abort on is_engaged(), NOT is_active(): the old
	# is_active() gate skipped the abort during a suspension, so die() -> _close_open_modals() then closed the
	# sub-menu, whose `closed` fired _resume_from_menu, re-pausing the tree + re-opening the box over the death
	# cinematic (which freezes the node-bound death tween). Pure predicates (read only _active/_suspended), so
	# no add_child / start() needed -- safe on a bare instance whose _ready never ran.
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_true(m.has_method("is_engaged"),
		"DialogueManager must expose is_engaged() -- die() uses it to tear down even a SUSPENDED conversation")
	assert_false(m.is_engaged(),
		"is_engaged() must be FALSE when idle (_active == null) -- nothing to tear down")
	m._active = DialogueResource.new()
	m._suspended = true  # a sub-menu (Trade/Heal/Install/...) is up
	assert_false(m.is_active(),
		"a SUSPENDED conversation must read is_active()==false so the sub-menu can open over it")
	assert_true(m.is_engaged(),
		"a suspended conversation is still ENGAGED -- die() aborts on THIS so a mid-menu death tears the conversation down instead of letting the sub-menu's close re-pause + re-open the box over the death cinematic")
	m.free()


func test_clear_choices_detaches_buttons_synchronously() -> void:
	# LAYOUT regression: "dialog > trade/menu > dialog put the box in the WRONG SPOT" (it jumped up off the
	# bottom of the screen). On RESUME from a sub-menu the response menu was still populated, so _reveal_menu
	# cleared-then-re-added the choices and scheduled _clamp_choices_height() in the SAME frame. clear_choices()
	# only queue_free()'d the outgoing buttons -- which is DEFERRED, so they lingered in _choices_box until
	# end-of-frame and got DOUBLE-counted by get_combined_minimum_size(); the choices scroll locked at ~2x height
	# and the bottom-anchored panel grew UPWARD (verified: panel top 270->196, scroll min 68->142). The fix:
	# clear_choices() remove_child()s each outgoing button BEFORE queue_free, so a same-frame re-measure is honest.
	# This test pins the synchronous detach (the measured 68->68 stability is the runtime QA proof of the effect).
	var view := DialogueView.new()
	add_child_autofree(view)
	view.open()  # lazily builds the box + choices UI
	view.add_extra_choice("A", func() -> void: pass)
	view.add_extra_choice("B", func() -> void: pass)
	assert_eq(view._choices_box.get_child_count(), 2, "two choice buttons were added")
	view.clear_choices()
	assert_eq(view._choices_box.get_child_count(), 0,
		"clear_choices() must DETACH the outgoing buttons synchronously (queue_free alone is deferred) so a same-frame _clamp_choices_height re-measure can't double-count them and shove the resumed dialogue box off the bottom of the screen")


func test_dialogue_view_hides_stat_choices_below_requirement() -> void:
	# No Player is present in this bare view test, so DialogueView._player_stat reads CharacterStats.BASELINE.
	# A choice requiring one point above baseline should disappear entirely; an ungated choice still renders.
	var view := DialogueView.new()
	add_child_autofree(view)
	view.open()
	var gated := DialogueChoice.new()
	gated.text = "Talk your way in"
	gated.required_stat = &"streetwise"
	gated.required_value = CharacterStats.BASELINE + 1
	var plain := DialogueChoice.new()
	plain.text = "Ask politely"
	view.set_choices([gated, plain], func(_choice: DialogueChoice, _passed: bool = true) -> void: pass)
	assert_eq(view._choices_box.get_child_count(), 1,
		"dialogue choices with unmet stat requirements should be hidden, not shown as failed/locked buttons")
	var button := view._choices_box.get_child(0) as Button
	assert_eq(button.text, "Ask politely",
		"the remaining visible choices keep their original order and labels after a stat-gated option is filtered out")

func test_dialogue_stat_checks_include_live_modifiers() -> void:
	var p := _StatBuffPlayerStub.new()
	p.sheet.streetwise = 0
	p.mods["streetwise"] = 3.0
	assert_almost_eq(DialogueView._effective_player_stat(p, &"streetwise"), 3.0, 0.001,
		"a carried +3 streetwise item like Chrome Grin should satisfy a Streetwise 3 dialogue check")
	assert_almost_eq(DialogueView._effective_player_stat(p, &"gunplay"), 0.0, 0.001,
		"unmodified stats still read the raw sheet value")
	p.free()


func test_start_hands_listeners_the_conversation_and_an_intro_abort_never_pauses_the_world() -> void:
	# start() is the only emitter of dialogue_started (ui.gd folds the crosshair off it), and after its intro beat it
	# pauses the world. Control first: left alone, the box opens and the tree pauses. Then the regression: the player
	# is shot DURING the intro beat, die() aborts -- the pending intro continuation must not pause the world anyway.
	var m = _live_manager()
	var started := []
	m.dialogue_started.connect(func(r: DialogueResource) -> void: started.append(r))
	var first := _convo(["Evening.", "Something you need?"])
	m.start(first)
	assert_eq(started.size(), 1, "start() must announce the conversation it opens")
	assert_same(started[0], first, "dialogue_started must hand listeners the exact DialogueResource being played")
	m.start(_convo(["A second conversation."]))
	assert_eq(started.size(), 1, "a start() while a conversation is already running must be ignored, not announced")
	await get_tree().create_timer(OUTLAST_TIMERS_SEC, true).timeout
	assert_true(get_tree().paused, "control: once the intro beat ends the box opens and the world pauses")
	m.abort()
	assert_false(get_tree().paused, "abort() must hand the world back")

	var second := _convo(["Hold on--"])
	m.start(second)
	assert_eq(started.size(), 2, "a fresh start() after the abort is announced again")
	assert_same(started[1], second, "with its own resource")
	m.abort()  # shot inside the intro beat
	assert_false(m.is_engaged(), "abort() during the intro beat must end the conversation")
	await get_tree().create_timer(OUTLAST_TIMERS_SEC, true).timeout
	assert_false(get_tree().paused,
		"the aborted intro's continuation must not open the box and pause the world -- that would freeze the death cinematic behind a dead conversation")
	assert_false(m.is_engaged(), "and it must not revive the conversation")


func test_suspending_for_a_sub_menu_announces_the_reason_before_opening_it() -> void:
	# _suspend_for_menu is the one pause-ownership seam for Trade / Heal / Level Up / Install / Exchange. Listeners
	# need the reason, and the announcement must come BEFORE the menu opens: a screen that refuses emits `closed`
	# synchronously inside its own open call, and must still read suspended -> resumed in that order.
	var m = _live_manager()
	var speaker := Node.new()
	add_child_autofree(speaker)
	_open_convo(m, ["Take a look at my wares."], speaker)
	var menu := _FakeMenu.new()
	add_child_autofree(menu)
	var events := []
	m.dialogue_suspended.connect(func(reason: String) -> void: events.append("suspended:" + reason))
	m.dialogue_resumed.connect(func() -> void: events.append("resumed"))
	m._suspend_for_menu("trade", func() -> void: events.append("menu opened"), menu.closed)
	assert_eq(events, ["suspended:trade", "menu opened"],
		"the suspension (with its reason) must be announced before the sub-menu opens")
	assert_false(m.is_active(), "while suspended the conversation reads inactive, so a menu that refuses over an ACTIVE dialogue may open")
	assert_true(m.is_engaged(), "but it still exists")
	menu.closed.emit()
	assert_eq(events, ["suspended:trade", "menu opened", "resumed"], "closing the menu resumes the conversation")
	assert_true(m.is_active(), "the player is dropped back into the live conversation")

	events.clear()
	m._suspend_for_menu("heal", func() -> void: menu.closed.emit(), menu.closed)  # a screen that refuses on open
	assert_eq(events, ["suspended:heal", "resumed"],
		"a menu that refuses synchronously must still read suspended -> resumed, in order")
	assert_true(m.is_active(), "and the refused menu leaves the conversation live, not stranded suspended")
	m.abort()


func test_a_speaker_killed_behind_a_sub_menu_still_ends_the_conversation() -> void:
	# Regression: the teardown gated on is_active(), which reads FALSE while a sub-menu suspends the conversation, so
	# killing the speaker while Trade was up left the conversation alive -- and the menu's later close re-opened the
	# box over a corpse. The gate is is_engaged(); _finish() also drops the menu's pending resume one-shot.
	var m = _live_manager()
	var events := []
	m.dialogue_finished.connect(func() -> void: events.append("finished"))
	m.dialogue_resumed.connect(func() -> void: events.append("resumed"))
	var speaker := _MortalSpeaker.new()
	add_child_autofree(speaker)
	var menu := _FakeMenu.new()
	add_child_autofree(menu)
	m.start(_convo(["Buy something, will ya?", "Come back soon."]), speaker)
	m._suspend_for_menu("trade", func() -> void: pass, menu.closed)
	assert_true(m.is_engaged() and not m.is_active(), "setup: the conversation is suspended behind the trade menu")
	assert_eq(speaker.process_mode, Node.PROCESS_MODE_DISABLED, "setup: the speaker is frozen for the conversation")

	speaker.died.emit()
	assert_false(m.is_engaged(), "a speaker killed while a sub-menu is up must still end the conversation")
	assert_eq(events, ["finished"], "the teardown announces dialogue_finished exactly once")
	assert_eq(speaker.process_mode, Node.PROCESS_MODE_INHERIT, "and hands the body its processing back")
	menu.closed.emit()  # the trade screen closes after the death
	assert_eq(events, ["finished"], "closing the sub-menu afterwards must not resume the torn-down conversation")
	assert_false(get_tree().paused, "nor re-pause the world behind a box nobody can answer")

	m._on_speaker_died()  # a stray death signal with no conversation up
	assert_eq(events, ["finished"], "control: with no conversation engaged a speaker death tears nothing down")
	await get_tree().create_timer(OUTLAST_TIMERS_SEC, true).timeout
	assert_false(get_tree().paused, "the intro beat that was pending when the speaker died must not pause the world either")


func test_player_death_tears_down_suspended_conversation_and_closes_install_screen() -> void:
	# Source contract (see the header): die() runs the death cinematic, so it cannot be driven on a GUT Player. Pins
	# the order inside die(): gate on is_engaged() (a SUSPENDED conversation reads is_active()==false, which skipped
	# the abort), abort, THEN sweep the modals -- closing a suspended conversation's sub-menu first fires its resume
	# one-shot and re-opens the box over the death cinematic. _close_open_modals must be the registry sweep, which
	# closes every modal (the "Install" suspend target, Chess, the name-entry box) rather than a hand-kept list.
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var die_code := _function_code(src, "die")
	var gate := die_code.find("DialogueManager.is_engaged()")
	var abort := die_code.find("DialogueManager.abort()")
	var sweep := die_code.find("_close_open_modals()")
	assert_gt(gate, -1, "Player.die() must gate its dialogue abort on DialogueManager.is_engaged()")
	assert_false(die_code.contains("DialogueManager.is_active()"),
		"Player.die() must not gate on is_active(): it reads false during a sub-menu suspension and skips the abort")
	assert_gt(abort, gate, "die() must call DialogueManager.abort() under that gate")
	assert_gt(sweep, abort,
		"die() must abort the conversation BEFORE sweeping the modals, or the sub-menu's close resumes the box over the death cinematic")
	assert_true(_function_code(src, "_close_open_modals").contains("InputManager.close_all_modals()"),
		"_close_open_modals() must route through InputManager.close_all_modals() so every registered modal (incl. the Install screen) closes on death")


func test_a_level_swap_mid_conversation_ends_it_while_the_speaker_is_still_in_the_world() -> void:
	# The DialogueView is a CHILD OF THE AUTOLOAD, so it outlives a level swap: unless GameRoot.load_level ends the
	# conversation, the new level boots with `_active` still set, `_speaker` a handle into the thrown-away level and the
	# tree PAUSED behind a box nobody can answer. Reached through the debug console's `warp` / `resurrect`, which run
	# PROCESS_MODE_ALWAYS straight through the dialogue pause. The conversation must end BEFORE the outgoing level is
	# detached, so the speaker's own release hook (set_in_dialogue(false)) still runs on a body that is in the world.
	# load_level aborts the LIVE DialogueManager, so the conversation is seated there (after_each restores its _active /
	# _suspended, the tree pause and the cursor); the GameState fields a level load writes are put back at the end.
	var prior_loaded: bool = GameState.loaded
	var prior_matches: bool = GameState.respawn_level_matches
	var prior_level_path: String = GameState.current_level_path
	var prior_apply_pending: String = GameState._level_apply_pending
	var prior_reload_pending: bool = GameState._reload_pending
	GameState.loaded = false  # a GameRoot's _ready boots the SAVED level while this is set; this test loads its own
	var root = load(GAME_ROOT_PATH).new()
	add_child_autofree(root)
	root.load_level(_stand_in_level("Bar"), &"", false)
	var speaker := _LevelSpeaker.new()
	root.get_node(^"Level").add_child(speaker)
	DialogueManager._active = _convo(["You're not from around here."])
	DialogueManager._index = 0
	DialogueManager._speaker = speaker
	DialogueManager._speaker_prior_mode = speaker.process_mode
	speaker.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = true  # the state a live conversation holds once its box is open
	assert_true(DialogueManager.is_engaged(), "setup: a conversation is up with its speaker standing in the level")
	assert_eq(speaker.released_in_world, [], "setup: the speaker has not been handed back yet")

	root.load_level(_stand_in_level("Street"), &"", false)  # the console's `warp`
	assert_false(DialogueManager.is_engaged(),
		"a level swap must end the conversation -- its speaker is in the level being thrown away, and the autoload-owned box would otherwise survive the swap")
	assert_eq(speaker.released_in_world, [true],
		"the conversation must end BEFORE the outgoing level is detached, so the speaker is handed back while it is still in the world")
	assert_false(get_tree().paused, "and the paused world is handed back, not left frozen under the new level")

	DialogueManager.abort()  # a no-op when the swap ended it; otherwise clears the seated speaker handle
	GameState.loaded = prior_loaded
	GameState.respawn_level_matches = prior_matches
	GameState.current_level_path = prior_level_path
	GameState._level_apply_pending = prior_apply_pending
	GameState._reload_pending = prior_reload_pending


## An in-memory LevelData whose scene is a bare Node3D named `root_name` -- a stand-in level for GameRoot.load_level
## (no resource_path, so GameRoot never parks it in its level cache and the swap frees it).
func _stand_in_level(root_name: String) -> LevelData:
	var content := Node3D.new()
	content.name = root_name
	var packed := PackedScene.new()
	assert_eq(packed.pack(content), OK, "setup: the stand-in level scene packs")
	content.free()
	var data := LevelData.new()
	data.scene = packed
	return data


func test_quest_toasts_raised_behind_a_suspended_conversation_wait_for_it_to_close() -> void:
	# UI hides its notices layer for the whole dialogue_started -> dialogue_finished span, but is_active() reads FALSE
	# while a sub-menu suspends the conversation. A quest toast raised from that sub-menu (buying a quest item in
	# Trade) must queue like any mid-conversation toast, not burn its fade timer on the hidden layer.
	var ui: UI = autofree(UI.new())
	var stack := VBoxContainer.new()
	add_child_autofree(stack)
	ui._rep_toasts = stack
	ui._push_quest_toast("New quest: Recover the package", Color.WHITE)
	assert_eq(stack.get_child_count(), 1, "control: with no conversation up a quest toast shows immediately")

	DialogueManager._active = _convo(["What'll it be?"])
	DialogueManager._suspended = true  # the Trade screen is up over the conversation
	ui._push_quest_toast("Objective complete: Buy the keycard", Color.WHITE)
	assert_eq(stack.get_child_count(), 1,
		"a quest toast raised behind a SUSPENDED conversation must wait -- the notices layer is still hidden until dialogue_finished")

	DialogueManager._active = null
	DialogueManager._suspended = false
	ui._on_dialogue_finished()
	assert_eq(stack.get_child_count(), 2, "the held toast is delivered when the conversation closes")
	assert_eq((stack.get_child(0) as Label).text, "Objective complete: Buy the keycard", "and it is the held toast, newest on top")


func test_a_picked_choice_routes_by_its_gate_result() -> void:
	# A passed gate applies the choice's consequences and jumps to its target; a FAILED gate (the choice stays
	# selectable, FNV-style) routes to target_on_fail -- END by default -- and applies NOTHING.
	var m = _live_manager()
	var speaker := _ProvokeRecorder.new()
	add_child_autofree(speaker)
	_open_convo(m, ["Hand it over.", "You'll regret that.", "Fine. Take it.", "Get lost."], speaker)
	var threaten := DialogueChoice.new()
	threaten.text = "[Intimidate] Hand it over or else."
	threaten.target = 2
	threaten.aggro_speaker = true
	m._on_choice_pressed(threaten, true)
	assert_eq(m._index, 2, "a passed choice must jump to the line its target names")
	assert_true(m.is_engaged(), "and keep the conversation going")
	assert_eq(speaker.provoked, 1, "a passed choice applies its consequences (aggro_speaker provokes the speaker)")
	m._on_choice_pressed(threaten, false)
	assert_false(m.is_engaged(), "a FAILED gate routes to target_on_fail, which defaults to END: the conversation closes")
	assert_eq(speaker.provoked, 1, "a failed gate must apply NO consequences -- flunking the check must not also turn the speaker hostile")


func test_an_unconfigured_or_dangling_choice_never_strands_the_conversation() -> void:
	var m = _live_manager()
	_open_convo(m, ["One.", "Two.", "Three."])
	m._on_choice_pressed(DialogueChoice.new())
	assert_eq(m._index, 1, "a choice nobody configured must carry the conversation on to the NEXT line, not dead-end it")
	assert_true(m.is_engaged(), "and leave it running")
	var dangling := DialogueChoice.new()
	dangling.target = 7  # lines were deleted after this choice was authored
	get_tree().paused = true  # the state a live conversation holds once its box is open (after_each restores it)
	m._on_choice_pressed(dangling)
	assert_false(m.is_engaged(), "a target past the last line must end the conversation cleanly instead of indexing off the end")
	assert_false(get_tree().paused,
		"and hand the paused world back -- a dangling target must not strand the player in a frozen world with no box")


## Pin the signal ARITY, not just existence: a future refactor that drops dialogue_started's resource arg (or
## dialogue_suspended's reason) would silently break every `.connect` that reads it. get_signal_list() reports the
## declared arg count, so this fails loudly if the contract drifts.
func test_dialogue_manager_signal_arity() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	assert_eq(_signal_arg_count(m, "dialogue_started"), 1,
		"dialogue_started must carry exactly one arg (the DialogueResource) so listeners know which conversation opened")
	assert_eq(_signal_arg_count(m, "dialogue_suspended"), 1,
		"dialogue_suspended must carry exactly one arg (the reason String) so listeners know which sub-menu opened")
	assert_eq(_signal_arg_count(m, "dialogue_finished"), 0,
		"dialogue_finished carries no args (a bare state notification)")
	assert_eq(_signal_arg_count(m, "dialogue_resumed"), 0,
		"dialogue_resumed carries no args (a bare state notification)")
	m.free()


func test_speech_tts_dialogue_completion_signal_exists() -> void:
	var t = load(SPEECH_TTS_PATH).new()
	assert_true(t.has_signal("dialogue_speech_finished"),
		"SpeechTts must emit when a focused dialogue line's generated audio finishes so auto-advance cannot cut long TTS lines off at the estimate cap")
	assert_eq(_signal_arg_count(t, "dialogue_speech_finished"), 1,
		"dialogue_speech_finished must carry the speech token so stale completions from skipped lines are ignored")
	t.free()


func test_auto_advance_waits_for_the_spoken_audio_not_the_text_estimate() -> void:
	# A long TTS line outlasts the clamped per-character estimate, so while real audio plays auto-advance must wait
	# for SpeechTts.dialogue_speech_finished. A completion from a line the player already skipped must be ignored,
	# or it would skip the NEXT line too.
	var voice := _install_scripted_voice()
	var d: DialogueSettings = GameSettings.dialogue
	d.auto_advance = true
	d.auto_advance_min_seconds = 0.05
	d.auto_advance_max_seconds = 0.05
	var m = _live_manager()
	_open_convo(m, ["A long line read aloud.", "Second.", "Third.", "Fourth."])
	m._show_line()
	assert_eq(voice.utterances.size(), 1, "setup: line one is being read aloud")
	await get_tree().create_timer(OUTLAST_TIMERS_SEC, true).timeout
	assert_eq(m._index, 0, "a spoken line must not be cut off when its text estimate runs out -- auto-advance waits for the audio")
	voice.utterances[0].finished.emit()
	assert_eq(m._index, 1, "the moment the line's audio finishes, the conversation moves on")
	assert_eq(voice.utterances.size(), 2, "and reads the next line aloud")

	m._on_advance_click()  # the player skips line two before its audio ends
	assert_eq(m._index, 2, "setup: a click skips to line three")
	voice.utterances[1].finished.emit()  # line two's audio ends late
	assert_eq(m._index, 2, "a skipped line's late completion must not advance past the line now playing")
	voice.utterances[2].finished.emit()
	assert_eq(m._index, 3, "only the current line's own completion advances")
	m.abort()


func test_text_only_lines_still_auto_advance_on_the_estimate() -> void:
	# The control for the test above: with no audio started (TTS off) the clamped text estimate drives auto-advance.
	var d: DialogueSettings = GameSettings.dialogue
	d.auto_advance = true
	d.auto_advance_min_seconds = 0.05
	d.auto_advance_max_seconds = 0.05
	var m = _live_manager()
	_open_convo(m, ["One.", "Two.", "Three.", "Four.", "Five.", "Six."])
	m._show_line()
	await get_tree().create_timer(OUTLAST_TIMERS_SEC, true).timeout
	assert_gt(m._index, 0, "with no speech playing, a line must auto-advance once its text estimate elapses")
	m.abort()


## Helper: the declared argument count of a signal on `obj` (from get_signal_list()), or -1 if absent.
func _signal_arg_count(obj: Object, sig_name: String) -> int:
	for s in obj.get_signal_list():
		if s.get("name", "") == sig_name:
			return (s.get("args", []) as Array).size()
	return -1


func test_dialogue_manager_ready_sets_process_mode_always() -> void:
	# add_child IS safe here: _ready sets process_mode and builds four PROCESS_MODE_ALWAYS children (DialogueView,
	# MusicDucker, DialogueMusicBed, DialogueFaceLight); none grabs the mouse or pauses the tree (the ducker only reads an
	# AudioServer bus index, the bed only reads its GameSettings.dialogue knobs), so adding it to the GUT tree is safe.
	# The only other lifecycle hook, _unhandled_input, early-returns while inactive (it stays inactive).
	var m = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(m)
	assert_eq(m.process_mode, Node.PROCESS_MODE_ALWAYS,
		"_ready must set PROCESS_MODE_ALWAYS so the text box keeps advancing while the manager pauses the game tree")


func test_dialogue_manager_start_null_is_guarded_noop() -> void:
	# A missing resource (an unassigned field, a selector with no matching row and no default) must not half-open a
	# conversation. `_active` stays null whether or not the guard holds, so is_active() cannot tell. What a null that
	# slipped past the guard WOULD do is the rest of start(): announce dialogue_started, freeze the speaker, and once the
	# intro beat ends pause the world -- with is_engaged() still false, so no teardown path would ever unpause it.
	# Control last: the same listener and speaker with a real conversation.
	var m = _live_manager()
	var started := []
	m.dialogue_started.connect(func(r: DialogueResource) -> void: started.append(r))
	var speaker := _MortalSpeaker.new()
	add_child_autofree(speaker)
	m.start(null, speaker)
	assert_eq(started.size(), 0,
		"start(null) must not announce a conversation -- dialogue_started listeners (the HUD, the holster) would react to one that never opens")
	assert_eq(speaker.process_mode, Node.PROCESS_MODE_INHERIT, "start(null) must not freeze the speaker it was handed")
	await get_tree().create_timer(OUTLAST_TIMERS_SEC, true).timeout
	assert_false(get_tree().paused,
		"start(null) must never pause the world -- there is no conversation that could ever unpause it")

	m.start(_convo(["Control."]), speaker)
	assert_eq(started.size(), 1, "control: a real conversation through the same call IS announced")
	assert_eq(speaker.process_mode, Node.PROCESS_MODE_DISABLED, "control: and freezes its speaker")
	m.abort()


func test_dialogue_manager_start_empty_resource_is_guarded_noop() -> void:
	# Same early-return path: lines.is_empty() is true, so start() returns before get_tree().
	var m = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(m)
	var empty := DialogueResource.new()
	m.start(empty)
	assert_false(m.is_active(),
		"start(empty) must be ignored (the dialogue.lines.is_empty() guard) so an empty conversation never opens")
	assert_false(get_tree().paused,
		"start(empty) must return before get_tree().paused = true so an empty resource never freezes the game")



# ---------------------------------------------------------------------------
# DialogueNPC -- inspected via load(path).new() WITHOUT add_child, so _ready (which puts range_area on the talk layer
# and collects the meshes) never runs. Node-derived but not in the tree, so .free() by hand.
# ---------------------------------------------------------------------------

func test_a_dialogue_npc_warns_the_designer_until_it_can_be_talked_to() -> void:
	# A DialogueNPC's whole job is to be interfaced with, so the inspector must flag one that silently does nothing on
	# interact: no conversation (neither `dialogue` nor `dialogue_selector`) and no look-at hitbox (`range_area`) each
	# warn, and wiring them clears the warning. A selector counts as a conversation -- it picks one by world state.
	var npc = load(DIALOGUE_NPC_PATH).new()
	assert_eq(npc._get_configuration_warnings().size(), 2,
		"a freshly dropped DialogueNPC has neither a conversation nor a look-at hitbox, and the inspector must flag both")
	var hitbox := Area3D.new()
	npc.range_area = hitbox
	assert_eq(npc._get_configuration_warnings().size(), 1,
		"wiring the look-at hitbox clears its warning; the missing conversation still warns")
	npc.dialogue = DialogueResource.new()
	assert_eq(npc._get_configuration_warnings().size(), 0, "with a conversation and a hitbox wired the node is complete")
	npc.dialogue = null
	npc.dialogue_selector = DialogueSelector.new()
	assert_eq(npc._get_configuration_warnings().size(), 0,
		"a dialogue_selector in place of a single dialogue is a conversation too -- it must not warn")
	hitbox.free()
	npc.free()


func test_dialogue_npc_is_node3d_and_typed() -> void:
	var npc = load(DIALOGUE_NPC_PATH).new()
	assert_true(npc is Node3D,
		"DialogueNPC must extend Node3D so it can be placed in the 3D world with a mesh + range Area3D")
	assert_true(npc is DialogueNPC,
		"DialogueNPC.new() must produce a DialogueNPC (class_name registered) so scenes can type it")
	npc.free()

func test_holster_deescalation_ignores_forced_carry_holster() -> void:
	var controller := DialogueController.new()
	var player := Player.new()
	var npc := _ForgiveRecorder.new()
	controller.host = player
	npc.add_to_group(Groups.NPC)
	add_child_autofree(controller)
	add_child_autofree(npc)

	controller.on_weapon_holstered(true)
	assert_eq(npc.forgive_count, 1,
		"a normal empty-handed holster still forgives a provoked NPC")
	player._carrying = true
	controller.on_weapon_holstered(true)
	assert_eq(npc.forgive_count, 1,
		"a forced carry holster must not forgive: the player is holding a throwable threat, not standing down")
	player.free()

## The DEATH holster's twin of the carry case above. Player.die() holsters the weapon for the cinematic; that must
## not pardon anyone. The pardon would sweep every provoked NPC no matter who killed you AND spend each one's
## one-shot betrayal latch — both of which the killer-aware death settlement (stand_down_on_player_death, applied on
## the respawn) is deliberately built to avoid, so a fall death would otherwise pacify the level for free.
func test_holster_deescalation_ignores_the_death_holster() -> void:
	var controller := DialogueController.new()
	var player := Player.new()
	var npc := _ForgiveRecorder.new()
	controller.host = player
	npc.add_to_group(Groups.NPC)
	add_child_autofree(controller)
	add_child_autofree(npc)

	player._dying = true
	controller.on_weapon_holstered(true)
	assert_eq(npc.forgive_count, 0,
		"the holster die() fires for the death cinematic must not forgive — a corpse lowering its gun is not a stand-down")
	# _dead is Character's latch, set by take_damage BEFORE die() runs, and it stays up for the whole cinematic:
	# cover it independently so neither half of the death state can leak a pardon.
	player._dying = false
	player._dead = true
	controller.on_weapon_holstered(true)
	assert_eq(npc.forgive_count, 0,
		"still no pardon while the Character death latch is up, even once the _dying cinematic flag is down")
	player._dead = false
	controller.on_weapon_holstered(true)
	assert_eq(npc.forgive_count, 1,
		"and a live, empty-handed player still gets the normal holster pardon — the death gate is not a blanket off-switch")
	player.free()

## The DIALOGUE holster's twin of the two cases above. on_dialogue_started force-holsters the weapon for the
## conversation camera; because that goes through the same set_holstered -> holster_changed path as a deliberate
## hold-R stand-down, it used to pardon every provoked NPC in the level the instant you talked to anyone — enemies
## visibly dropped aggro mid-fight for talking, which read as a jarring free pardon (and spent their betrayal latch).
## Wires a REAL Weapon + Attack so the pardon is reached through the live signal, exactly as in play.
func test_holster_deescalation_ignores_the_dialogue_holster() -> void:
	var controller := DialogueController.new()
	var player := Player.new()
	var ws := Weapon.new()
	var atk := Attack.new()
	ws.attack = atk
	player.weapon_system = ws
	atk.holster_changed.connect(controller.on_weapon_holstered)  # what Player._ready wires in play
	var npc := _ForgiveRecorder.new()
	controller.host = player
	npc.add_to_group(Groups.NPC)
	add_child_autofree(controller)
	add_child_autofree(npc)

	atk.holstered = false  # gun out, mid-fight
	controller.on_dialogue_started()
	assert_true(atk.holstered, "starting a conversation still stows the weapon for the camera")
	assert_eq(npc.forgive_count, 0,
		"the forced dialogue holster must not pardon a provoked NPC — talking to someone is not standing down")
	controller.on_dialogue_finished()
	assert_false(atk.holstered, "the pre-dialogue drawn state is restored on finish")
	assert_eq(npc.forgive_count, 0, "and un-holstering on finish forgives nothing either")
	atk.set_holstered(true)  # now a DELIBERATE hold-R stand-down
	assert_eq(npc.forgive_count, 1,
		"a deliberate holster after the conversation still pardons — the dialogue fence is a latch, not a sticky flag")
	atk.free()
	ws.free()
	player.free()


# ---------------------------------------------------------------------------
# DialogueSelector / DialogueSelectorRow (rank 8) -- pick a conversation by world state. Pure data + the
# ungated-row / default fallback; a gated matches() reads the GameState autoload, so the FAILED-quest gate test
# below resets that autoload before and after it.
# ---------------------------------------------------------------------------

func test_dialogue_selector_pick_returns_default_when_no_rows() -> void:
	var sel := DialogueSelector.new()
	var d := DialogueResource.new()
	sel.default_dialogue = d
	assert_eq(sel.pick(), d, "with no rows, pick() returns default_dialogue")

func test_dialogue_selector_first_ungated_row_wins_over_default() -> void:
	var sel := DialogueSelector.new()
	var d0 := DialogueResource.new()
	var d_def := DialogueResource.new()
	var row := DialogueSelectorRow.new()  # no gates -> always matches
	row.dialogue = d0
	sel.rows.append(row)
	sel.default_dialogue = d_def
	assert_eq(sel.pick(), d0, "an ungated row matches and its dialogue wins over the default")

func test_dialogue_selector_row_no_gate_matches() -> void:
	var row := DialogueSelectorRow.new()
	assert_true(row.matches(), "a row with no flag/quest gate always matches")
	assert_null(row.dialogue, "DialogueSelectorRow.dialogue defaults null")
	assert_eq(row.required_quest_state, DialogueSelectorRow.QuestState.ACTIVE, "required_quest_state defaults ACTIVE")


# --- WR-6: a FAILED quest opens its own dialogue gate (the DialogueChoice gate eval is playtest-verified;
# the DialogueSelectorRow.matches() path is pure enough to pin against the GameState autoload + reset) --------

func test_quest_gate_enums_have_failed() -> void:
	assert_true(DialogueChoice.QuestGate.has("FAILED"), "DialogueChoice.QuestGate gained a FAILED state (WR-6)")
	assert_true(DialogueSelectorRow.QuestState.has("FAILED"), "DialogueSelectorRow.QuestState gained a FAILED state (WR-6)")

func test_selector_row_failed_state_tracks_a_failed_quest() -> void:
	# matches() reads the GameState autoload — set up a failed quest, assert the FAILED row matches, then reset.
	GameState.reset_for_new_game()
	var q := Quest.new()
	q.id = &"wr6_sel"  # no objectives needed — fail_quest acts on the active record directly
	GameState.start_quest(q)
	GameState.fail_quest(&"wr6_sel")
	var row := DialogueSelectorRow.new()
	row.required_quest_id = &"wr6_sel"
	row.required_quest_state = DialogueSelectorRow.QuestState.FAILED
	assert_true(row.matches(), "a FAILED selector row matches once the quest has failed")
	row.required_quest_state = DialogueSelectorRow.QuestState.ACTIVE
	assert_false(row.matches(), "the same row gated ACTIVE no longer matches a failed quest")
	row.required_quest_state = DialogueSelectorRow.QuestState.NOT_STARTED
	assert_false(row.matches(), "a failed quest counts as started, so NOT_STARTED no longer matches")
	GameState.reset_for_new_game()  # cleanup the shared autoload
	q = null



# ---------------------------------------------------------------------------
# Talkable -- the reusable talk component (Area3D). Inspected via load(path).new(); the look-at highlight test adds it
# under a host so its _ready latches the highlight switch (it touches no autoload).
# ---------------------------------------------------------------------------

func test_a_talkable_warns_only_when_its_host_can_do_nothing() -> void:
	# With no conversation a Talkable does nothing under an INANIMATE host (a car / terminal needs something to say), so
	# the inspector flags it; under an NPC it still enables crouch-pickpocketing, so it must not. Which host that is
	# comes from highlight_target when one is set, else the node the component sits under -- the drop-in default.
	var car := Node3D.new()
	var on_car = load(TALKABLE_PATH).new()
	car.add_child(on_car)
	assert_eq(on_car._get_configuration_warnings().size(), 1,
		"a Talkable with no conversation under an inanimate host does nothing, and the inspector must say so")
	on_car.dialogue = DialogueResource.new()
	assert_eq(on_car._get_configuration_warnings().size(), 0, "assigning a conversation clears the warning")
	on_car.dialogue = null
	on_car.dialogue_selector = DialogueSelector.new()
	assert_eq(on_car._get_configuration_warnings().size(), 0, "a dialogue_selector counts as a conversation too")

	var npc = load("res://scripts/npc/npc.gd").new()  # built off-tree (no _ready)
	var on_npc = load(TALKABLE_PATH).new()
	npc.add_child(on_npc)
	assert_eq(on_npc._get_configuration_warnings().size(), 0,
		"a dialogue-less Talkable dropped under an NPC is valid (it still enables pickpocketing) -- the NPC it sits under is its host")
	on_npc.highlight_target = car
	assert_eq(on_npc._get_configuration_warnings().size(), 1,
		"control: pointed at an inanimate highlight_target, THAT node is the host, so the same dialogue-less Talkable warns")
	npc.free()
	car.free()


func test_a_dropped_in_talkable_lights_its_host_and_zero_width_opts_out() -> void:
	# The look-at outline IS the "you can talk to this" cue, so a Talkable dropped under a host with its shipped
	# highlight knobs must light that host. The two knobs now survive only as a visibility switch: zeroing EITHER opts
	# the host out (test_ink_outline.gd drives the alpha half; this drives the width half, with the default as control).
	var lit: Array = _talkable_on_host(false)
	(lit[0] as Talkable).set_look_highlight(true)
	assert_eq(_painted_id(lit[1]), float(InkOutline.TINT_ID_HOVER),
		"a Talkable left at its shipped highlight defaults must outline its host on look-at")
	(lit[0] as Talkable).set_look_highlight(false)
	var opted_out: Array = _talkable_on_host(true)
	(opted_out[0] as Talkable).set_look_highlight(true)
	assert_eq(_painted_id(opted_out[1]), float(InkOutline.TINT_ID_NEUTRAL),
		"highlight_width = 0 alone must opt the host out of the hover outline -- the shipping ATM-style 'no outline' authoring")


func test_talkable_is_area3d_and_typed() -> void:
	var t = load(TALKABLE_PATH).new()
	assert_true(t is Area3D,
		"Talkable must extend Area3D so it IS its own look-at hitbox -- dropped under any node, the interaction ray can hit it without a separate collider node")
	assert_true(t is Talkable,
		"Talkable.new() must produce a Talkable (class_name registered) so scenes can type it and reference the component")
	t.free()


## [Talkable, body mesh]: a Talkable added under a fresh in-tree host whose body mesh wears a neutral outline id, so
## _ready latches the highlight switch. `zero_width` sets highlight_width = 0 and leaves the colour at its default.
func _talkable_on_host(zero_width: bool) -> Array:
	var host := Node3D.new()
	add_child_autofree(host)
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	host.add_child(body)
	InkOutline.apply_tint_mesh(body, InkOutline.TINT_ID_NEUTRAL)
	var talk := Talkable.new()
	if zero_width:
		talk.highlight_width = 0.0
	host.add_child(talk)
	return [talk, body]


## The outline id currently painted on `m` (its InkOutline tint duplicate), or -1 when it has none.
func _painted_id(m: MeshInstance3D) -> float:
	var dup := m.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	if dup == null:
		return -1.0
	var v: Variant = dup.get_instance_shader_parameter(&"disposition_id")
	return float(v) if v != null else -1.0


## Code lines only (full-line comments dropped, trailing comments cut, indentation stripped) of the top-level function
## `fname` in `src`, or "" when there is none -- so a pinned call must sit in THAT function's code, not in a comment
## or in a neighbouring function.
func _function_code(src: String, fname: String) -> String:
	var out := PackedStringArray()
	var inside := false
	for line: String in src.split("\n"):
		if not line.is_empty() and not line.begins_with("\t") and not line.begins_with(" "):
			inside = line.begins_with("func %s(" % fname) or line.begins_with("static func %s(" % fname)
			continue
		if not inside:
			continue
		var code := line.get_slice("#", 0).strip_edges()
		if not code.is_empty():
			out.append(code)
	return "\n".join(out)


## Player stand-in for the dead-host bail test below: _begin_dialogue types `player: Node3D` and, once past
## its guards, calls focus_camera_on() BEFORE DialogueManager.start -- so a recorded call is the observable
## that the liveness bail leaked (the convo stays EMPTY, so a regressed bail reaches only the live autoload's
## start(empty) no-op).
class _FocusRecorder extends Node3D:
	var focus_calls: int = 0
	func focus_camera_on(_point) -> void:
		focus_calls += 1


func test_talkable_begin_dialogue_refuses_a_dead_host() -> void:
	# The talk-prompt buffer (TalkApproach.prompt_talk's in-range shortcut) arms a TREE-owned SceneTreeTimer
	# whose callback is _begin_dialogue -- so the delivery still lands when the host is KILLED during the beat
	# (the death freeze only disables the body's process_mode, never the timer). Pin the liveness bail: a DEAD
	# Character host must return BEFORE the camera focus + DialogueManager.start (which would fire
	# GameState.notify_talk, letting a TALK quest objective complete on the corpse). The convo is EMPTY on
	# purpose: if the bail regressed, start(empty) stays the documented safe no-op while the recorder catches
	# the leak -- the runner's tree/mouse state is never at risk.
	var t = load(TALKABLE_PATH).new()
	t.dialogue = DialogueResource.new()  # non-null so the convo guard passes and LIVENESS is what returns
	var host = load("res://scripts/npc/npc.gd").new()
	host.hp = 5.0
	host._dead = true  # the latch take_damage sets the moment the kill lands (before the freeze / free)
	var player := _FocusRecorder.new()
	t._begin_dialogue(host, player)
	assert_eq(player.focus_calls, 0,
		"a host that died inside the talk-prompt buffer must not open a conversation -- _begin_dialogue bails before the camera focus / DialogueManager.start, so no notify_talk ever fires on a corpse")
	player.free()
	host.free()
	t.free()
