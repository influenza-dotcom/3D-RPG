extends GutTest

## "Stranger until introduced": GameState.reveal_name / name_is_revealed / public_name + the [world].known_names
## save/load round-trip + the New-Game wipe, DialogueLine.reveals_name, and the reveal-on-talk seam (opening ANY
## conversation with a real character ends their Stranger status — see the two source pins at the foot of this
## file; the per-line reveals_name flag is now redundant for a character speaker). Uses a FRESH GameState instance
## (load().new()), never the autoload, so it can't touch the user's real user://gamestate.cfg — same isolation
## pattern as test_story_flags.gd. The DISPLAY consumers (dialogue speaker label via DialogueManager, Talkable
## look-at readout, corpse loot header, death card, takedown prompt, cripple toast) are thin `public_name(...)`
## wiring over this surface and are playtest-verified per the in-tree-behaviour convention. The critical INVARIANT
## pinned here: masking is DISPLAY-only — identity/quest matching (notify_kill/notify_talk) keys on the STABLE
## identity, never the shown name.
##
## Slice 3 (stable identity, save v4): the ledger's canonical key is now NPC.identity_key (NpcData.id, falling
## back to the authored display name), with reveal_name taking an optional `identity` arg. Every single-arg call
## below therefore ALSO pins the id-less/legacy path: for an NPC with no authored id the identity key IS the name
## string, so these literal-name round-trips must behave byte-identically to v3 forever. The identity-arg surface,
## the display-compat bridge, and the v3 -> v4 lazy migration are pinned in tests/test_character_identity.gd.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const DIALOGUE_MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"
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

func test_reveal_with_identity_unmasks_the_display_name() -> void:
	# Slice 3: an id-authored NPC reveals under its IDENTITY key, and the display-compat bridge keeps the
	# string-only public_name surfaces resolving — the introduced NPC must never read "Stranger" again.
	var gs = load(GAMESTATE_PATH).new()
	gs.reveal_name("Marcus", &"marcus_fence")
	assert_true(gs.name_is_revealed("Marcus", &"marcus_fence"), "an identity-keyed query resolves after the reveal")
	assert_eq(gs.public_name("Marcus"), "Marcus", "the string-only display seam resolves too (the bridge entry)")
	gs.free()

func test_identity_arg_matches_ledger_without_bridge_entry() -> void:
	# name_is_revealed accepts EITHER key form: a ledger holding only the identity key (e.g. written by a future
	# identity-aware surface) still answers an identity-carrying query, while a string-only query misses it.
	var gs = load(GAMESTATE_PATH).new()
	gs.known_names["marcus_fence"] = true  # identity key only — no display bridge entry
	assert_true(gs.name_is_revealed("Marcus", &"marcus_fence"), "the identity arg matches the ledger's id key")
	assert_false(gs.name_is_revealed("Marcus"), "a string-only query can't see an id-only entry (needs the bridge)")
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

## THE feature: talking to someone AT ALL ends their Stranger status. start() reveals a real character speaker as
## the conversation opens — before the box paints its first speaker label — so no authored line has to be ticked
## reveals_name for the player to learn who they just met. Source-pinned like the rest of the DialogueManager
## contract (it is an autoload with NO class_name, so the start() flow can't be driven from a unit test — see the
## header of test_dialogue.gd). The `speaker`/`speaker_name` PARAMETER names also pin that this lives in start(),
## not in the legacy per-line reveal in _show_line (which reads the `_speaker` members).
func test_start_reveals_the_speaker_on_any_conversation() -> void:
	var src := FileAccess.get_file_as_string(DIALOGUE_MANAGER_PATH)
	var expected := "if _speaker_is_character():\n\t\t\tGameState.reveal_name(_speaker_name, _speaker_identity(speaker, speaker_name))"
	assert_string_contains(src, expected)

## ...and it is gated to real CHARACTERS: an inanimate DialogueNPC (terminal / sign) or a null-speaker note was
## never Stranger-masked, so it must never land in the known-names ledger either. The gate is the same
## resolved_disposition() marker every other masked surface keys on.
func test_speaker_is_character_gate_still_marks_only_npcs() -> void:
	var src := FileAccess.get_file_as_string(DIALOGUE_MANAGER_PATH)
	var expected := "func _speaker_is_character() -> bool:\n\treturn _speaker != null and is_instance_valid(_speaker) and _speaker.has_method(&\"resolved_disposition\")"
	assert_string_contains(src, expected)
