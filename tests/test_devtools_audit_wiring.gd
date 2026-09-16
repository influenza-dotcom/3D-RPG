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


# --- PASS 4: dialogue target-id wiring (within one conversation) ------------------------------------------------
# The model is plain Dictionaries, built either from a LOADED DialogueResource (duck-typed) or PARSED from the
# serialized .tres / .tscn text -- the latter is how an inline conversation on a Talkable gets audited without
# instantiating its level. Both builders are pinned to agree; the predicate is then tested on hand-built models.

## A .tscn snippet in the exact shape Godot writes an inline conversation (a Talkable's `dialogue` authored as a
## sub-resource): three dialogue scripts as ext_resources, choice / line / resource sub_resource blocks, and the
## node that carries the conversation. Line 0 has an id and two choices: one by number (a legacy jump to line 1),
## one gated with a typo'd target id AND a typo'd fail id. Line 1 is id-less.
const SCENE_FIXTURE := """[gd_scene load_steps=5 format=3 uid="uid://fixture"]

[ext_resource type="Script" uid="uid://cjonbsqr2gwyj" path="res://scripts/dialogue/dialogue_line.gd" id="26_loova"]
[ext_resource type="Script" uid="uid://csb55tjjecvsy" path="res://scripts/dialogue/dialogue_choice.gd" id="27_888rm"]
[ext_resource type="Script" uid="uid://brjt78ou6p8py" path="res://scripts/dialogue/dialogue_resource.gd" id="28_42wi0"]
[ext_resource type="PackedScene" path="res://scenes/dialogue/talkable.tscn" id="9_talk"]

[sub_resource type="Resource" id="Choice_a"]
script = ExtResource("27_888rm")
text = "Zorkmids?"
target = 1
metadata/_custom_type_script = "uid://csb55tjjecvsy"

[sub_resource type="Resource" id="Choice_b"]
script = ExtResource("27_888rm")
text = "Relax!"
target_id = &"gret"
target_on_fail_id = &"nope"
required_stat = &"streetwise"
required_value = 2
metadata/_custom_type_script = "uid://csb55tjjecvsy"

[sub_resource type="Resource" id="Line_0"]
script = ExtResource("26_loova")
id = &"greet"
text = "You deaf or just dumb, kid?"
choices = Array[ExtResource("27_888rm")]([SubResource("Choice_a"), SubResource("Choice_b")])
metadata/_custom_type_script = "uid://cjonbsqr2gwyj"

[sub_resource type="Resource" id="Line_1"]
script = ExtResource("26_loova")
text = "Buzz off."
metadata/_custom_type_script = "uid://cjonbsqr2gwyj"

[sub_resource type="Resource" id="Convo"]
script = ExtResource("28_42wi0")
lines = Array[ExtResource("26_loova")]([SubResource("Line_0"), SubResource("Line_1")])
metadata/_custom_type_script = "uid://brjt78ou6p8py"

[node name="Level" type="Node3D"]

[node name="Talkable" parent="Characters/OldMan" instance=ExtResource("9_talk")]
dialogue = SubResource("Convo")
"""

## The same conversation as .new() resources, so the two model builders can be compared.
func _fixture_resource() -> DialogueResource:
	var r := DialogueResource.new()
	var l0 := DialogueLine.new()
	l0.id = &"greet"
	l0.text = "You deaf or just dumb, kid?"
	var a := DialogueChoice.new()
	a.text = "Zorkmids?"
	a.target = 1
	var b := DialogueChoice.new()
	b.text = "Relax!"
	b.target_id = &"gret"
	b.target_on_fail_id = &"nope"
	b.required_stat = &"streetwise"
	b.required_value = 2
	l0.choices = [a, b]
	var l1 := DialogueLine.new()
	l1.text = "Buzz off."
	r.lines = [l0, l1]
	return r


