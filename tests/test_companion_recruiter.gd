extends GutTest

## CompanionRecruiter (scripts/dialogue/companion_recruiter.gd) is the PURE recruit/dismiss resolution behind the
## dialogue companion button. DialogueManager binds following() as the BEHAVIOUR key (never the label text), paints
## label_for() as display only, and calls apply() to invoke the speaker's follow contract (stop_following, or
## start_following(player) with the player resolved from the PLAYER group). Every read is has_method-guarded
## duck typing, so a rename on the NPC silently drops the button with no compile error — this file pins the
## contract with test doubles: the "Wait here"-beats-"Follow me" priority, the empty label for a speaker without
## the contract, the null guard, the PlayerText-const labels, and that apply() dispatches to the matching method
## (and is a harmless no-op on a partial implementation). The FREED-speaker half of the guard is not reachable
## from a test — see the KNOWN GAP below — so it is pinned on the CALLER instead.

## A speaker exposing the whole follow contract, with switchable answers and call recording.
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
	func start_following(leader: Node3D) -> void:
		start_calls += 1
		start_leader = leader

## A speaker with NO follow contract (a terminal, a car, a hostile NPC) — reads as not-following, gets no button.
class _Inert extends Node:
	pass

## A PARTIAL implementation: only can_recruit(). The label still shows, and apply() must have nothing to call
## without erroring — the has_method guards are the whole reason a partial speaker is safe.
class _RecruitOnly extends Node:
	func can_recruit() -> bool:
		return true


# --- following() — the behaviour predicate -----------------------------------------------------------------

func test_following_is_false_for_null_and_inert_speakers() -> void:
	assert_false(CompanionRecruiter.following(null), "a null speaker (no conversation) is never following")
	var inert: _Inert = autofree(_Inert.new())
	assert_false(CompanionRecruiter.following(inert),
		"a speaker without is_following() reads as not-following (the terminal / car case), never as an error")


func test_following_mirrors_the_speakers_is_following() -> void:
	var c: _Companion = autofree(_Companion.new())
	c.following_now = false
	assert_false(CompanionRecruiter.following(c), "an idle companion reads as not-following")
	c.following_now = true
	assert_true(CompanionRecruiter.following(c), "a mid-follow companion reads as following — this is apply()'s was_following key")


## KNOWN GAP: a FREED speaker can never reach these statics' bodies. GDScript type-checks an Object argument
## against the `Node` PARAMETER before the function runs and raises "Invalid type in function 'following'/'apply'
## ... (previously freed) is not a subclass of the expected argument class" — the same family as the lambda-capture
## trap, where the engine validates at the boundary and an in-body guard cannot suppress it. So the
## `not is_instance_valid(speaker)` half of the guards in companion_recruiter.gd (lines 14, 28, 44) is live for
## NULL only; a genuinely freed speaker errors at the call site regardless of what the callee does. The protection
## that actually works is the CALLER validating first, which is what the three tests below pin: BOTH call sites
## (DialogueManager._on_companion_pressed before apply(), _reveal_menu before label_for()) do exactly that, and
## the null path still behaves.
func test_null_speaker_is_guarded_on_every_entry_point() -> void:
	assert_false(CompanionRecruiter.following(null), "following(null) is false, never an error")
	assert_eq(CompanionRecruiter.label_for(null), "", "label_for(null) offers no button")
	CompanionRecruiter.apply(null, true, get_tree())
	CompanionRecruiter.apply(null, false, get_tree())
	assert_true(true, "apply(null, ...) is a no-op in both directions (the death-abort path's null speaker)")


func test_the_caller_validates_the_speaker_before_handing_it_to_apply() -> void:
	# Because the freed case dies at the parameter boundary (see the KNOWN GAP above), the ONLY working guard is
	# the caller's. DialogueManager._on_companion_pressed must bail on an invalid speaker BEFORE calling apply()
	# — a stale companion button can fire after the speaker died mid-conversation.
	var src := FileAccess.get_file_as_string("res://scripts/dialogue/dialogue_manager.gd")
	var guard := src.find("if _speaker == null or not is_instance_valid(_speaker):")
	var call_site := src.find("CompanionRecruiter.apply(")
	assert_gt(guard, -1, "DialogueManager carries the speaker-validity guard")
	assert_gt(call_site, -1, "DialogueManager is the caller of CompanionRecruiter.apply()")
	assert_lt(guard, call_site,
		"the validity guard runs BEFORE apply() — a freed speaker must never be passed at all (the callee cannot save it)")


## The label_for() / following() call site carries the SAME exposure as apply()'s, and it is REACHABLE.
## DialogueManager clears `_speaker` only in _finish(), so anything that frees the speaker's node under a live
## conversation leaves _reveal_menu() holding a freed handle with `_active` still set — the debug console is
## PROCESS_MODE_ALWAYS and deliberately does NOT refuse over a conversation, so its `reload` / `load` /
## `sandbox off` frees the whole scene (speaker included) while the autoload-owned dialogue box stays up. The
## boundary error is not a cosmetic log either: it ABORTS the calling function, so an unguarded _reveal_menu()
## would stop part-built — no station options and no Goodbye button, i.e. a paused world behind a dead box.
## Pinned on the SOURCE for the reason in the KNOWN GAP above: the freed argument cannot be handed to the
## static from a test at all, so there is no way to exercise the bad path directly.
func test_reveal_menu_validates_the_speaker_before_reading_the_companion_label() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/dialogue/dialogue_manager.gd")
	var body_start := src.find("func _reveal_menu()")
	assert_gt(body_start, -1, "DialogueManager still has _reveal_menu(), the companion button's paint site")
	var label_call := src.find("CompanionRecruiter.label_for(", body_start)
	assert_gt(label_call, -1, "_reveal_menu() is the caller of CompanionRecruiter.label_for()")
	var guard := src.find("is_instance_valid(_speaker)", body_start)
	assert_gt(guard, -1, "_reveal_menu() carries a speaker-validity guard of its own")
	assert_lt(guard, label_call,
		"the guard runs BEFORE label_for() — a freed speaker must never reach the typed `Node` parameter, because the callee's own is_instance_valid can never fire")


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


func test_apply_recruit_without_a_player_still_calls_start_following() -> void:
	var expected: Node = get_tree().get_first_node_in_group(Groups.PLAYER)
	var c: _Companion = autofree(_Companion.new())
	CompanionRecruiter.apply(c, false, get_tree())
	assert_eq(c.start_calls, 1, "start_following() is still invoked; the NPC decides what a missing leader means")
	assert_eq(c.start_leader, expected, "the leader is whatever the PLAYER group resolves to (null when no player is in the tree)")


func test_apply_is_a_no_op_on_null_inert_and_partial_speakers() -> void:
	CompanionRecruiter.apply(null, true, get_tree())
	CompanionRecruiter.apply(null, false, get_tree())
	var inert: _Inert = autofree(_Inert.new())
	CompanionRecruiter.apply(inert, true, get_tree())
	CompanionRecruiter.apply(inert, false, get_tree())
	var partial: _RecruitOnly = autofree(_RecruitOnly.new())
	CompanionRecruiter.apply(partial, true, get_tree())
	CompanionRecruiter.apply(partial, false, get_tree())
	assert_true(true, "apply() on a null / contract-less / partial speaker must not call anything or raise (has_method guards)")

