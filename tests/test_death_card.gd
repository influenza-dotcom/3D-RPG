extends GutTest

## Death-meaning knob + the editable death card (ML-2). The death_mode enum is branched in
## Player._on_death_sequence_done (CHECKPOINT_RESPAWN = today's Dark-Souls revive / RELOAD_LAST_SAVE /
## RELOAD_CHECKPOINT_FRESH); the card's text is a designer-editable death_message (default "You were killed.")
## on the player_feedback tuning resource, NOT a hardcoded string. The branch + the in-scene card draw are
## in-tree behaviour (reload / shader overlay) and playtested; here we pin the data contract: the default mode
## is the non-destructive one, the message default matches the requested copy, and the enum has all three modes.


func test_death_mode_enum_has_three_modes() -> void:
	assert_eq(PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN, 0, "CHECKPOINT_RESPAWN is the first (default) mode")
	assert_eq(PlayerFeedbackSettings.DeathMode.RELOAD_LAST_SAVE, 1, "RELOAD_LAST_SAVE is the second mode")
	assert_eq(PlayerFeedbackSettings.DeathMode.RELOAD_CHECKPOINT_FRESH, 2, "RELOAD_CHECKPOINT_FRESH is the third mode")
	assert_eq(PlayerFeedbackSettings.DeathMode.size(), 3, "exactly three death modes")


func test_defaults_preserve_todays_behaviour_and_copy() -> void:
	var s := PlayerFeedbackSettings.new()
	assert_eq(s.death_mode, PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN,
		"the default death mode is the non-destructive in-place revive (today's behaviour)")
	assert_eq(s.death_message, "[PH] You were killed.", "the death card default copy matches the requested line")
	assert_gt(s.death_message_size, 0, "the card font size is positive")
	s = null


func test_live_tuning_resource_exposes_the_card_fields() -> void:
	# The live .tres (GameSettings.player_feedback) carries the new fields with their defaults — what the Player
	# reads in _show_death_card / _on_death_sequence_done.
	var fb = GameSettings.player_feedback
	assert_true(fb is PlayerFeedbackSettings, "player_feedback is a PlayerFeedbackSettings")
	assert_eq(fb.death_message, "[PH] You were killed.", "the editable death message defaults through the live resource")
	assert_eq(fb.death_mode, PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN, "the live default mode is CHECKPOINT_RESPAWN")


func test_player_exposes_death_card_hooks() -> void:
	# The card show/hide + the mode branch exist on the Player (off-tree method-surface check; the draw is in-tree).
	var p = load("res://scripts/player/player.gd").new()
	assert_true(p.has_method(&"_show_death_card"), "the Player can raise the death card")
	assert_true(p.has_method(&"_hide_death_card"), "the Player can clear the death card on revive")
	assert_true(p.has_method(&"_on_death_sequence_done"), "the death-mode branch lives here")
	p.free()
