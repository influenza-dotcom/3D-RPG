extends GutTest

## The STORY command family (scripts/components/debug_actions_world_story.gd: `flag`, `flags`, `quest`, `quests`,
## `notify`, `ledger`, `wipeobjects`, `resurrect`, `names`), split out of debug_actions_world.gd on 2026-09-11.
## Pins (1) the static surface the dispatcher routes into and the registry<->family verb parity for `quest` /
## `notify` BY SOURCE SCAN (test_debug_commands.gd's approach — run() writes real GameState / QuestTracker
## state so it is never driven blind), (2) the pure helpers (objective type words, notify verb mapping, objective
## lookup on the authored quests and on a hand-built one) with concrete inputs, and (3) the READ-ONLY command paths
## (`flag <unset>`, `flag <unset> clear`, `quest show`, `quests`, `flags`, `ledger`) which only read GameState /
## QuestTracker. `names` flips one in-memory bool and is snapshot/restored. The active-quest snapshot helpers and
## `ledger` read probe entries parked straight into QuestTracker's journal and GameState.world_objects (never through
## start_quest / record_object_state, which both queue an autosave), erased key-for-key in after_each.

const STORY_PATH := "res://scripts/components/debug_actions_world_story.gd"
const WORLD_PATH := "res://scripts/components/debug_actions_world.gd"
const Commands := preload("res://scripts/components/debug_commands.gd")
const Story := preload("res://scripts/components/debug_actions_world_story.gd")
const Common := preload("res://scripts/components/debug_actions_world_common.gd")

## A flag name no test or game code ever sets — every read below stays a miss and writes nothing.
const NEVER_FLAG := "__gut_story_probe_flag_never_set__"
## Quest ids the active-set test parks in the live tracker's journal (QuestTracker._quests_active) — never through
## start_quest, which emits quest_started, runs stage entry and queues an autosave. Erased in after_each.
const PROBE_QUESTS := [&"__gut_story_probe_quest_a__", &"__gut_story_probe_quest_b__", &"__gut_story_probe_quest_c__"]
## A level key no level ever loads: the ledger test parks one world_objects bucket under it. Erased in after_each.
const PROBE_LEVEL := "res://__gut_story_probe_level__.tres"

var _names_before: bool
## GameState.flags as found. `flags` is driven over hand-placed entries (written straight into the dictionary — never
## through set_flag, which notifies QuestTracker and AUTOSAVES) and put back key-for-key in after_each.
var _flags_before: Dictionary = {}


func before_each() -> void:
	_names_before = GameState.stranger_names_enabled
	_flags_before = GameState.flags.duplicate(true)


func after_each() -> void:
	GameState.stranger_names_enabled = _names_before
	GameState.flags.clear()
	GameState.flags.merge(_flags_before)
	for qid in PROBE_QUESTS:
		QuestTracker._quests_active.erase(qid)
	GameState.world_objects.erase(PROBE_LEVEL)


## Park `qid` in the live tracker's journal in the entry shape start_quest writes (a stage-less quest, no objectives).
func _park_active_quest(qid: StringName) -> void:
	var quest := Quest.new()
	quest.id = qid
	QuestTracker._quests_active[qid] = {"quest": quest, "stage": &"", "epoch": 0, "progress": {}}


func _static_names(script: GDScript) -> Dictionary:
	var out := {}
	for m in script.get_script_method_list():
		out[String(m["name"])] = true
	return out


func _arms_in(src: String, func_name: String) -> Dictionary:
	var start := src.find("static func %s(" % func_name)
	assert_gt(start, -1, "%s is defined" % func_name)
	if start < 0:
		return {}
	var end := src.find("\nstatic func ", start + 1)
	var body := src.substr(start, (end - start) if end > 0 else -1)
	var rx := RegEx.new()
	rx.compile("\\n\\t\\t\"([a-z_]+)\":")
	var out := {}
	for m in rx.search_all(body):
		out[m.get_string(1)] = true
	return out


