extends GutTest

## CompanionRecruiter (scripts/dialogue/companion_recruiter.gd) is the PURE recruit/dismiss resolution behind the
## dialogue companion button. DialogueManager binds following() as the BEHAVIOUR key (never the label text), paints
## label_for() as display only, and calls apply() to invoke the speaker's follow contract (stop_following, or
## start_following(player) with the player resolved from the PLAYER group). Every read is has_method-guarded
## duck typing, so a rename on the NPC silently drops the button with no compile error — this file drives the
## statics with recording doubles: the "Wait here"-beats-"Follow me" priority, the empty label for a speaker
## without the contract, the null guard, and that apply() dispatches only to the half of the contract a speaker
## actually implements.
##
## THE FREED SPEAKER. The statics' `speaker` parameter is typed `Node`, so a freed node is rejected at the call
## boundary before their own is_instance_valid can run — only the CALLER can refuse it. So that half is driven
## on a throwaway DialogueManager (the tests/test_dialogue.gd idiom: load(path).new(), a conversation seated
## directly, no start()): a speaker freed under a live conversation must leave the response menu with its
## Goodbye exit and turn a stale companion-button press into a silent no-op. Each refusal has a live-speaker
## control beside it. GUT 9.6 fails a test on any engine error, and the refusals also assert a zero engine-error
## count explicitly, because a boundary rejection and a clean early return leave the same fields behind.

const DIALOGUE_MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"

## A speaker exposing the whole follow contract, with call recording. start/stop flip is_following() the way
## a real NPC's follow state does, so a recruit -> dismiss cycle can be driven end to end.
class _Companion extends Node:
	var following_now: bool = false
	var recruitable: bool = false
	var stop_calls: int = 0
	var start_calls: int = 0
	var start_leader: Node = null
	func is_following() -> bool:
		return following_now
	func can_recruit() -> bool:
		return recruitable
	func stop_following() -> void:
		stop_calls += 1
		following_now = false
	func start_following(leader: Node3D) -> void:
		start_calls += 1
		start_leader = leader
		following_now = true

## A speaker with NO follow contract (a terminal, a car, a hostile NPC) — reads as not-following, gets no button.
class _Inert extends Node:
	pass

## A PARTIAL implementation: only can_recruit(). The label still shows, and apply() must have nothing to call.
class _RecruitOnly extends Node:
	func can_recruit() -> bool:
		return true

## Half a contract: can be dismissed, has no way to start following.
class _StopOnly extends Node:
	var stop_calls: int = 0
	func is_following() -> bool:
		return true
	func stop_following() -> void:
		stop_calls += 1

## The other half: can be recruited, has no way to stop.
class _StartOnly extends Node:
	var start_calls: int = 0
	func can_recruit() -> bool:
		return true
	func start_following(_leader: Node3D) -> void:
		start_calls += 1


var _prior_tts_enabled: bool
var _prior_auto_advance: bool
var _prior_mouse_mode: Input.MouseMode


func before_each() -> void:
	_prior_tts_enabled = Settings.tts_enabled
	_prior_auto_advance = GameSettings.dialogue.auto_advance
	_prior_mouse_mode = Input.mouse_mode
	# The recruit acknowledgement is a spoken line: no native TTS engine headless, and no auto-advance timer
	# left pointing at a throwaway manager.
	Settings.tts_enabled = false
	GameSettings.dialogue.auto_advance = false


func after_each() -> void:
	Settings.tts_enabled = _prior_tts_enabled
	GameSettings.dialogue.auto_advance = _prior_auto_advance
	Input.mouse_mode = _prior_mouse_mode
	# Response rows are detached then queue_free'd by clear_choices(); let them go before the orphan count.
	await wait_process_frames(1)


## A fresh in-tree DialogueManager seated on a one-line conversation with `speaker`, box open, intro over.
## Untyped: the manager is an autoload script with no class_name.
func _manager_on_a_line(speaker: Node):
	var m = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(m)
	var line := DialogueLine.new()
	line.text = "Need something?"
	var convo := DialogueResource.new()
	convo.lines.append(line)
	m._active = convo
	m._index = 0
	m._intro_playing = false
	m._speaker = speaker
	m._view.open()
	return m


## The labels of the unnumbered service rows the manager painted (companion / stations / exchange).
func _service_rows(m) -> PackedStringArray:
	var out := PackedStringArray()
	for child in m._view._choices_box.get_children():
		if child is Button:
			out.append((child as Button).text)
	return out