func test_dialogue_models_from_text_parses_an_inline_conversation() -> void:
	var models: Array = Wiring.dialogue_models_from_text(SCENE_FIXTURE)
	assert_eq(models.size(), 1, "the scene embeds exactly one conversation")
	assert_eq(String(models[0]["where"]), "Talkable under Characters/OldMan", "the finding can name the node that carries it")
	var lines: Array = models[0]["model"]["lines"]
	assert_eq(lines.size(), 2, "two lines, in the order the resource block lists them")
	assert_eq(String(lines[0]["id"]), "greet", "line 0's id was read off its block")
	assert_eq(String(lines[1]["id"]), "", "line 1 is id-less")
	var choices: Array = lines[0]["choices"]
	assert_eq(choices.size(), 2, "line 0's two choices, in choices-array order")
	assert_eq(choices[0], {"target_id": "", "target_on_fail_id": "", "target": 1, "target_on_fail": -1, "gated": false},
		"a by-number choice: blank ids, the serialized target, the omitted-default fail int (-1), ungated")
	assert_eq(choices[1], {"target_id": "gret", "target_on_fail_id": "nope", "target": -2, "target_on_fail": -1, "gated": true},
		"an id-addressed gated choice: both ids read, the omitted ints at their defaults, gated by its required_stat")


func test_dialogue_model_from_resource_agrees_with_the_text_model() -> void:
	var from_text: Dictionary = Wiring.dialogue_models_from_text(SCENE_FIXTURE)[0]["model"]
	var r := _fixture_resource()
	var from_res: Dictionary = Wiring.dialogue_model_from_resource(r)
	assert_eq(from_res, from_text, "the loaded-resource builder and the text parser produce the SAME model, so a .tres and an inline .tscn conversation are judged identically")
	assert_eq(Wiring.dialogue_model_from_resource(null), {"lines": []}, "a null resource is an empty model, no crash")
	r = null


func test_dialogue_findings_in_text_names_the_node_and_reports_the_three_problems() -> void:
	var out: Array = Wiring.dialogue_findings_in_text(SCENE_FIXTURE, "res://scenes/levels/x.tscn")
	assert_eq(out.size(), 3, "two dangling ids (ERROR) + one by-number nudge (WARN)")
	var errors := 0
	var warns := 0
	for f in out:
		assert_true(String(f["message"]).begins_with("Talkable under Characters/OldMan: "), "every row names the node that carries the inline conversation")
		assert_eq(f["source"], "res://scenes/levels/x.tscn", "and the scene file")
		assert_eq(f["domain"], "content", "a wiring slip is content, so it sits in the designer's default view")
		if f["severity"] == "ERROR":
			errors += 1
		else:
			warns += 1
	assert_eq(errors, 2, "gret (Target) and nope (Fail target) are both ERRORs -- the fail id is checked even though it is only live when gated")
	assert_eq(warns, 1, "the by-number jump to line 1 is a WARN because this conversation has started using ids")
	var first_error := ""
	for f in out:
		if f["severity"] == "ERROR":
			first_error = String(f["message"])
			break
	assert_true(first_error.contains("ids here: greet"), "a dangling-id row lists the ids that DO exist")


func test_dialogue_findings_legacy_conversation_is_silent_and_out_of_range_is_an_error() -> void:
	var legacy := {"lines": [
		{"id": "", "choices": [{"target_id": "", "target_on_fail_id": "", "target": 1, "target_on_fail": -1, "gated": false}]},
		{"id": "", "choices": [{"target_id": "", "target_on_fail_id": "", "target": -2, "target_on_fail": -1, "gated": false}]},
	]}
	assert_eq(Wiring.dialogue_findings(legacy, "res://a.tres").size(), 0, "a wholly by-number conversation (no id anywhere) produces NO finding -- every conversation authored before ids must stay quiet")
	var bad := {"lines": [
		{"id": "", "choices": [{"target_id": "", "target_on_fail_id": "", "target": 5, "target_on_fail": -3, "gated": true}]},
	]}
	var out: Array = Wiring.dialogue_findings(bad, "res://a.tres")
	assert_eq(out.size(), 2, "an out-of-range number and a below-CONTINUE number are both ERRORs (the check scan_disk used to carry)")
	assert_eq(out[0]["severity"], "ERROR", "severity")
	assert_true(String(out[0]["message"]).contains("Line 0: a choice's Target points at line 5, which doesn't exist"), "the legacy wording is kept, with the designer's dropdown label")
	assert_true(String(out[1]["message"]).contains("Fail target"), "the fail branch names its own dropdown")


