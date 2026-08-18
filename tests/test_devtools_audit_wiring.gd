extends GutTest

## Unit tests for the WIRING AUDITS' PURE predicates (scan_wiring.gd) — the flag classifier, the quest-id /
## objective-id resolvers, and the faction-id resolver + dict-key + filename-mismatch checks. Everything here
## runs on SMALL fixture strings/dicts (NOT real-project counts — those churn as content is authored). The
## editor glue (run()/_walk/_collect_* — DirAccess + load + EditorInterface-adjacent) is NOT exercised; the
## predicates are the only thing with real logic, and they're tree-free.

const Wiring = preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")


# --- PASS 1: story-flag collection + dead-gate / typo classification -----------------------------------------

func test_collect_flag_refs_tags_writers_and_readers() -> void:
	var text := "set_flag = &\"alarm_tripped\"\nrequired_flag = &\"door_opened\"\n"
	var refs := Wiring.collect_flag_refs(text)
	assert_true(refs["write"].has("alarm_tripped"), "set_flag is a WRITE field — alarm_tripped should be a writer")
	assert_true(refs["read"].has("door_opened"), "required_flag is a READ field — door_opened should be a reader")

func test_collect_flag_refs_flag_objective_target_id_is_a_read() -> void:
	# A FLAG QuestObjective (type = 5) makes its target_id a flag READ; without the FLAG type it must NOT count.
	var with_flag := "type = 5\ntarget_id = &\"intel_found\"\n"
	var refs := Wiring.collect_flag_refs(with_flag)
	assert_true(refs["read"].has("intel_found"), "a FLAG objective's target_id is a flag the quest READS")
	var kill := "type = 0\ntarget_id = &\"raider_boss\"\n"
	var refs2 := Wiring.collect_flag_refs(kill)
	assert_false(refs2["read"].has("raider_boss"), "a non-FLAG objective's target_id must NOT be treated as a flag")

func test_collect_flag_refs_target_id_scoped_per_block() -> void:
	# A Quest .tres holds many mixed-type QuestObjective sub_resources; target_id is overloaded. Only a block that
	# is ITSELF a FLAG type (type = 5) contributes its target_id as a flag read — a sibling KILL block must not.
	var mixed := "[sub_resource type=\"Resource\" id=\"o1\"]\ntype = 5\ntarget_id = &\"intel_found\"\n\n[sub_resource type=\"Resource\" id=\"o2\"]\ntype = 0\ntarget_id = &\"raider_boss\"\n"
	var refs := Wiring.collect_flag_refs(mixed)
	assert_true(refs["read"].has("intel_found"), "the FLAG block's target_id is a flag read")
	assert_false(refs["read"].has("raider_boss"), "the KILL block's target_id must NOT leak in as a flag read (per-block, not per-file)")

func test_collect_flag_refs_bare_autoload_calls() -> void:
	var src := "GameState.set_flag(&\"met_mayor\")\nif GameState.get_flag(&\"saw_intro\"): pass\n"
	var refs := Wiring.collect_flag_refs(src)
	assert_true(refs["write"].has("met_mayor"), "a bare set_flag(...) call is a WRITE")
	assert_true(refs["read"].has("saw_intro"), "a bare get_flag(...) call is a READ")

func test_collect_flag_refs_recognizes_readable_and_cutscene_writers() -> void:
	# PL4: Readable.set_flag_on_read and CutsceneAction.flag_name both call GameState.set_flag — so they are flag
	# WRITERS. Without them, a flag written only by a Readable and read by a dialogue gate is mis-reported as a dead gate.
	var text := "set_flag_on_read = &\"note_read\"\nflag_name = &\"cutscene_seen\"\n"
	var refs := Wiring.collect_flag_refs(text)
	assert_true(refs["write"].has("note_read"), "Readable.set_flag_on_read is a flag WRITER")
	assert_true(refs["write"].has("cutscene_seen"), "CutsceneAction.flag_name is a flag WRITER")

func test_set_flag_field_does_not_false_match_set_flag_on_read() -> void:
	# The field regex anchors ^\s*<field>\s*=, so the shorter "set_flag" writer entry must NOT also swallow a
	# set_flag_on_read line (which would yield a blank "" flag name). Each field is matched on its own exact name.
	var refs := Wiring.collect_flag_refs("set_flag_on_read = &\"only_readable\"\n")
	assert_true(refs["write"].has("only_readable"), "set_flag_on_read is collected under its own field name")
	assert_false(refs["write"].has(""), "the shorter set_flag entry must not false-match and yield a blank flag name")