func _service_row(m, text: String) -> Button:
	for child in m._view._choices_box.get_children():
		if child is Button and (child as Button).text == text:
			return child as Button
	return null


func _exit_row_up(m) -> bool:
	var exit_button = m._view._exit_button
	return exit_button != null and is_instance_valid(exit_button)


# --- following() — the behaviour predicate -----------------------------------------------------------------

func test_following_is_false_for_null_and_inert_speakers() -> void:
	assert_false(CompanionRecruiter.following(null), "a null speaker (no conversation) is never following")
	var inert: _Inert = autofree(_Inert.new())
	assert_false(CompanionRecruiter.following(inert),
		"a speaker without is_following() reads as not-following (the terminal / car case), never as an error")


func test_following_keys_a_recruit_then_dismiss_round_trip() -> void:
	# DialogueManager feeds following() straight into apply() as was_following. If the predicate stopped
	# reading the speaker's live answer, an idle companion would be DISMISSED instead of recruited.
	var c: _Companion = autofree(_Companion.new())
	c.recruitable = true
	assert_false(CompanionRecruiter.following(c), "an idle companion reads as not-following")
	assert_eq(CompanionRecruiter.label_for(c), PlayerText.DIALOGUE_OPTION_FOLLOW, "an idle recruitable companion offers Follow me")
	CompanionRecruiter.apply(c, CompanionRecruiter.following(c), get_tree())
	assert_eq(c.start_calls, 1, "pressing Follow me on an idle companion recruits it")
	assert_eq(c.stop_calls, 0, "and never dismisses it")
	assert_true(CompanionRecruiter.following(c), "once recruited, the companion reads as following")
	assert_eq(CompanionRecruiter.label_for(c), PlayerText.DIALOGUE_OPTION_WAIT_HERE, "and the button flips to Wait here")
	CompanionRecruiter.apply(c, CompanionRecruiter.following(c), get_tree())
	assert_eq(c.stop_calls, 1, "pressing Wait here on a following companion dismisses it")
	assert_eq(c.start_calls, 1, "and does not recruit it a second time")
	assert_false(CompanionRecruiter.following(c), "a dismissed companion reads as not-following again")
	assert_eq(CompanionRecruiter.label_for(c), PlayerText.DIALOGUE_OPTION_FOLLOW, "and the button flips back to Follow me")


# --- the freed speaker: the caller's guard, driven on a real DialogueManager -------------------------------

func test_reveal_menu_offers_the_companion_row_and_pressing_it_dismisses() -> void:
	# CONTROL for the freed-speaker refusal below: the same seating with a live speaker gets the button, and the
	# row is bound to the behaviour predicate, so pressing it dismisses and the menu re-paints flipped.
	var c: _Companion = autofree(_Companion.new())
	c.following_now = true
	c.recruitable = true
	var m = _manager_on_a_line(c)
	m._reveal_menu()
	assert_true(_exit_row_up(m), "the response menu pins its Goodbye exit")
	var wait_row := _service_row(m, PlayerText.DIALOGUE_OPTION_WAIT_HERE)
	assert_true(wait_row != null, "a following companion gets a Wait-here row in the response menu (rows: %s)" % [_service_rows(m)])
	if wait_row == null:
		return
	wait_row.pressed.emit()
	assert_eq(c.stop_calls, 1, "pressing Wait here dismisses the companion")
	assert_eq(c.start_calls, 0, "and never recruits it")
	assert_true(_service_rows(m).has(PlayerText.DIALOGUE_OPTION_FOLLOW),
		"the re-painted menu offers Follow me, so the player can take the dismissal back (rows: %s)" % [_service_rows(m)])
	assert_false(_service_rows(m).has(PlayerText.DIALOGUE_OPTION_WAIT_HERE), "and no stale Wait-here row survives the re-paint")
	assert_true(_exit_row_up(m), "the re-painted menu still has its Goodbye exit")


