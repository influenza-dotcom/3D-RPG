extends GutTest

## Slice 3: STABLE NPC IDENTITY — display names are no longer identity keys. Pins the three seams end to end:
## NpcData.id + identity_key() (blank id falls back to StringName(display_name), so nothing authored changes key),
## NPC.identity_key()'s derivation + the _ready rename-latch (a claimed pet's runtime display_name rename must NOT
## move its quest-match key), GameState's identity-first KILL/TALK matching with the authored-display fallback
## (pre-identity quest .tres keep working unedited), and the v3 -> v4 known_names LAZY save migration (legacy
## name-string entries stay readable; unmatched ones degrade to "not yet introduced"). Off-tree per convention:
## NPCs built via load(path).new() WITHOUT add_child (never _ready — the latch line is invoked directly), a fresh
## GameState instance (never the autoload), Resources released with = null.

const GAMESTATE_PATH := "res://managers/GameState.gd"
const NPC_PATH := "res://scripts/npc/npc.gd"
const TMP_SAVE := "user://test_character_identity.cfg"

func after_each() -> void:
	for p in [TMP_SAVE, TMP_SAVE + ".tmp", TMP_SAVE + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _kill_obj(oid: StringName, target: StringName, cnt := 1) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = oid
	o.type = QuestObjective.Type.KILL
	o.target_id = target
	o.required_count = cnt
	return o

func _quest(qid: StringName, objs: Array) -> Quest:
	var q := Quest.new()
	q.id = qid
	for o in objs:
		q.objectives.append(o)
	return q

# --- NpcData.identity_key (the ONE canonical accessor) -------------------------------------------------------

func test_npc_data_identity_key_blank_id_falls_back_to_display_name() -> void:
	var d := NpcData.new()
	d.display_name = "Marcus"
	assert_eq(d.identity_key(), &"Marcus", "blank id -> StringName(display_name): every pre-identity resource keys exactly as before")
	d.id = &"marcus_fence"
	assert_eq(d.identity_key(), &"marcus_fence", "an authored id wins over the display name")
	d = null

# --- NPC.identity_key derivation (off-tree: the live fallback path, _ready never ran) ------------------------

func test_npc_identity_key_prefers_profile_id_else_effective_display_name() -> void:
	var npc = load(NPC_PATH).new()
	npc.display_name = "Marcus"
	assert_eq(npc.identity_key(), &"Marcus", "no profile -> the display name (today's key, unchanged)")
	var d := NpcData.new()
	d.display_name = "Townsperson"
	npc.profile = d
	# Blank-id profile: the EFFECTIVE display name must win, NOT profile.display_name — on the additive-merge
	# path an inline display_name override survives the stamp and is that instance's authored identity.
	assert_eq(npc.identity_key(), &"Marcus", "blank-id profile -> the NPC's effective display name, never the archetype's")
	d.id = &"marcus_fence"
	assert_eq(npc.identity_key(), &"marcus_fence", "a profile with an authored id -> that id (routed through NpcData.identity_key)")
	npc.free()
	d = null

func test_claimed_pet_rename_does_not_change_quest_key() -> void:
	# claimable.gd _apply_name writes a player-typed pet name into host.display_name at claim time. Pre-Slice-3 the
	# kill key WAS the display string, so a renamed pet silently stalled its own KILL/TALK objectives. The _ready
	# latch (invoked directly here — off-tree NPCs never run _ready) pins the key to the AUTHORED name for life.
	var npc = load(NPC_PATH).new()
	npc.display_name = "Dog"
	npc._identity_key = npc._derive_identity_key()  # the exact latch line _ready runs post-profile-stamp
	npc.set(&"display_name", "Rex")  # Claimable._apply_name's runtime write
	assert_eq(npc.identity_key(), &"Dog", "the latched key ignores a runtime rename — 'kill/talk Dog' objectives keep matching")
	assert_eq(npc.display_name, "Rex", "...while the DISPLAY name really did change (display and identity are now separate)")
	npc.free()

# --- Two NPCs sharing one display_name stay distinct once ids are authored -----------------------------------

func test_shared_display_name_with_distinct_ids_stays_distinct() -> void:
	var a := NpcData.new()
	a.display_name = "Guard"
	a.id = &"guard_a"
	var b := NpcData.new()
	b.display_name = "Guard"
	b.id = &"guard_b"
	assert_ne(a.identity_key(), b.identity_key(), "same display_name, different ids -> different identities")
	# Quest identity: an objective keyed to guard_a is NOT advanced by guard_b's death (same shown name).
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_kill_obj(&"hit", &"guard_a")]))
	gs.notify_kill(b.identity_key(), StringName(b.display_name))
	assert_false(gs.is_quest_completed(&"q1"), "killing guard_b does not advance a guard_a objective despite the shared name")
	gs.notify_kill(a.identity_key(), StringName(a.display_name))
	assert_true(gs.is_quest_completed(&"q1"), "killing guard_a does")
	# Known-names ledger: revealing guard_a records guard_a's identity, not guard_b's.
	gs.reveal_name("Guard", &"guard_a")
	assert_true(gs.known_names.has("guard_a"), "the reveal records guard_a's identity key")
	assert_false(gs.known_names.has("guard_b"), "guard_b's identity stays un-introduced")
	# Pinned LIMITATION: the display-compat bridge writes the shared NAME string too, and the string-only display
	# surfaces (public_name(display_name)) can't tell the two apart — so on DISPLAY both read revealed. Identity
	# consumers (quests, the ledger keys above) stay distinct; an identity-aware display pass is future work.
	assert_true(gs.name_is_revealed("Guard", &"guard_b"), "display bridge: the shared name string reads revealed for both (documented display-only merge)")
	gs.free()
	a = null
	b = null