func _load_quest(qid: String) -> Resource:
	var path := String(Common._quests().get(qid, ""))
	assert_ne(path, "", "quest '%s' is on disk" % qid)
	return load(path) as Resource if path != "" else null


# --- dispatch surface -------------------------------------------------------------------------------------------

func test_dispatcher_routes_into_statics_that_exist_and_none_is_dead() -> void:
	var names := _static_names(Story)
	var world_src := FileAccess.get_file_as_string(WORLD_PATH)
	var rx := RegEx.new()
	rx.compile("StoryActions\\.(_cmd_[a-z_]+)\\(")
	var routed := {}
	for m in rx.search_all(world_src):
		var fn := m.get_string(1)
		routed[fn] = true
		assert_true(names.has(fn), "debug_actions_world.gd routes to StoryActions.%s() which does not exist" % fn)
	for fn in names.keys():
		if String(fn).begins_with("_cmd_"):
			assert_true(routed.has(fn), "%s is defined in the story family but never routed (dead handler)" % String(fn))
	assert_gte(routed.size(), 9, "flag/flags/quest/quests/notify/ledger/wipeobjects/resurrect/names all route here")


func test_every_story_category_row_is_routed_to_this_family() -> void:
	# The Story page is this file's whole reason to exist: a Story row whose arm calls into the main file (or
	# nowhere) is a split that drifted.
	var world_src := FileAccess.get_file_as_string(WORLD_PATH)
	for row in Commands.in_category("Story"):
		var n := String(row["name"])
		assert_eq(row["mod"], &"world", "'%s' on the Story page is a world-module command" % n)
		var arm := world_src.find("\"%s\": return " % n)
		assert_gt(arm, -1, "'%s' has a dispatch arm" % n)
		if arm > -1:
			var line_end := world_src.find("\n", arm)
			var line := world_src.substr(arm, line_end - arm)
			assert_true(line.contains("StoryActions._cmd_"), "'%s' (Story page) must route into StoryActions: %s" % [n, line.strip_edges()])


func test_quest_verbs_match_the_registry_both_ways() -> void:
	var src := FileAccess.get_file_as_string(STORY_PATH)
	var arms := _arms_in(src, "_cmd_quest")
	var verbs: Array = Commands.find("quest")["verbs"]
	for v in verbs:
		assert_true(arms.has(String(v)), "registry verb 'quest %s' has no match arm in _cmd_quest — dead verb" % String(v))
	for a in arms.keys():
		assert_true(verbs.has(String(a)), "_cmd_quest handles '%s' but the registry never offers it" % String(a))


func test_notify_verbs_all_map_to_a_real_objective_type() -> void:
	var verbs: Array = Commands.find("notify")["verbs"]
	assert_gt(verbs.size(), 3, "notify lists its event words")
	for v in verbs:
		var t := Story._notify_type_for(String(v))
		assert_gte(t, 0, "notify verb '%s' maps to a QuestObjective.Type (-1 = registry/actions drift)" % String(v))
		assert_false(Story._objective_type_text(t).begins_with("type "), "and that type has a word in _objective_type_text")
	assert_eq(Story._notify_type_for("flag"), -1, "flags are set through `flag`, never notified — no mapping")
	assert_eq(Story._notify_type_for("zzz"), -1, "an unknown word is -1")


# --- pure helpers -----------------------------------------------------------------------------------------------

func test_objective_type_text_covers_the_enum_and_degrades() -> void:
	for key in QuestObjective.Type.keys():
		assert_eq(Story._objective_type_text(int(QuestObjective.Type[key])), String(key), "Type.%s renders as its word" % String(key))
	assert_eq(Story._objective_type_text(99), "type 99", "an unknown type prints its number rather than erroring")
	assert_eq(Story._objective_type_text(-1), "type -1", "the _int_of(-1) fallback for a missing `type` field is visible")


