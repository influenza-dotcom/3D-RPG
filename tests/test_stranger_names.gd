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
##
## JOB TITLES (the foot of this file): an un-introduced NPC who visibly holds a job reads as the JOB ("Merchant",
## "Gunsmith") instead of "Stranger" — public_name's optional `who` node arg, duck-typed on job_title() through
## GameState.job_title_of; NPC.job_title() prefers the authored NPC.job override, else the first service-station
## child; every station's answer is a PlayerText.JOB_* const and is roster-pinned here (JOB_COMPONENTS).

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

# --- Job titles: an un-introduced NPC with a JOB reads as the job, not "Stranger" ------------------------------

## A stand-in for anything wearing a job — the seam is duck-typed on job_title(), exactly like NPC.job_title and
## every service component, so the seam is exercised with no NPC or station in the picture.
class FakeWorker extends Node:
	var title: String = "Gunsmith"
	func job_title() -> String:
		return title

## Roster-as-spec: every service station that IS a job, and the PlayerText const it must answer with (referenced as
## the const, never a literal — the pin is "this component paints THIS authored const"). A new station that is a
## job adds a row here + a job_title() on the component; NOT_JOBS pins the two stations that deliberately aren't.
const JOB_COMPONENTS := {
	"res://scripts/components/merchant.gd": PlayerText.JOB_MERCHANT,
	"res://scripts/components/healer.gd": PlayerText.JOB_HEALER,
	"res://scripts/components/weapon_bench.gd": PlayerText.JOB_GUNSMITH,
	"res://scripts/components/chip_installer.gd": PlayerText.JOB_MECHANIC,
	"res://scripts/components/level_up.gd": PlayerText.JOB_TRAINER,
	"res://scripts/components/atm.gd": PlayerText.JOB_BANKER,
}
const NOT_JOBS: Array[String] = ["res://scripts/components/bonfire.gd", "res://scripts/components/chess_match.gd"]

func test_unknown_name_with_a_job_reads_the_job() -> void:
	var gs = load(GAMESTATE_PATH).new()
	var w := FakeWorker.new()
	assert_eq(gs.public_name("Marcus", w), "Gunsmith", "an un-introduced NPC with a job is shown by the job")
	assert_false(gs.name_is_revealed("Marcus"), "...and the job never counts as an introduction")
	gs.reveal_name("Marcus")
	assert_eq(gs.public_name("Marcus", w), "Marcus", "once introduced the real name wins over the job")
	w.free()
	gs.free()

func test_job_title_of_is_duck_typed_and_guarded() -> void:
	var gs = load(GAMESTATE_PATH).new()
	assert_eq(gs.job_title_of(null), "", "null -> no job")
	var plain := Node.new()
	assert_eq(gs.job_title_of(plain), "", "a node with no job_title() -> no job")
	assert_eq(gs.public_name("Marcus", plain), PlayerText.STRANGER, "...so it still reads Stranger")
	var w := FakeWorker.new()
	w.title = "   "
	assert_eq(gs.public_name("Marcus", w), PlayerText.STRANGER, "a whitespace title is no job")
	w.title = "  Merchant "
	assert_eq(gs.public_name("Marcus", w), "Merchant", "a title is trimmed")
	plain.free()
	w.free()
	gs.free()

func test_nameless_npc_with_a_job_reads_the_job() -> void:
	# A blank name is never "Stranger" (label hidden) — but a nameless shopkeeper still reads by the sign over the
	# counter, and keeps reading that way after a talk (there was never a name to learn).
	var gs = load(GAMESTATE_PATH).new()
	var w := FakeWorker.new()
	w.title = "Merchant"
	assert_eq(gs.public_name("", w), "Merchant", "a nameless NPC with a job reads as the job")
	gs.stranger_names_enabled = false
	assert_eq(gs.public_name("", w), "Merchant", "...even with masking off (there is no real name to show)")
	assert_eq(gs.public_name("", null), "", "a nameless NPC with NO job stays blank, never Stranger")
	w.free()
	gs.free()

func test_master_switch_off_still_shows_real_name_over_job() -> void:
	var gs = load(GAMESTATE_PATH).new()
	gs.stranger_names_enabled = false
	var w := FakeWorker.new()
	assert_eq(gs.public_name("Zeke", w), "Zeke", "masking OFF -> the real name, the job is not consulted")
	w.free()
	gs.free()

func test_every_service_station_answers_its_pinned_job_title() -> void:
	for path in JOB_COMPONENTS:
		var c = load(path).new()  # off-tree (no add_child -> no _ready), like test_dialogue_speaker_contracts
		assert_true(c.has_method(&"job_title"), "%s exposes job_title()" % path)
		assert_eq(c.job_title(), JOB_COMPONENTS[path], "%s answers its PlayerText.JOB_* const" % path)
		c.free()
	for path in NOT_JOBS:
		var c = load(path).new()
		assert_false(c.has_method(&"job_title"), "%s is not a job (no job_title)" % path)
		c.free()

func test_npc_job_title_prefers_authored_then_first_station_child() -> void:
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	assert_eq(npc.job_title(), "", "no job authored, no station -> no job")
	var bench = load("res://scripts/components/weapon_bench.gd").new()
	var shop = load("res://scripts/components/merchant.gd").new()
	npc.add_child(bench)
	npc.add_child(shop)
	assert_eq(npc.job_title(), PlayerText.JOB_GUNSMITH, "the FIRST station child (tree order) names the job")
	npc.job = "Arms Dealer"
	assert_eq(npc.job_title(), "Arms Dealer", "an authored NPC.job overrides the derived title")
	var gs = load(GAMESTATE_PATH).new()
	npc.display_name = "Vex"
	assert_eq(gs.public_name(npc.display_name, npc), "Arms Dealer", "...and the seam reads it through the NPC")
	gs.free()
	npc.free()

func test_killer_job_is_the_in_sentence_form() -> void:
	assert_eq(PlayerText.killer_job(PlayerText.JOB_GUNSMITH), "the gunsmith", "the death card lower-cases the title mid-sentence")
