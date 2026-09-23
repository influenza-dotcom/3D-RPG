extends GutTest

## "Stranger until introduced": GameState.reveal_name / name_is_revealed / public_name + the [world].known_names
## save/load round-trip + the New-Game wipe, and the reveal-on-talk seam (opening ANY
## conversation with a real character ends their Stranger status — driven through a real DialogueManager.start() in
## the middle of this file; the per-line reveals_name flag is now redundant for a character speaker). The ledger tests
## use a FRESH GameState instance (load().new()), never the autoload, so they can't touch the user's real
## user://gamestate.cfg — same isolation pattern as test_story_flags.gd. The reveal-on-talk test cannot: start() writes
## the LIVE GameState, so it snapshots and restores known_names (and with no player in the tree the reveal's coalesced
## autosave has nobody to save, so no file is written). The DISPLAY consumers (dialogue speaker label via
## DialogueManager, Talkable look-at readout, corpse loot header, death card, takedown prompt, cripple toast) are thin `public_name(...)`
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

## Unmistakable test-only names, so the live-ledger reveal test can never collide with a real introduction.
const TALK_CHARACTER_NAME := "Test Stranger Marcus Vell"
const TALK_CHARACTER_ID := &"test_stranger_marcus_vell"
const TALK_TERMINAL_NAME := "Test Stranger Relay Terminal"
const TALK_NOTE_NAME := "Test Stranger Pinned Note"

var _prev_known_names: Dictionary = {}
var _prev_mouse_mode: Input.MouseMode
var _prev_paused: bool = false
var _prev_music_db: float = 0.0
var _prev_stranger_names_enabled: bool = true

func before_each() -> void:
	_prev_known_names = GameState.known_names.duplicate()
	_prev_mouse_mode = Input.mouse_mode
	_prev_paused = get_tree().paused
	_prev_stranger_names_enabled = GameState.stranger_names_enabled
	var music := AudioServer.get_bus_index(&"music")
	_prev_music_db = AudioServer.get_bus_volume_db(music) if music >= 0 else 0.0

func after_each() -> void:
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	# The reveal-on-talk test drives real conversations: put back every global they touch.
	GameState.known_names = _prev_known_names
	Input.mouse_mode = _prev_mouse_mode
	get_tree().paused = _prev_paused
	GameState.stranger_names_enabled = _prev_stranger_names_enabled
	var music := AudioServer.get_bus_index(&"music")
	if music >= 0:
		AudioServer.set_bus_volume_db(music, _prev_music_db)

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

## A conversation partner that is a real CHARACTER, shaped by the same duck-typed markers DialogueManager keys on:
## resolved_disposition() (what makes a speaker Stranger-masked at all — every NPC has it, a terminal does not) and
## identity_key() (NPC.identity_key: NpcData.id, blank for an id-less NPC).
class FakeCharacter extends Node:
	var id: StringName = &""
	func resolved_disposition() -> int:
		return 0
	func identity_key() -> StringName:
		return id

## Open a one-line conversation on a FRESH DialogueManager in the test tree (never the autoload). Its _ready builds the
## view / ducker / music bed / face light start() needs; start() then runs synchronously up to its intro-beat timer,
## which is exactly the window the reveal must land in (before the box paints its first speaker label).
func _open_conversation(speaker: Node, speaker_name: String) -> Node:
	var line := DialogueLine.new()
	line.text = "..."
	var convo := DialogueResource.new()
	convo.lines = [line]
	var manager: Node = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(manager)
	manager.start(convo, speaker, null, speaker_name)
	return manager

## THE feature: talking to someone AT ALL ends their Stranger status. start() reveals a real character speaker as
## the conversation opens — so no authored line has to be ticked reveals_name for the player to learn who they just
## met — and it is gated to real CHARACTERS: an inanimate DialogueNPC (terminal / sign) or a speaker-less note was
## never Stranger-masked, so it must never land in the known-names ledger either (the three conversations share one
## setup, so the terminal and the note are the control cases for the character).
func test_opening_a_conversation_introduces_a_character_but_never_a_terminal_or_note() -> void:
	var marcus := FakeCharacter.new()
	marcus.id = TALK_CHARACTER_ID
	var terminal := Node.new()
	# Masking ON (the shipped default): with it off name_is_revealed() is true for everyone and the controls prove nothing.
	GameState.stranger_names_enabled = true
	assert_false(GameState.name_is_revealed(TALK_CHARACTER_NAME, TALK_CHARACTER_ID), "setup: the character starts un-introduced")
	assert_false(GameState.name_is_revealed(TALK_TERMINAL_NAME), "setup: the terminal starts un-recorded")
	assert_false(GameState.name_is_revealed(TALK_NOTE_NAME), "setup: the note starts un-recorded")
	var talks: Array[Node] = [
		_open_conversation(marcus, TALK_CHARACTER_NAME),
		_open_conversation(terminal, TALK_TERMINAL_NAME),
		_open_conversation(null, TALK_NOTE_NAME),
	]
	assert_true(GameState.name_is_revealed(TALK_CHARACTER_NAME, TALK_CHARACTER_ID),
		"opening a conversation with a character must introduce them at once — still masked here means the player reads 'Stranger' on someone they are talking to")
	assert_true(GameState.known_names.has(String(TALK_CHARACTER_ID)),
		"the introduction is keyed by the STABLE identity (NpcData.id), so a quest or a save matches it even if the display name changes")
	assert_eq(GameState.public_name(TALK_CHARACTER_NAME), TALK_CHARACTER_NAME,
		"...and the string-only display surfaces (look-at, corpse header, death card) show the real name too")
	assert_false(GameState.name_is_revealed(TALK_TERMINAL_NAME),
		"a terminal / sign speaker (no resolved_disposition) must never enter the known-names ledger")
	assert_false(GameState.name_is_revealed(TALK_NOTE_NAME),
		"a speaker-less note's cosmetic title must never enter the known-names ledger")
	for manager in talks:
		manager.abort()
	# Keep the managers alive past the intro timer so start()'s continuation returns on the ended conversation
	# instead of resuming on a freed instance.
	await wait_seconds(GameSettings.dialogue.dialogue_intro_delay + 0.15)
	marcus.free()
	terminal.free()

func test_speaker_is_character_gate_marks_only_live_characters() -> void:
	# The gate the reveal (and the Stranger mask on the speaker label) keys on, driven on an off-tree manager.
	var manager = load(DIALOGUE_MANAGER_PATH).new()
	assert_false(manager._speaker_is_character(), "no speaker at all (a note) is not a character")
	var terminal := Node.new()
	manager._speaker = terminal
	assert_false(manager._speaker_is_character(), "a terminal / sign (no resolved_disposition) is not a character")
	var marcus := FakeCharacter.new()
	manager._speaker = marcus
	assert_true(manager._speaker_is_character(), "a speaker carrying resolved_disposition() is a character")
	marcus.free()
	assert_false(manager._speaker_is_character(),
		"a character freed mid-conversation (shot during the intro beat) must read as no character, never crash the label paint")
	manager._speaker = null
	terminal.free()
	manager.free()

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
		assert_eq(c.job_title(), JOB_COMPONENTS[path], "%s must read as its PlayerText.JOB_* title to an un-introduced player (a weapon bench is a Gunsmith, a healer a Healer) — a wrong or blank title shows the wrong trade, or 'Stranger', over a service NPC" % path)
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