func test_obj_type_flag_ordinal_matches_enum() -> void:
	# PL4 drift pin: OBJ_TYPE_FLAG is a hand-mirror of the QuestObjective.Type.FLAG serialized ordinal. If the enum
	# is ever reordered, EVERY FLAG-objective wiring check silently mis-fires — pin the ordinal to the live enum here.
	assert_eq(Wiring.OBJ_TYPE_FLAG, int(QuestObjective.Type.FLAG), "scan_wiring.OBJ_TYPE_FLAG must equal the live QuestObjective.Type.FLAG ordinal")


func test_flag_findings_dead_gate_when_read_without_writer() -> void:
	var writers := {}
	var readers := {"ghost_gate": true}
	var out := Wiring.flag_findings(writers, readers)
	assert_eq(out.size(), 1, "a flag read with no writer is exactly one finding (a dead gate)")
	assert_eq(out[0]["severity"], "WARN", "a dead gate is a WARN, not an ERROR")
	assert_true(out[0]["message"].contains("dead gate"), "the dead-gate finding should name the problem")

func test_flag_findings_typo_when_write_without_reader() -> void:
	var writers := {"orphan_write": true}
	var readers := {}
	var out := Wiring.flag_findings(writers, readers)
	assert_eq(out.size(), 1, "a flag written with no reader is exactly one finding (a likely typo)")
	assert_true(out[0]["message"].contains("typo"), "the write-no-reader finding should mention a typo")

func test_flag_findings_clean_when_paired() -> void:
	var both := {"alarm": true}
	var out := Wiring.flag_findings(both, both)
	assert_eq(out.size(), 0, "a flag that is both written AND read is correctly wired — no finding")

func test_flag_findings_uses_source_map() -> void:
	var out := Wiring.flag_findings({}, {"x": true}, {"x": "res://a.tscn"})
	assert_eq(out[0]["source"], "res://a.tscn", "the finding's source should come from the src_of map")


# --- PASS 2: quest-id + objective-id resolution --------------------------------------------------------------

func test_resolve_quest_id_known_passes() -> void:
	assert_eq(Wiring.resolve_quest_id("rescue_op", {"rescue_op": true}), "", "a known quest id resolves cleanly (empty message)")

func test_resolve_quest_id_blank_is_ok() -> void:
	assert_eq(Wiring.resolve_quest_id("", {}), "", "a blank quest-id field is an unset export, not an error")

func test_resolve_quest_id_unknown_reports() -> void:
	var msg := Wiring.resolve_quest_id("typo_quest", {"real_quest": true})
	assert_ne(msg, "", "an unknown quest id must produce a non-empty error message")
	assert_true(msg.contains("typo_quest"), "the message should name the offending id")

func test_resolve_objective_id_known_passes() -> void:
	var by_quest := {"q1": {"o1": true, "o2": true}}
	assert_eq(Wiring.resolve_objective_id("q1", "o2", by_quest), "", "an objective the quest declares resolves cleanly")

func test_resolve_objective_id_missing_quest() -> void:
	var msg := Wiring.resolve_objective_id("ghost", "o1", {"q1": {"o1": true}})
	assert_ne(msg, "", "advancing an objective of a non-existent quest is an error")
	assert_true(msg.contains("ghost"), "the message should name the missing quest")

func test_resolve_objective_id_missing_objective() -> void:
	var msg := Wiring.resolve_objective_id("q1", "no_such", {"q1": {"o1": true}})
	assert_ne(msg, "", "advancing an objective the quest doesn't declare is an error")
	assert_true(msg.contains("no_such"), "the message should name the missing objective")

func test_resolve_objective_id_blank_is_ok() -> void:
	assert_eq(Wiring.resolve_objective_id("", "", {}), "", "a blank advance pair is an unset export, not an error")

func test_collect_quest_id_refs_finds_fields() -> void:
	var text := "complete_quest_id = &\"finale\"\nprereq_quest_id = &\"intro\"\n"
	var refs := Wiring.collect_quest_id_refs(text)
	var vals := []
	for r in refs:
		vals.append(r["value"])
	assert_true(vals.has("finale"), "complete_quest_id literal should be collected")
	assert_true(vals.has("intro"), "prereq_quest_id literal should be collected")

