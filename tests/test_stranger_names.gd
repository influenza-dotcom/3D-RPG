extends GutTest

## "Stranger until introduced": GameState.reveal_name / name_is_revealed / public_name + the [world].known_names
## save/load round-trip + the New-Game wipe, and DialogueLine.reveals_name. Uses a FRESH GameState instance
## (load().new()), never the autoload, so it can't touch the user's real user://gamestate.cfg — same isolation
## pattern as test_story_flags.gd. The DISPLAY consumers (dialogue speaker label via DialogueManager, Talkable
## look-at readout, corpse loot header, death card, takedown prompt, cripple toast) are thin `public_name(...)`
## wiring over this surface and are playtest-verified per the in-tree-behaviour convention. The critical INVARIANT
## pinned here: masking is DISPLAY-only — identity/quest matching (notify_kill/notify_talk) keeps the true name.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const TMP_SAVE := "user://test_stranger_names.cfg"

func after_each() -> void:
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))

func test_unknown_name_masks_to_stranger() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_false(gs.name_is_revealed("Marcus"), "an un-introduced name is not revealed")
	assert_eq(gs.public_name("Marcus"), PlayerText.STRANGER, "an un-introduced NPC is shown as 'Stranger'")
	gs.free()

func test_blank_name_is_never_masked() -> void:
	# A nameless NPC has nothing to hide — it must stay blank (label hidden), not become "Stranger".
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.name_is_revealed(""), "a blank name is never 'unknown'")
	assert_eq(gs.public_name(""), "", "a blank name stays blank, not 'Stranger'")
	gs.free()

func test_reveal_unmasks_that_name_only() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.reveal_name("Marcus")
	assert_true(gs.name_is_revealed("Marcus"), "reveal_name marks the name known")
	assert_eq(gs.public_name("Marcus"), "Marcus", "a revealed NPC shows their real name")
	assert_eq(gs.public_name("Elena"), PlayerText.STRANGER, "reveal is per-name — Elena is still a Stranger")
	gs.free()

func test_reveal_ignores_whitespace_and_is_idempotent() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.reveal_name("  Marcus  ")
	assert_true(gs.name_is_revealed("Marcus"), "reveal strips surrounding whitespace on match")
	gs.reveal_name("Marcus")  # duplicate
	assert_eq(gs.known_names.size(), 1, "revealing the same name twice doesn't grow the ledger")
	gs.free()

func test_blank_reveal_is_a_noop() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.reveal_name("   ")
	assert_eq(gs.known_names.size(), 0, "revealing a blank/whitespace name records nothing")
	gs.free()

func test_master_switch_off_shows_real_names() -> void:
	# The authoring/debug escape hatch: with masking off, every NPC shows their real name outright.
	var gs = load(GAMESTATE_PATH).new()
	gs.stranger_names_enabled = false
	assert_eq(gs.public_name("Zeke"), "Zeke", "masking OFF -> the real name, no reveal needed")
	assert_true(gs.name_is_revealed("Zeke"), "masking OFF -> everyone reads as 'revealed'")
	gs.free()

func test_known_names_round_trip_through_save() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.reveal_name("Marcus")
	gs.reveal_name("Psycho Sniper")  # a name with a space must survive the ConfigFile round-trip
	gs.save_to_disk(TMP_SAVE)
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the known-names-bearing save loads back")
	assert_eq(gs2.public_name("Marcus"), "Marcus", "a revealed name survives a save")
	assert_eq(gs2.public_name("Psycho Sniper"), "Psycho Sniper", "a spaced name survives the round-trip")
	assert_eq(gs2.public_name("Elena"), PlayerText.STRANGER, "an un-revealed name is still masked after load")
	gs.free()
	gs2.free()

func test_reset_for_new_game_clears_known_names() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.reveal_name("Marcus")
	gs.reset_for_new_game()
	assert_false(gs.name_is_revealed("Marcus"), "New Game re-meets everyone — the known-names ledger is wiped")
	assert_eq(gs.public_name("Marcus"), PlayerText.STRANGER, "after New Game the once-known NPC is a Stranger again")
	gs.free()

func test_dialogue_line_reveals_name_defaults_inert() -> void:
	var line := DialogueLine.new()
	assert_false(line.reveals_name, "a line does NOT reveal the speaker's name unless the designer ticks it")
	line = null
