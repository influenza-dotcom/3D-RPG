extends GutTest

## CA-9 TutorialPrompt — a one-time, persistent tutorial tooltip volume (TriggerVolume subclass). Pure logic
## tested off-tree: {action} key-label substitution and the persistent seen-gate (the in-tree fire() path —
## body_entered + UI.toast — is playtest-verified per the repo convention). The seen-gate touches the shared
## GameState autoload, so the test cleans its flag.

const SEEN := &"__test_tutorial_seen_flag"


func test_is_a_trigger_volume() -> void:
	var tp := TutorialPrompt.new()
	assert_true(tp is TriggerVolume, "TutorialPrompt must be a TriggerVolume so all the base trigger actions compose")
	tp.free()


func test_resolve_keys_passthrough_when_no_tokens() -> void:
	var tp := TutorialPrompt.new()
	assert_eq(tp._resolve_keys("Just plain text."), "Just plain text.", "text with no {action} tokens is returned unchanged")
	tp.free()


func test_resolve_keys_substitutes_a_token() -> void:
	var tp := TutorialPrompt.new()
	var out := tp._resolve_keys("Press {interact} to use")
	assert_false(out.contains("{interact}"), "the {interact} token is replaced, not left literal")
	assert_true(out.begins_with("Press ") and out.ends_with(" to use"), "the surrounding text is preserved around the substitution")
	tp.free()


func test_resolve_keys_unknown_action_renders_none() -> void:
	var tp := TutorialPrompt.new()
	assert_eq(tp._resolve_keys("{__no_such_action__}"), "(none)", "an unbound/unknown action renders as InputManager's (none) sentinel")
	tp.free()


func test_seen_gate_blank_flag_never_seen() -> void:
	var tp := TutorialPrompt.new()
	tp.seen_flag = &""
	assert_false(tp._already_seen(), "a blank seen_flag is never 'seen' — the prompt repeats every entry by design")
	tp.free()


func test_seen_gate_tracks_the_flag() -> void:
	var tp := TutorialPrompt.new()
	tp.seen_flag = SEEN
	GameState.set_flag(SEEN, false)  # clean baseline on the shared autoload
	assert_false(tp._already_seen(), "not yet shown -> not seen")
	GameState.set_flag(SEEN, true)
	assert_true(tp._already_seen(), "once the persistent flag is set, the prompt is suppressed")
	GameState.set_flag(SEEN, false)  # cleanup so we don't leak into other tests
	tp.free()