func test_notify_type_for_matches_the_objective_enum() -> void:
	assert_eq(Story._notify_type_for("kill"), int(QuestObjective.Type.KILL), "kill -> KILL")
	assert_eq(Story._notify_type_for("talk"), int(QuestObjective.Type.TALK), "talk -> TALK")
	assert_eq(Story._notify_type_for("pickup"), int(QuestObjective.Type.PICKUP), "pickup -> PICKUP")
	assert_eq(Story._notify_type_for("enter"), int(QuestObjective.Type.ENTER_AREA), "enter -> ENTER_AREA")
	assert_eq(Story._notify_type_for("use"), int(QuestObjective.Type.USE_ITEM), "use -> USE_ITEM")


func test_find_objective_is_exact_then_case_insensitive() -> void:
	# Precedence needs two ids that differ ONLY by case, which no shipped quest authors, so a hand-built stage-less quest
	# carries them, with the differently-cased one FIRST: a lookup that went straight to the case-insensitive pass would
	# hand that one back.
	var cased_first := QuestObjective.new()
	cased_first.id = &"Reach_Vault"
	var exact_second := QuestObjective.new()
	exact_second.id = &"reach_vault"
	var objectives: Array[QuestObjective] = [cased_first, exact_second]
	var twins := Quest.new()
	twins.objectives = objectives
	assert_true(Story._find_objective(twins, "reach_vault") == exact_second,
		"an exact id match wins over an EARLIER objective that only matches case-insensitively")
	assert_true(Story._find_objective(twins, "Reach_Vault") == cased_first,
		"the other exact spelling finds its own objective")
	assert_true(Story._find_objective(twins, "REACH_VAULT") == cased_first,
		"with no exact match, the first case-insensitive match is accepted (typing convenience)")
	var quest := _load_quest("clear_the_block")
	if quest == null:
		return
	var loose := Story._find_objective(quest, "REACH_VAULT")
	assert_not_null(loose, "a case-insensitive match is accepted (typing convenience)")
	if loose != null:
		assert_eq(String(loose.get("id")), "reach_vault", "the RESOLVED authored id is what comes back")
	assert_null(Story._find_objective(quest, "no_such_objective"), "a miss is null")
	assert_null(Story._find_objective(Resource.new(), "kill_raiders"), "a resource with no objectives array is null, never an error")


func test_objective_lines_list_every_authored_objective() -> void:
	var quest := _load_quest("clear_the_block")
	if quest == null:
		return
	var lines := Story._objective_lines(quest, &"clear_the_block")
	assert_eq(lines.size(), 2, "clear_the_block authors two objectives -> two lines")
	assert_true(lines[0].contains("kill_raiders"), "first objective id: %s" % lines[0])
	assert_true(lines[1].contains("reach_vault"), "second objective id: %s" % lines[1])
	var bare := Story._objective_lines(Resource.new(), &"x")
	assert_eq(bare.size(), 1, "no objectives array -> one explanatory line")
	assert_true(bare[0].contains("no objectives array"), "and it says so: %s" % bare[0])


func test_open_required_objectives_is_empty_for_a_non_active_quest() -> void:
	var quest := _load_quest("clear_the_block")
	if quest == null or QuestTracker.is_quest_active(&"clear_the_block"):
		return  # another test left it active — the contract below only holds for a NON-active quest
	assert_eq(Story._open_required_objectives(quest, &"clear_the_block").size(), 0, "a non-active quest has no OPEN objectives to report")