func test_reveal_menu_with_a_freed_speaker_still_pins_the_goodbye_exit() -> void:
	# A debug-console reload frees the scene (speaker included) under a live conversation; the box is
	# autoload-owned and survives. A menu that stopped part-built would leave a paused world with no way out.
	var doomed := _Companion.new()
	doomed.recruitable = true
	var m = _manager_on_a_line(doomed)
	doomed.free()
	m._reveal_menu()
	assert_true(_exit_row_up(m),
		"a freed speaker must not stop the response menu before its Goodbye exit is added — that is a soft-lock behind the box")
	assert_false(_service_rows(m).has(PlayerText.DIALOGUE_OPTION_FOLLOW), "a freed speaker gets no Follow-me row")
	assert_false(_service_rows(m).has(PlayerText.DIALOGUE_OPTION_WAIT_HERE), "a freed speaker gets no Wait-here row")
	assert_engine_error_count(0, "the freed speaker must never reach CompanionRecruiter's typed Node parameter")


func test_companion_press_on_a_live_speaker_recruits_and_acknowledges() -> void:
	# CONTROL for the stale-press refusal below: the same press with the speaker alive gets past the guard.
	var c: _Companion = autofree(_Companion.new())
	c.recruitable = true
	var m = _manager_on_a_line(c)
	m._reveal_menu()
	var follow_row := _service_row(m, PlayerText.DIALOGUE_OPTION_FOLLOW)
	assert_true(follow_row != null, "a recruitable idle speaker gets a Follow-me row (rows: %s)" % [_service_rows(m)])
	if follow_row == null:
		return
	follow_row.pressed.emit()
	assert_eq(c.start_calls, 1, "pressing Follow me recruits the speaker")
	assert_true(m._pending_end, "the recruit acknowledgement ends the conversation on the next advance")
	assert_false(_exit_row_up(m), "the response menu gives way to the spoken acknowledgement line")


func test_a_stale_companion_press_after_the_speaker_is_freed_does_nothing() -> void:
	var doomed := _Companion.new()
	doomed.recruitable = true
	var m = _manager_on_a_line(doomed)
	m._reveal_menu()
	var follow_row := _service_row(m, PlayerText.DIALOGUE_OPTION_FOLLOW)
	assert_true(follow_row != null, "setup: the live speaker painted a Follow-me row (rows: %s)" % [_service_rows(m)])
	if follow_row == null:
		doomed.free()
		return
	doomed.free()
	follow_row.pressed.emit()
	assert_false(m._pending_end, "a press on a dead speaker's button must not queue the recruit acknowledgement's end")
	assert_true(_exit_row_up(m), "the response menu stays up, Goodbye included, so the player can still leave")
	assert_engine_error_count(0, "the stale press must bail before the freed speaker reaches CompanionRecruiter.apply()")


# --- label_for() — display only, priority dismiss > recruit > nothing ---------------------------------------

func test_label_is_empty_for_null_inert_and_unrecruitable_speakers() -> void:
	assert_eq(CompanionRecruiter.label_for(null), "", "no speaker -> no button")
	var inert: _Inert = autofree(_Inert.new())
	assert_eq(CompanionRecruiter.label_for(inert), "", "a speaker without the follow contract shows no button")
	var c: _Companion = autofree(_Companion.new())
	c.recruitable = false
	c.following_now = false
	assert_eq(CompanionRecruiter.label_for(c), "",
		"a speaker that is neither following nor recruitable (hostile / already-leader) shows nothing")


func test_label_offers_follow_me_for_a_recruitable_idle_speaker() -> void:
	var c: _Companion = autofree(_Companion.new())
	c.recruitable = true
	c.following_now = false
	assert_eq(CompanionRecruiter.label_for(c), PlayerText.DIALOGUE_OPTION_FOLLOW,
		"a recruitable speaker not yet following offers the authored Follow-me const (never a literal: the tr() sweep lives on PlayerText)")


func test_label_wait_here_wins_while_following_even_if_recruitable() -> void:
	var c: _Companion = autofree(_Companion.new())
	c.recruitable = true
	c.following_now = true
	assert_eq(CompanionRecruiter.label_for(c), PlayerText.DIALOGUE_OPTION_WAIT_HERE,
		"dismiss wins over recruit: you cannot re-recruit something already at your side")
	c.recruitable = false
	assert_eq(CompanionRecruiter.label_for(c), PlayerText.DIALOGUE_OPTION_WAIT_HERE,
		"a following companion offers Wait-here regardless of can_recruit()")


func test_label_for_a_partial_recruit_only_speaker() -> void:
	var p: _RecruitOnly = autofree(_RecruitOnly.new())
	assert_false(CompanionRecruiter.following(p), "can_recruit() alone is not following (no is_following method)")
	assert_eq(CompanionRecruiter.label_for(p), PlayerText.DIALOGUE_OPTION_FOLLOW,
		"a partial speaker that can be recruited still gets the Follow-me button")