func test_dialogue_findings_duplicate_and_reserved_line_ids_are_errors() -> void:
	var model := {"lines": [
		{"id": "greet", "choices": []},
		{"id": "greet", "choices": []},
		{"id": "END", "choices": []},
	]}
	var out: Array = Wiring.dialogue_findings(model, "res://a.tres")
	assert_eq(out.size(), 2, "one duplicate + one reserved word")
	assert_true(String(out[0]["message"]).contains("Line 1 has id \"greet\", which line 0 already uses"), "the duplicate names both lines")
	assert_true(String(out[1]["message"]).contains("Line 2's id is \"END\", a reserved word"), "the reserved word says why the line is unreachable")
	for f in out:
		assert_eq(f["severity"], "ERROR", "both are ERRORs: the resolver silently takes the first / the word")


func test_dialogue_findings_by_number_nudge_rules() -> void:
	# ids in use (line 0), so a by-number REAL jump warns; a sentinel int does not; the fail branch only when gated.
	var model := {"lines": [
		{"id": "greet", "choices": [
			{"target_id": "", "target_on_fail_id": "", "target": 1, "target_on_fail": -1, "gated": false},  # WARN (target by number)
			{"target_id": "CONTINUE", "target_on_fail_id": "", "target": -2, "target_on_fail": 1, "gated": false},  # silent: ungated fail branch
			{"target_id": "CONTINUE", "target_on_fail_id": "", "target": -2, "target_on_fail": 1, "gated": true},  # WARN (gated fail by number)
			{"target_id": "", "target_on_fail_id": "", "target": -2, "target_on_fail": -1, "gated": true},  # silent: sentinel ints are not positional
		]},
		{"id": "", "choices": []},
	]}
	var out: Array = Wiring.dialogue_findings(model, "res://a.tres")
	assert_eq(out.size(), 2, "exactly the two positional by-number branches warn")
	for f in out:
		assert_eq(f["severity"], "WARN", "a nudge, not breakage -- the conversation still plays")
		assert_true(String(f["message"]).contains("Migrate to Ids"), "and it names the fix")
	assert_true(String(out[0]["message"]).contains("Target still points by line number (line 1)"), "the first names the Target")
	assert_true(String(out[1]["message"]).contains("Fail target still points by line number (line 1)"), "the second names the gated Fail target")
	# The nudge is keyed on the conversation using ids ANYWHERE -- a choice id alone (no line id) is enough.
	var choice_only := {"lines": [
		{"id": "", "choices": [
			{"target_id": "END", "target_on_fail_id": "", "target": -2, "target_on_fail": -1, "gated": false},
			{"target_id": "", "target_on_fail_id": "", "target": 0, "target_on_fail": -1, "gated": false},
		]},
	]}
	assert_eq(Wiring.dialogue_findings(choice_only, "res://a.tres").size(), 1, "one choice already by id makes the by-number sibling a mixed-state WARN")


func test_dialogue_models_from_text_reads_a_tres_main_resource_and_ignores_other_files() -> void:
	var tres := """[gd_resource type="Resource" script_class="DialogueResource" format=3]

[ext_resource type="Script" path="res://scripts/dialogue/dialogue_line.gd" id="1_line"]
[ext_resource type="Script" path="res://scripts/dialogue/dialogue_choice.gd" id="2_choice"]
[ext_resource type="Script" path="res://scripts/dialogue/dialogue_resource.gd" id="3_dialogue"]

[sub_resource type="Resource" id="Choice_transmit"]
script = ExtResource("2_choice")
target_id = &"done"
target_on_fail_id = &"END"

[sub_resource type="Resource" id="Line_prompt"]
script = ExtResource("1_line")
id = &"prompt"
choices = Array[ExtResource("2_choice")]([SubResource("Choice_transmit")])

[sub_resource type="Resource" id="Line_done"]
script = ExtResource("1_line")
id = &"done"

[resource]
script = ExtResource("3_dialogue")
lines = Array[ExtResource("1_line")]([SubResource("Line_prompt"), SubResource("Line_done")])
"""
	var models: Array = Wiring.dialogue_models_from_text(tres)
	assert_eq(models.size(), 1, "the [resource] block is the conversation")
	assert_eq(String(models[0]["where"]), "", "a .tres has no carrying node -- the source path names it")
	assert_eq(Wiring.dialogue_findings(models[0]["model"], "res://x.tres").size(), 0, "a clean, fully id-addressed conversation has no findings")
	assert_eq(Wiring.dialogue_models_from_text("[gd_scene format=3]\n[node name=\"X\" type=\"Node3D\"]\n").size(), 0, "a file with no dialogue scripts yields no models (and no false conversation)")


# --- PASS 2b: quest stages -----------------------------------------------------------------------------------------