func test_active_id_set_and_new_active_since_are_consistent() -> void:
	# `quest advance` / `notify` snapshot the active set BEFORE firing the tracker, then name what the cascade started.
	# Anything already active (a quest another test left behind included) sits in the snapshot, so only this test's
	# probes can be reported as new.
	var already := StringName(PROBE_QUESTS[0])
	_park_active_quest(already)
	var before := Story._active_id_set()
	assert_true(before.has(String(already)),
		"an active quest is in the snapshot under its String id (the key _quest_advance looks next_quest up by)")
	assert_false(before.has(String(PROBE_QUESTS[1])), "a quest that is not active is not in the snapshot")
	assert_eq(Story._new_active_since(before).size(), 0, "nothing went active since the snapshot, so nothing is new")
	# Two more go active, parked in REVERSE name order: the report must still read alphabetically.
	_park_active_quest(StringName(PROBE_QUESTS[2]))
	_park_active_quest(StringName(PROBE_QUESTS[1]))
	assert_eq(Array(Story._new_active_since(before)), [String(PROBE_QUESTS[1]), String(PROBE_QUESTS[2])],
		"exactly the two quests that went active after the snapshot, sorted; the one active before it is not new")


# --- read-only command paths --------------------------------------------------------------------------------------

func test_flag_read_and_clear_on_an_unset_flag_write_nothing() -> void:
	var flags_before := GameState.flags.size()
	var read := Story._cmd_flag(PackedStringArray([NEVER_FLAG]))
	assert_eq(read.size(), 1, "reading an unset flag is one line")
	assert_eq(read[0], "%s: not set" % NEVER_FLAG, "and says it is not set")
	var clear := Story._cmd_flag(PackedStringArray([NEVER_FLAG, "clear"]))
	assert_eq(clear.size(), 1, "clearing an unset flag is one line")
	assert_true(clear[0].contains("was not set"), "and refuses rather than erasing: %s" % clear[0])
	var blank := Story._cmd_flag(PackedStringArray(["   "]))
	assert_eq(blank[0], "flag name is blank", "a whitespace name is rejected before any read")
	assert_eq(GameState.flags.size(), flags_before, "none of the three paths touched GameState.flags")
	assert_false(GameState.has_flag(NEVER_FLAG), "the probe flag is still unset")


func test_flags_lists_every_set_flag_sorted_and_names_a_flag_the_game_really_reads() -> void:
	GameState.flags.clear()
	var empty := Story._cmd_flags()
	assert_true(empty[0].contains("no story flags"), "with nothing set the first line says so rather than printing an empty list: %s" % empty[0])
	# Inserted OUT of order: the listing must sort, or two runs of `flags` over the same state read differently.
	GameState.flags["zz_gut_story_probe"] = true
	GameState.flags["aa_gut_story_probe"] = 3
	var out := Story._cmd_flags()
	var joined := "\n".join(out)
	var at_a := joined.find("aa_gut_story_probe")
	var at_z := joined.find("zz_gut_story_probe")
	assert_gt(at_a, -1, "a set flag is listed: %s" % joined)
	assert_gt(at_z, -1, "every set flag is listed: %s" % joined)
	assert_lt(at_a, at_z, "flags list alphabetically, whatever order they were set in: %s" % joined)
	for line in out:
		if line.contains("aa_gut_story_probe"):
			assert_true(line.strip_edges().ends_with("3"), "a flag's line carries its stored value, not just its name: %s" % line)
	assert_true(joined.contains("2 flag"), "the count line matches the number of flags set: %s" % joined)
	# The footer points a designer at the one flag that exists in code. Prove the name it prints is a flag the game
	# actually READS (the holster-forgiveness tutorial latch), not a stale spelling of it.
	var footer := out[out.size() - 1]
	var named := footer.split(" ", false)[-1]
	GameState.flags.clear()
	assert_false(GameState.holster_forgiveness_tutorial_seen(), "precondition: with no flags the tutorial reads unseen")
	GameState.flags[named] = true
	assert_true(GameState.holster_forgiveness_tutorial_seen(),
		"the flag the `flags` footer names ('%s') is the one the holster tutorial latch reads — setting it by that name marks the tutorial seen" % named)