func test_the_two_labels_are_distinct_authored_strings() -> void:
	assert_ne(PlayerText.DIALOGUE_OPTION_FOLLOW, PlayerText.DIALOGUE_OPTION_WAIT_HERE,
		"the button must visibly flip between recruit and dismiss; identical labels would hide the state")
	assert_ne(PlayerText.DIALOGUE_OPTION_FOLLOW.strip_edges(), "",
		"Follow-me must be non-empty: an empty label reads as no-button to DialogueManager")
	assert_ne(PlayerText.DIALOGUE_OPTION_WAIT_HERE.strip_edges(), "",
		"Wait-here must be non-empty: an empty label reads as no-button to DialogueManager")


# --- apply() — invoke the contract -----------------------------------------------------------------------------

func test_apply_dismiss_calls_stop_following_only() -> void:
	var c: _Companion = autofree(_Companion.new())
	c.following_now = true
	CompanionRecruiter.apply(c, true, get_tree())
	assert_eq(c.stop_calls, 1, "was_following=true -> stop_following() exactly once")
	assert_eq(c.start_calls, 0, "a dismiss must never also start a follow")


func test_apply_recruit_calls_start_following_with_the_player_group_node() -> void:
	var player := Node3D.new()
	player.name = "FakePlayer"
	player.add_to_group(Groups.PLAYER)
	add_child_autofree(player)
	var c: _Companion = autofree(_Companion.new())
	CompanionRecruiter.apply(c, false, get_tree())
	assert_eq(c.start_calls, 1, "was_following=false -> start_following() exactly once")
	assert_eq(c.stop_calls, 0, "a recruit must never also stop a follow")
	assert_eq(c.start_leader, player, "the leader handed to start_following is the first node in the PLAYER group")


func test_apply_recruit_without_a_player_hands_a_null_leader() -> void:
	assert_null(get_tree().get_first_node_in_group(Groups.PLAYER),
		"setup: no node is in the PLAYER group (a leaked player from another test would make this case meaningless)")
	var c: _Companion = autofree(_Companion.new())
	CompanionRecruiter.apply(c, false, get_tree())
	assert_eq(c.start_calls, 1, "start_following() is still invoked with no player; the NPC decides what a missing leader means")
	assert_null(c.start_leader, "with no player in the tree the leader is null, never some other node")
	assert_engine_error_count(0, "a recruit with no player to follow must not raise")


func test_apply_on_null_inert_and_recruit_only_speakers_raises_nothing() -> void:
	# There is nothing on these speakers to call, so the observable is the error log: an unguarded call on a
	# missing method is a "Nonexistent function" script error, which a player never sees but a broken button is.
	CompanionRecruiter.apply(null, true, get_tree())
	CompanionRecruiter.apply(null, false, get_tree())
	var inert: _Inert = autofree(_Inert.new())
	CompanionRecruiter.apply(inert, true, get_tree())
	CompanionRecruiter.apply(inert, false, get_tree())
	var partial: _RecruitOnly = autofree(_RecruitOnly.new())
	CompanionRecruiter.apply(partial, true, get_tree())
	CompanionRecruiter.apply(partial, false, get_tree())
	assert_engine_error_count(0,
		"apply() on a null / contract-less / can_recruit-only speaker must skip every call it has no method for")


func test_apply_calls_only_the_half_of_the_contract_a_partial_speaker_implements() -> void:
	var stop_only: _StopOnly = autofree(_StopOnly.new())
	CompanionRecruiter.apply(stop_only, false, get_tree())
	assert_eq(stop_only.stop_calls, 0, "a recruit never falls back to stop_following() on a speaker that cannot start")
	CompanionRecruiter.apply(stop_only, true, get_tree())
	assert_eq(stop_only.stop_calls, 1, "the half it does implement still works: a dismiss reaches stop_following()")
	var start_only: _StartOnly = autofree(_StartOnly.new())
	CompanionRecruiter.apply(start_only, true, get_tree())
	assert_eq(start_only.start_calls, 0, "a dismiss never falls back to start_following() on a speaker that cannot stop")
	CompanionRecruiter.apply(start_only, false, get_tree())
	assert_eq(start_only.start_calls, 1, "the half it does implement still works: a recruit reaches start_following()")
	assert_engine_error_count(0, "the missing half of a partial contract is skipped, not called")
