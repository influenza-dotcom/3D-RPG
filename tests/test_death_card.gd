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
	assert_eq(s.death_stranger_killer, "a stranger",
		"an un-introduced killer reads as the indefinite 'a stranger' — the proper-noun 'Stranger' placeholder is wrong mid-sentence")
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


## Duck-typed stand-in for an NPC killer: a display_name plus the resolved_disposition method that
## _killer_display_name uses as its "is a real person" gate (so the Stranger mask applies), plus the
## `faction` slot the NPC resolves its faction_id dropdown into (null == UNALIGNED, as on a real NPC).
class StubNpcKiller:
	extends Node
	var display_name := ""
	var faction: Faction = null
	func resolved_disposition() -> int:
		return 0


func _faction_with_noun(id: StringName, noun: String) -> Faction:
	var f := Faction.new()
	f.id = id
	f.display_name = String(id).capitalize()
	f.member_noun = noun
	return f


func test_killer_display_name_swaps_stranger_mask_for_indefinite_form() -> void:
	# The death card is a SENTENCE, so an un-introduced killer must read "killed by a stranger", never
	# "killed by Stranger" (the proper-noun placeholder is for label contexts: hover, corpse, loot title).
	# Off-tree: _killer_display_name only reads the live GameState name ledger, no scene needed.
	var prev_mask: bool = GameState.stranger_names_enabled
	GameState.stranger_names_enabled = true
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()
	k.display_name = "Zz Unmet Card Tester"  # unique — never revealed by any other test
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a stranger",
		"an un-introduced NPC killer masks to the indefinite 'a stranger' on the death card")
	GameState.reveal_name(k.display_name)
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "Zz Unmet Card Tester",
		"once introduced, the real name shows on the death card")
	var hazard := Node.new()  # no display_name / no resolved_disposition -> blank-name fallback path
	assert_eq(p._killer_display_name(hazard, "someone", "a stranger"), "someone",
		"a nameless killer still falls back to death_unknown_killer, not the stranger form")
	GameState.stranger_names_enabled = prev_mask
	hazard.free()
	k.free()
	p.free()


func test_faction_member_noun_names_an_unknown_killer_better_than_a_stranger() -> void:
	# THE REQUESTED BEHAVIOUR: an UNALIGNED killer stays "a stranger"; a killer who belongs to a faction
	# reads by that faction's in-sentence member_noun instead ("You were killed by a raider."). Same NPC,
	# same un-introduced state — the faction is the ONLY difference between the two lines.
	var prev_mask: bool = GameState.stranger_names_enabled
	GameState.stranger_names_enabled = true
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()
	k.display_name = "Zz Unmet Faction Card Tester"  # unique — never revealed by any other test
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a stranger",
		"UNALIGNED (faction == null) keeps the generic form — this is the case the design deliberately preserves")
	k.faction = _faction_with_noun(&"raiders", "a raider")
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a raider",
		"a faction member the player never met is named by their faction, not by the faceless generic")
	# A NAME YOU KNOW OUTRANKS THE FACTION: being introduced tells you strictly more than the uniform does,
	# so the faction noun must NOT hijack an unmasked name.
	GameState.reveal_name(k.display_name)
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "Zz Unmet Faction Card Tester",
		"once introduced, the real name still wins over the faction noun")
	GameState.stranger_names_enabled = prev_mask
	k.free()
	p.free()


func test_faction_without_an_authored_noun_falls_back_instead_of_reading_blank() -> void:
	# member_noun is OPTIONAL. A half-authored faction (or one deliberately left anonymous) must fall through
	# to the old wording — never emit "You were killed by ." — and whitespace must not count as authored.
	var prev_mask: bool = GameState.stranger_names_enabled
	GameState.stranger_names_enabled = true
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()
	k.display_name = "Zz Unmet Nounless Card Tester"  # unique — never revealed by any other test
	k.faction = _faction_with_noun(&"zz_nounless", "")
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a stranger",
		"a faction with no authored member_noun leaves the stranger fallback standing")
	k.faction.member_noun = "   "
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a stranger",
		"whitespace is not an authored noun — it would render as 'You were killed by  .'")
	GameState.stranger_names_enabled = prev_mask
	k.free()
	p.free()