func test_quest_show_reads_the_authored_quest_case_insensitively() -> void:
	var miss := Story._cmd_quest(PackedStringArray(["show", "__no_such_quest__"]))
	assert_eq(miss.size(), 1, "an unknown id is one line")
	assert_true(miss[0].begins_with("no quest with id"), "and it lists the ids to try: %s" % miss[0])
	assert_true(miss[0].contains("recover_package"), "the try-list carries Quest.id, not the file stem: %s" % miss[0])
	var show := Story._cmd_quest(PackedStringArray(["show", "RECOVER_PACKAGE"]))
	assert_gt(show.size(), 2, "show is a multi-line report")
	assert_true(show[0].begins_with("recover_package"), "the lookup is case-insensitive and the header carries the id: %s" % show[0])
	var extra := Story._cmd_quest(PackedStringArray(["show", "recover_package", "ignored", "3"]))
	assert_eq(extra[0], show[0], "slots 2 and 3 (objective id, amount) are ignored by show — not an arity error")


func test_quests_lists_ids_with_their_file_note() -> void:
	var out := Story._cmd_quests()
	var joined := "\n".join(out)
	assert_true(joined.contains("recover_package"), "recover_package is listed")
	assert_true(joined.contains("(file: recover_the_package.tres)"), "an id that differs from its file stem gets the file note")
	assert_true(joined.contains("clear_the_block"), "clear_the_block is listed")
	assert_true(joined.contains("keyed by Quest.id"), "the footer explains the keying")


func test_ledger_is_read_only_and_reports_every_section() -> void:
	# A world_objects bucket under a level that is NOT the current one: plain `ledger` reports the current level only,
	# so the bucket must stay out of it, and `ledger ALL` walks every level, so it must show up there. Parked before the
	# snapshot, so "never writes" is checked over a ledger that has something in it.
	assert_ne(String(GameState.current_level_path), PROBE_LEVEL, "precondition: the probe bucket is not the current level's")
	GameState.world_objects[PROBE_LEVEL] = {"id:gut_story_probe_door": {"open": true}}
	var wo_before := GameState.world_objects.duplicate(true)
	var out := Story._cmd_ledger(PackedStringArray())
	var joined := "\n".join(out)
	assert_true(out[0].begins_with("ledger — current level"), "header names the current level: %s" % out[0])
	assert_true(joined.contains("-- world_objects["), "section 1: the per-object ledger")
	assert_true(joined.contains("-- dead authored NPCs"), "section 2: the dead-NPC ledger")
	assert_true(joined.contains("-- discovered_corpses:"), "the corpse ledger line")
	assert_true(joined.contains("-- latches:"), "section 3: the latches")
	assert_false(joined.contains(PROBE_LEVEL),
		"plain `ledger` reports the current level only, so another level's bucket stays out of it: %s" % joined)
	var all := "\n".join(Story._cmd_ledger(PackedStringArray(["ALL"])))
	assert_true(all.contains("-- world_objects[\"%s\"]: 1 entry" % PROBE_LEVEL),
		"`ledger ALL` (any case) walks every level's bucket, including one that is not the current level: %s" % all)
	assert_true(all.contains("id:gut_story_probe_door"), "and lists that bucket's entries: %s" % all)
	assert_eq(GameState.world_objects, wo_before, "ledger never writes the ledger")


func test_names_flips_only_the_in_memory_veil_and_says_which_way() -> void:
	var on := Story._cmd_names(PackedStringArray(["on"]))
	assert_false(GameState.stranger_names_enabled, "`names on` = real names SHOWN = the veil OFF")
	assert_true(on[0].contains("names ON") and on[0].contains("SHOWN"), "the polarity is stated in the line: %s" % on[0])
	var off := Story._cmd_names(PackedStringArray(["off"]))
	assert_true(GameState.stranger_names_enabled, "`names off` restores the veil")
	assert_true(off[0].contains("veiled"), "and says so: %s" % off[0])
	var bare := Story._cmd_names(PackedStringArray())
	assert_false(GameState.stranger_names_enabled, "a bare `names` flips (veil was on -> shown)")
	assert_true(bare[0].contains("names ON"), "flip reported: %s" % bare[0])