# --- Identity-first quest matching with the authored-display fallback ----------------------------------------

func test_kill_objective_matches_identity_or_display_fallback() -> void:
	var gs = load(GAMESTATE_PATH).new()
	# A pre-identity quest .tres authored against the display string (clear_the_block's &"Raider") keeps working
	# when the killed NPC now reports an identity id.
	gs.start_quest(_quest(&"q1", [_kill_obj(&"hunt", &"Raider")]))
	gs.notify_kill(&"raider_boss", &"Raider")
	assert_true(gs.is_quest_completed(&"q1"), "a display-name-authored objective advances via the legacy fallback")
	# An identity-authored objective matches on the id itself.
	gs.start_quest(_quest(&"q2", [_kill_obj(&"hunt2", &"raider_boss")]))
	gs.notify_kill(&"raider_boss", &"Raider")
	assert_true(gs.is_quest_completed(&"q2"), "an identity-authored objective advances on the identity key")
	gs.free()

func test_objective_matching_both_forms_advances_once() -> void:
	# Every id-less NPC reports identity == display string; the matcher's != guard must not double-advance.
	var gs = load(GAMESTATE_PATH).new()
	gs.start_quest(_quest(&"q1", [_kill_obj(&"hunt", &"Raider", 2)]))
	gs.notify_kill(&"Raider", &"Raider")
	assert_eq(gs.objective_progress(&"q1", &"hunt"), 1, "one kill -> exactly one advance even when identity == display name")
	gs.free()

# --- v3 -> v4 save migration (LAZY: legacy name keys stay readable; see the known_names load site) -----------

func test_v3_known_names_load_readable_and_degrade_gracefully() -> void:
	# Hand-built v3 payload: [world].known_names entries are raw display-name strings.
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("world", "known_names", ["Marcus", "Psycho Sniper"])
	assert_eq(cfg.save(TMP_SAVE), OK, "the hand-built v3 save writes")
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the v3 save loads")
	assert_eq(gs.save_version, 3, "the pre-migration schema version is recorded")
	# Legacy name entries keep resolving: for an id-less NPC the v3 key IS the v4 identity key.
	assert_true(gs.name_is_revealed("Marcus"), "a v3 legacy name entry stays readable (lazy migration)")
	assert_eq(gs.public_name("Psycho Sniper"), "Psycho Sniper", "a spaced legacy name resolves on the display seam")
	# An NPC that GAINS an id but keeps its display name still resolves through the legacy entry (accept-either).
	assert_true(gs.name_is_revealed("Marcus", &"marcus_fence"), "identity-carrying query still matches the legacy name entry")
	# Unmatched legacy keys DEGRADE to "not yet introduced" — the graceful direction (a Stranger again, never a
	# wrongly-revealed name): an edited display string, or an id-authored NPC never met under v3.
	assert_false(gs.name_is_revealed("Markus"), "an edited display name no longer matches -> Stranger again")
	assert_false(gs.name_is_revealed("Elena", &"elena_id"), "an id-authored NPC never introduced in the v3 save stays a Stranger")
	gs.free()

func test_v3_save_restamps_v4_and_keys_survive() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 3)
	cfg.set_value("world", "known_names", ["Marcus"])
	assert_eq(cfg.save(TMP_SAVE), OK, "the hand-built v3 save writes")
	var gs = load(GAMESTATE_PATH).new()
	assert_true(gs.load_from_disk(TMP_SAVE), "the v3 save loads")
	gs.reveal_name("Elena", &"elena_id")  # a post-migration reveal writes the identity key (+ display bridge)
	gs.save_to_disk(TMP_SAVE)
	var reread := ConfigFile.new()
	assert_eq(reread.load(TMP_SAVE), OK, "the re-saved file reads back")
	# Read the constant rather than a literal: this assert is about "re-saving stamps whatever the CURRENT
	# schema is", not about any particular number, and a hardcoded one silently goes red on every version bump.
	assert_eq(int(reread.get_value("meta", "version", 0)), GameState.SAVE_VERSION, "re-saving stamps the current schema")
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the re-saved current-schema save loads")
	assert_true(gs2.name_is_revealed("Marcus"), "the carried-forward legacy name entry survives the re-save")
	assert_true(gs2.name_is_revealed("Elena", &"elena_id"), "the identity-keyed reveal survives the round-trip")
	assert_true(gs2.name_is_revealed("Elena"), "...and so does its display-compat bridge entry")
	gs.free()
	gs2.free()