func test_nameless_faction_killer_reads_by_faction_not_someone() -> void:
	# The OTHER anonymous rung: an NPC with no authored display_name at all used to read "someone". If it
	# has a faction, that is a strictly better name for it. A faction-less nameless killer still reads "someone".
	var p = load("res://scripts/player/player.gd").new()
	var k := StubNpcKiller.new()   # display_name deliberately left blank
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "someone",
		"a nameless, faction-less killer keeps the unknown-killer fallback")
	k.faction = _faction_with_noun(&"raiders", "a raider")
	assert_eq(p._killer_display_name(k, "someone", "a stranger"), "a raider",
		"a nameless killer with a faction is named by it")
	k.free()
	p.free()


func test_faction_noun_lookup_survives_a_killer_with_no_faction_property() -> void:
	# The death path is loosely typed (an NPC, a test double, a TITLED HAZARD) and must not crash on a killer
	# that has no `faction` member at all — the duck-typed .get() returns null and we fall through.
	var p = load("res://scripts/player/player.gd").new()
	var hazard := Node.new()
	assert_eq(p._killer_faction_noun(hazard), "",
		"a killer with no faction property resolves to no noun rather than erroring")
	assert_eq(p._killer_display_name(hazard, "someone", "a stranger"), "someone",
		"...and the card still composes its normal fallback line")
	hazard.free()
	p.free()


func test_shipped_factions_author_an_in_sentence_member_noun() -> void:
	# The three factions on disk are what the player actually meets, so their nouns are part of the copy, not
	# just a schema slot. Lowercase + article included, because they sit MID-SENTENCE ("You were killed by
	# a raider.") — a capitalized "Raiders" here would reproduce the exact "killed by Stranger" bug the
	# stranger fallback exists to fix.
	var Factions = load("res://scripts/faction/factions.gd")
	for id in ["raiders", "townsfolk", "neutral_wildlife"]:
		var f = Factions.by_id(id)
		assert_true(f is Faction, "%s resolves to a Faction" % id)
		var noun: String = f.member_noun
		assert_ne(noun, "", "%s authors an in-sentence member noun" % id)
		assert_eq(noun, noun.to_lower(), "%s's member noun is lowercase — it sits inside a sentence" % id)
		assert_true(noun.begins_with("a ") or noun.begins_with("an "),
			"%s's member noun carries its own indefinite article ('a raider'), so the line stays grammatical" % id)
	assert_eq(Factions.by_id("raiders").member_noun, "a raider",
		"the requested line: 'You were killed by a raider.'")


func test_faction_member_noun_defaults_blank_so_it_is_opt_in() -> void:
	# A faction that never authors one behaves exactly as before this feature — an unnamed faction is not a
	# wrong faction. Pins the default alongside the rest of the Faction schema.
	var f := Faction.new()
	assert_eq(f.member_noun, "", "member_noun is opt-in; blank keeps the old anonymous wording")


func test_reload_last_save_routes_through_the_autosave_freeze_seam() -> void:
	# THE RACE THIS PINS (2026-08-26 review find): autosave_world_state() coalesces to a one-frame-DEFERRED
	# flush. When the death frame also queued one (a door, a pickup, a kill bounty), a bare
	# GameState.load_from_disk() + reload_current_scene() in the RELOAD_LAST_SAVE branch let that flush run
	# AFTER the load, capture the still-in-tree OLD player, and autosave the abandoned timeline over the
	# checkpoint it had just loaded — silently destroying the save it was reverting to. The branch must route
	# through GameState.load_autosave() (-> _load_and_reload), which arms the _reload_pending freeze that
	# autosave() checks (latch behaviour: test_world_snapshot.gd; seam behaviour: test_debug_sandbox.gd).
	# The branch itself needs a tree + the autoloads, so the routing is a SOURCE-TEXT pin: if it fails after
	# a refactor, re-route through the latch seam and re-pin the new spelling — never satisfy it by restoring
	# a bare load.
	assert_true(GameState.has_method(&"load_autosave"), "the death-reload seam exists on GameState")
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true(src.contains("GameState.load_autosave()"),
		"the RELOAD_LAST_SAVE death branch loads the checkpoint through load_autosave() (arms _reload_pending)")
	assert_false(src.contains("GameState.load_from_disk"),
		"no direct GameState.load_from_disk in player.gd — outside _load_and_reload the loaded profile has no autosave-freeze protection")