func _stage(sid: StringName, next := &"") -> QuestStage:
	var st := QuestStage.new()
	st.id = sid
	st.next_stage_id = next
	return st


func test_quest_stage_problems_is_silent_for_a_stage_less_quest_and_a_clean_staged_one() -> void:
	var plain := Quest.new()
	plain.objectives.append(QuestObjective.new())
	assert_eq(Wiring.quest_stage_problems(plain).size(), 0, "a stage-less quest (every quest before stages) has no stage findings")
	var q := Quest.new()
	q.stages = [_stage(&"a", &"b"), _stage(&"b")]
	assert_eq(Wiring.quest_stage_problems(q).size(), 0, "unique ids + a next_stage_id that resolves + a terminal stage = clean")
	assert_eq(Wiring.quest_stage_problems(null).size(), 0, "null is no quest, no crash")


func test_quest_stage_problems_reports_blank_duplicate_and_dangling_ids() -> void:
	var q := Quest.new()
	q.stages = [_stage(&"a", &"gone"), _stage(&""), _stage(&"a"), null]
	q.objectives.append(QuestObjective.new())
	var out: Array = Wiring.quest_stage_problems(q)
	var by_sev := {"ERROR": 0, "WARN": 0}
	var text := ""
	for f in out:
		by_sev[f["severity"]] += 1
		text += String(f["message"]) + "\n"
	assert_eq(by_sev["ERROR"], 3, "blank id + duplicate id + dangling next_stage_id are ERRORs")
	assert_eq(by_sev["WARN"], 2, "a null stage row + the ignored quest-level objectives are WARNs")
	assert_true(text.contains("stage 2 has no id"), "the blank id names the row")
	assert_true(text.contains("reuses the id \"a\" (stage 1 already has it)"), "the duplicate names both rows")
	assert_true(text.contains("moves on to stage \"gone\""), "the dangling next_stage_id names the id")
	assert_true(text.contains("its own 1 are ignored"), "the ignored-objectives warning says how many")


func test_resolve_stage_jump() -> void:
	var quests := {"heist": true, "plain": true}
	var stages := {"heist": {"intro": true, "inside": true}}
	assert_eq(Wiring.resolve_stage_jump("heist", "inside", quests, stages), "", "a real stage of a staged quest resolves")
	assert_eq(Wiring.resolve_stage_jump("heist", "", quests, stages), "", "a blank stage id is an unset field")
	assert_true(Wiring.resolve_stage_jump("", "inside", quests, stages).contains("names no quest"), "a stage with no quest half is an error")
	assert_true(Wiring.resolve_stage_jump("plain", "inside", quests, stages).contains("has no stages"), "jumping a stage-less quest is an error")
	assert_true(Wiring.resolve_stage_jump("heist", "vault", quests, stages).contains("doesn't have"), "an unknown stage is an error")
	assert_eq(Wiring.resolve_stage_jump("ghost", "inside", quests, stages), "", "an unknown QUEST is left to the quest-id resolver (reported once, not twice)")


func test_collect_stage_jumps_pairs_within_a_block() -> void:
	var text := "[sub_resource type=\"Resource\" id=\"c1\"]\nadvance_quest_id = &\"heist\"\nset_quest_stage_id = &\"inside\"\n\n[sub_resource type=\"Resource\" id=\"c2\"]\nset_quest_stage_id = &\"orphan\"\n\n[sub_resource type=\"Resource\" id=\"c3\"]\nadvance_quest_id = &\"heist\"\nadvance_objective_id = &\"x\"\n"
	var jumps: Array = Wiring.collect_stage_jumps(text)
	assert_eq(jumps.size(), 2, "one jump per block that names a stage (the objective-only block makes none)")
	assert_eq(jumps[0], {"quest": "heist", "stage": "inside"}, "the stage pairs with its own block's quest")
	assert_eq(jumps[1], {"quest": "", "stage": "orphan"}, "a stage with no quest in its block keeps a blank quest half (that is the finding)")


func test_set_flag_on_enter_is_a_flag_writer() -> void:
	var refs := Wiring.collect_flag_refs("set_flag_on_enter = &\"reached_vault\"\n")
	assert_true(refs["write"].has("reached_vault"), "QuestStage.set_flag_on_enter sets a flag -- without this a gate reading it is a false 'dead gate'")
	assert_false(refs["write"].has(""), "the shorter set_flag entry does not false-match set_flag_on_enter")