func test_collect_advance_pairs_pairs_positionally() -> void:
	var text := "advance_quest_id = &\"q1\"\nadvance_objective_id = &\"o1\"\n"
	var pairs := Wiring.collect_advance_pairs(text)
	assert_eq(pairs.size(), 1, "one advance_quest_id + one advance_objective_id should pair into one pair")
	assert_eq(pairs[0]["quest"], "q1", "the pair's quest should be q1")
	assert_eq(pairs[0]["objective"], "o1", "the pair's objective should be o1")

func test_collect_advance_pairs_skips_lone_half() -> void:
	var text := "advance_quest_id = &\"q1\"\n"  # objective half absent
	assert_eq(Wiring.collect_advance_pairs(text).size(), 0, "a lone advance_quest_id with no objective half makes no pair")

func test_collect_advance_pairs_per_block_no_index_drift() -> void:
	# First node is half-configured (advance_quest_id with NO advance_objective_id — allowed to ship). A flat
	# per-file zip would mispair node B's objective onto node A's quest; per-block pairing keeps B's pair its own.
	var text := "[node name=\"A\" type=\"Node3D\"]\nadvance_quest_id = &\"qA\"\n\n[node name=\"B\" type=\"Node3D\"]\nadvance_quest_id = &\"qB\"\nadvance_objective_id = &\"oB\"\n"
	var pairs := Wiring.collect_advance_pairs(text)
	assert_eq(pairs.size(), 1, "only the fully-configured second block yields a pair; the lone-half first block is skipped")
	assert_eq(pairs[0]["quest"], "qB", "the surviving pair must be the second block's OWN quest (no drift from block A)")
	assert_eq(pairs[0]["objective"], "oB", "the surviving pair must resolve to its own objective oB")


# --- PASS 3: faction-id resolution + dict keys + filename mismatch -------------------------------------------

func test_resolve_faction_id_known_passes() -> void:
	assert_eq(Wiring.resolve_faction_id("raiders", {"raiders": true}), "", "a known faction id resolves cleanly")

func test_resolve_faction_id_blank_is_ok() -> void:
	assert_eq(Wiring.resolve_faction_id("", {}), "", "a blank faction-id field is an unset export, not an error")

func test_resolve_faction_id_unknown_reports() -> void:
	var msg := Wiring.resolve_faction_id("raidres", {"raiders": true})
	assert_ne(msg, "", "a misspelled faction id must report")
	assert_true(msg.contains("raidres"), "the message should name the offending id")

func test_unknown_dict_keys_flags_only_bad_keys() -> void:
	var d := {&"raiders": -1.0, &"ghosts": 1.0}  # StringName keys, as Faction.relations uses
	var bad := Wiring.unknown_dict_keys(d, {"raiders": true})
	assert_eq(bad.size(), 1, "exactly one key (ghosts) names no real faction")
	assert_eq(bad[0], "ghosts", "the StringName key should normalise to the String 'ghosts'")

func test_unknown_dict_keys_clean_dict() -> void:
	var d := {"raiders": 5.0, "townsfolk": -3.0}
	assert_eq(Wiring.unknown_dict_keys(d, {"raiders": true, "townsfolk": true}).size(), 0, "all-known keys produce no findings")

func test_faction_id_filename_match() -> void:
	assert_eq(Wiring.faction_id_filename_mismatch("raiders", "raiders"), "", "matching internal id and filename is clean")

func test_faction_id_filename_mismatch_reports() -> void:
	var msg := Wiring.faction_id_filename_mismatch("raidrs", "raiders")
	assert_ne(msg, "", "an internal id that differs from the filename must report")
	assert_true(msg.contains("raidrs"), "the message should show the internal id")
	assert_true(msg.contains("raiders"), "the message should show the filename")

func test_collect_faction_id_refs_finds_fields() -> void:
	var text := "alarm_faction_id = \"raiders\"\nfaction_id = \"townsfolk\"\n"
	var refs := Wiring.collect_faction_id_refs(text)
	var vals := []
	for r in refs:
		vals.append(r["value"])
	assert_true(vals.has("raiders"), "alarm_faction_id literal should be collected")
	assert_true(vals.has("townsfolk"), "faction_id literal should be collected")


# --- finding-shape contract (matches scan_disk's {severity, source, message}) --------------------------------

func test_finding_shape_matches_scan_disk() -> void:
	var out := Wiring.flag_findings({}, {"x": true})
	var fnd: Dictionary = out[0]
	assert_true(fnd.has("severity"), "a finding has a severity key")
	assert_true(fnd.has("source"), "a finding has a source key")
	assert_true(fnd.has("message"), "a finding has a message key")
