extends GutTest

## PURE tests for the dev-tools graph viewers (BUILD plugin item 5: Dialogue + Quest graph panels).
## graph_data.gd is a pure builder (no EditorInterface / no scene tree), so we feed it in-memory
## DialogueResource + Quest resources and assert node/edge counts + dangling-target detection. We also
## assert the two @tool Controls CONSTRUCT via .new() -- the GUT run is the real compile check for
## addon-only scripts (--import does not deep-compile them) -- and pin the tab's designer contract: the typed
## picker filter (a VoiceData beside the conversations must never be offered as one), the Show Graph / Open
## wording + disabled states, the two-line status with its tooltip mirror, and a mode switch that clears the
## drawing. The tabs are built bare and freed; nothing is add_child'ed and no handler touches EditorInterface.

const GraphData = preload("res://addons/cybersunday_tools/panel_graph/graph_data.gd")
const DialogueGraph = preload("res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd")
const QuestGraph = preload("res://addons/cybersunday_tools/panel_graph/quest_graph.gd")


# --- Dialogue builder -------------------------------------------------------------------------------

## Build a 3-line conversation: line0 has two choices (jump to line1, jump to line2), line1 continues (END),
## line2 has a choice with a DELIBERATELY out-of-range target (99). Expect 3 nodes, 2 real edges, 1 problem.
func _make_dialogue() -> DialogueResource:
	var res := DialogueResource.new()
	var l0 := DialogueLine.new()
	l0.text = "Start"
	var c0a := DialogueChoice.new()
	c0a.text = "go to 1"
	c0a.target = 1
	var c0b := DialogueChoice.new()
	c0b.text = "go to 2"
	c0b.target = 2
	l0.choices = [c0a, c0b]

	var l1 := DialogueLine.new()
	l1.text = "Middle"
	var c1 := DialogueChoice.new()
	c1.text = "end here"
	c1.target = DialogueLine.END  # terminal sentinel -> NOT an edge
	l1.choices = [c1]

	var l2 := DialogueLine.new()
	l2.text = "Bad branch"
	var c2 := DialogueChoice.new()
	c2.text = "dangling"
	c2.target = 99  # out of range -> a problem, no edge
	l2.choices = [c2]

	res.lines = [l0, l1, l2]
	return res


func test_dialogue_node_and_edge_counts() -> void:
	var res := _make_dialogue()
	var g: Dictionary = GraphData.build_dialogue(res)
	assert_eq((g["nodes"] as Array).size(), 3, "one GraphNode per dialogue line")
	assert_eq((g["edges"] as Array).size(), 2, "two real line->line edges (END + out-of-range excluded)")
	res = null


func test_dialogue_flags_out_of_range_target() -> void:
	var res := _make_dialogue()
	var g: Dictionary = GraphData.build_dialogue(res)
	var problems: Array = g["problems"]
	assert_eq(problems.size(), 1, "exactly one dangling/out-of-range target flagged")
	assert_eq(String(problems[0]["node"]), "line2", "the problem points at the offending line")
	assert_true(String(problems[0]["message"]).contains("99"), "the message names the bad index")
	res = null


func test_dialogue_end_and_continue_are_not_edges() -> void:
	var res := DialogueResource.new()
	var l0 := DialogueLine.new()
	var cend := DialogueChoice.new()
	cend.target = DialogueLine.END
	var ccont := DialogueChoice.new()
	ccont.target = DialogueLine.CONTINUE
	l0.choices = [cend, ccont]
	res.lines = [l0]
	var g: Dictionary = GraphData.build_dialogue(res)
	assert_eq((g["nodes"] as Array).size(), 1, "single line")
	assert_eq((g["edges"] as Array).size(), 0, "END + CONTINUE render as pins, never edges")
	assert_eq((g["problems"] as Array).size(), 0, "sentinels are valid, not problems")
	res = null


func test_dialogue_null_resource_is_empty() -> void:
	var g: Dictionary = GraphData.build_dialogue(null)
	assert_eq((g["nodes"] as Array).size(), 0, "null resource -> empty graph, no crash")
	assert_eq((g["edges"] as Array).size(), 0, "no edges")


func test_dialogue_fail_branch_only_when_gated() -> void:
	var res := DialogueResource.new()
	var l0 := DialogueLine.new()
	var l1 := DialogueLine.new()
	var l2 := DialogueLine.new()
	# A GATED choice: target -> line1, target_on_fail -> line2. Both should chart.
	var c := DialogueChoice.new()
	c.required_stat = &"streetwise"
	c.required_value = 6
	c.target = 1
	c.target_on_fail = 2
	l0.choices = [c]
	res.lines = [l0, l1, l2]
	var g: Dictionary = GraphData.build_dialogue(res)
	assert_eq((g["edges"] as Array).size(), 2, "a gated choice charts BOTH target and target_on_fail")

	# An UNGATED choice: target_on_fail is ignored at runtime, so it must not produce an edge.
	var res2 := DialogueResource.new()
	var m0 := DialogueLine.new()
	var m1 := DialogueLine.new()
	var m2 := DialogueLine.new()
	var c2 := DialogueChoice.new()
	c2.target = 1
	c2.target_on_fail = 2  # but no gate set
	m0.choices = [c2]
	res2.lines = [m0, m1, m2]
	var g2: Dictionary = GraphData.build_dialogue(res2)
	assert_eq((g2["edges"] as Array).size(), 1, "ungated choice charts only its target, not the ignored fail branch")
	res = null
	res2 = null


# --- Quest builder ----------------------------------------------------------------------------------

## Build three quests: q_b has prereq q_a; q_a.next_quest = q_b; q_c has a prereq that names NO quest in the set.
## Expect 3 nodes, 2 edges (prereq a->b + next a->b), and 1 dangling-prereq problem on q_c.
func test_quest_node_edge_and_dangling_counts() -> void:
	var qa := Quest.new()
	qa.id = &"q_a"
	qa.title = "First"
	var qb := Quest.new()
	qb.id = &"q_b"
	qb.title = "Second"
	qb.prereq_quest_id = &"q_a"
	qa.next_quest = qb  # chains a->b
	var qc := Quest.new()
	qc.id = &"q_c"
	qc.title = "Orphan"
	qc.prereq_quest_id = &"does_not_exist"

	var g: Dictionary = GraphData.build_quests([qa, qb, qc])
	assert_eq((g["nodes"] as Array).size(), 3, "one GraphNode per quest")
	assert_eq((g["edges"] as Array).size(), 2, "prereq a->b + next a->b")
	var problems: Array = g["problems"]
	assert_eq(problems.size(), 1, "the unresolved prereq is flagged")
	assert_eq(String(problems[0]["node"]), "q_c", "problem points at the quest with the bad prereq")
	qa = null
	qb = null
	qc = null


func test_quest_empty_set() -> void:
	var g: Dictionary = GraphData.build_quests([])
	assert_eq((g["nodes"] as Array).size(), 0, "empty quest set -> empty graph")
	assert_eq((g["edges"] as Array).size(), 0, "no edges")


# --- Layout -----------------------------------------------------------------------------------------

func test_layout_assigns_columns_topologically() -> void:
	var qa := Quest.new()
	qa.id = &"a"
	var qb := Quest.new()
	qb.id = &"b"
	qb.prereq_quest_id = &"a"  # a -> b
	var g: Dictionary = GraphData.build_quests([qa, qb])
	var pos: Dictionary = GraphData.layout(g)
	assert_true(pos.has("a") and pos.has("b"), "every node gets a position")
	assert_lt((pos["a"] as Vector2).x, (pos["b"] as Vector2).x, "successor sits in a later column than its prereq")
	qa = null
	qb = null


# --- Typed picker filter (the VoiceData-offered-as-a-conversation bug) ------------------------------

## A fixture list with one non-dialogue resource beside a conversation and a quest: Dialogue mode must keep ONLY the
## DialogueResource, Quest mode ONLY the Quest (the loader's duck-typed id + objectives test). A null (failed load)
## is refused in both -- validity is tested before `is`, so a freed instance never reaches the type check.
func test_accepts_filters_by_mode_over_a_fixture_list() -> void:
	var conv := DialogueResource.new()
	var voice := VoiceData.new()
	var quest := Quest.new()
	quest.id = &"q"
	var fixtures: Array = [conv, voice, quest, null]

	var dialogue_kept := 0
	var quest_kept := 0
	for r in fixtures:
		if DialogueGraph.accepts(r, false):
			dialogue_kept += 1
		if DialogueGraph.accepts(r, true):
			quest_kept += 1
	assert_eq(dialogue_kept, 1, "Dialogue mode keeps exactly the one DialogueResource out of [conversation, voice, quest, null]")
	assert_eq(quest_kept, 1, "Quest mode keeps exactly the one Quest out of [conversation, voice, quest, null]")
	assert_false(DialogueGraph.accepts(voice, false), "a VoiceData is NOT offered as a conversation (the reported bug)")
	assert_false(DialogueGraph.accepts(voice, true), "a VoiceData is NOT offered as a quest either")
	assert_false(DialogueGraph.accepts(conv, true), "a conversation has no objectives, so it is not a quest")
	assert_false(DialogueGraph.accepts(quest, false), "a quest is not a conversation")
	conv = null
	voice = null
	quest = null


func test_label_for_names_quests_by_id_and_conversations_by_file() -> void:
	var quest := Quest.new()
	quest.id = &"recover_package"
	assert_eq(DialogueGraph.label_for(quest, "res://resources/quests/recover_the_package.tres", true), "recover_package  (recover_the_package.tres)", "quest rows read '<id>  (<file>)' -- the id is the key every other surface uses")
	var blank := Quest.new()
	assert_eq(DialogueGraph.label_for(blank, "res://resources/quests/x.tres", true), "(no id)  (x.tres)", "a blank quest id is said so, not hidden")
	var conv := DialogueResource.new()
	assert_eq(DialogueGraph.label_for(conv, "res://resources/dialogue/old_man.tres", false), "old_man.tres", "conversation rows read the file name")
	quest = null
	blank = null
	conv = null


## The real dialogue folder holds old_man_voice.tres (a VoiceData) beside the conversations. The typed scan must skip
## it and count it, so the tab's status can say why it isn't listed. Guarded: if the project no longer ships that
## file the case passes with a note rather than pinning content that moved.
func test_typed_paths_skips_the_voice_file_in_the_dialogue_folder() -> void:
	const VOICE_PATH := "res://resources/dialogue/old_man_voice.tres"
	if not ResourceLoader.exists(VOICE_PATH):
		pass_test("old_man_voice.tres is not in resources/dialogue any more -- nothing to filter here")
		return
	var scan: Dictionary = DialogueGraph.typed_paths(DialogueGraph._scan_resources(DialogueGraph.DIALOGUE_DIR), false)
	var kept: Array[String] = scan["paths"]
	var labels: PackedStringArray = scan["labels"]
	assert_false(kept.has(VOICE_PATH), "the VoiceData is not offered as a conversation")
	assert_gte(int(scan["skipped"]), 1, "the skipped count reports the filtered voice file")
	assert_eq(labels.size(), kept.size(), "labels stay parallel to the kept paths")
	for p in kept:
		assert_true(DialogueGraph.accepts(load(p), false), "every kept path loads as a conversation: %s" % p)


# --- Controls construct (the real compile check for addon-only scripts) + the designer contract ------

func test_dialogue_graph_panel_constructs() -> void:
	var panel = DialogueGraph.new()
	assert_not_null(panel, "the combined Graphs panel constructs via .new()")
	assert_eq(panel.name, "Graphs", "panel names itself for the bottom-panel tab (the panel sets the display title)")
	assert_eq(panel._show_btn.text, "Show Graph", "the draw command is 'Show Graph' (was 'Build')")
	assert_eq(panel._open_btn.text, "Open", "the handoff command is 'Open' (was 'Reveal')")
	assert_eq(panel._refresh_btn.text, "Refresh", "Refresh stays the explicit rescan fallback")
	assert_false(panel._graph.minimap_enabled, "the GraphEdit minimap is off -- it eats a corner of a short panel")
	assert_lte(panel._graph.custom_minimum_size.y, 120.0, "the graph area floor stays at or under 120 px")
	assert_eq(panel._status.max_lines_visible, 2, "the status clips at two lines so dangling targets can't grow the tab")
	assert_eq(panel._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the status wraps")
	assert_false(panel._picker.fit_to_longest_item, "the file picker never sizes the bar to its longest row")
	assert_true(panel._picker.clip_text, "the file picker clips a long label instead of widening")
	assert_false(panel._mode.fit_to_longest_item, "the mode picker never sizes the bar to its longest row")
	assert_true(panel._mode.clip_text, "the mode picker clips instead of widening")
	assert_eq(panel._status.text, DialogueGraph.MSG_IDLE_DIALOGUE, "the idle hint is the Dialogue next step")
	assert_eq(panel._status.tooltip_text, panel._status.text, "the status tooltip mirrors the text")
	assert_false(panel._revealed, "no folder scan at construction -- the first reveal does it")
	panel.free()


func test_quest_graph_panel_constructs() -> void:
	var panel = QuestGraph.new()
	assert_not_null(panel, "the quest-first variant constructs via .new()")
	assert_eq(panel._mode.selected, 1, "the quest-first variant boots in Quest mode")
	assert_eq(panel._status.text, DialogueGraph.MSG_IDLE_QUEST, "the idle hint is the Quest one (select() emits nothing, so it is pushed by hand)")
	assert_false(panel._revealed, "no eager scan -- the inherited latch populates on reveal")
	panel.free()


func test_status_mirrors_tooltip_and_tints_problems_by_override() -> void:
	var panel = DialogueGraph.new()
	panel._set_status("one problem here", true)
	assert_eq(panel._status.text, "one problem here", "status text written")
	assert_eq(panel._status.tooltip_text, "one problem here", "the tooltip mirrors the full text on every write")
	assert_true(panel._status.has_theme_color_override("font_color"), "a problem tints through a theme override, never bbcode")
	panel._set_status("all clear")
	assert_eq(panel._status.tooltip_text, "all clear", "the mirror follows every write")
	assert_false(panel._status.has_theme_color_override("font_color"), "a plain message drops the tint")
	panel.free()


## An empty scan result greys Show Graph and Open with the "create one in the New tab" tooltip and says so in the
## status -- fed through _apply_scan so no folder on disk is involved.
func test_empty_scan_disables_show_graph_and_open() -> void:
	var panel = DialogueGraph.new()
	var none: Array[String] = []
	panel._apply_scan(none, PackedStringArray(), 0, "")
	var want_tip := DialogueGraph.MSG_NONE_FOUND % "conversation"
	assert_true(panel._show_btn.disabled, "Show Graph is disabled when no conversation file exists")
	assert_eq(panel._show_btn.tooltip_text, want_tip, "the disabled Show Graph names what is missing")
	assert_true(panel._open_btn.disabled, "Open is disabled when no conversation file exists")
	assert_eq(panel._open_btn.tooltip_text, want_tip, "the disabled Open names what is missing")
	assert_true(panel._status.text.begins_with("No conversation files found"), "the status says the folder is empty: %s" % panel._status.text)
	panel.free()


## A rescan keeps the pick BY PATH (row order is irrelevant), enables the commands for a real pick, and reports the
## files it skipped. With nothing picked, Dialogue mode greys Show Graph with "Pick a conversation first."
func test_apply_scan_keeps_the_pick_by_path_and_counts_skipped() -> void:
	var panel = DialogueGraph.new()
	var paths: Array[String] = ["res://fixtures/a.tres", "res://fixtures/b.tres"]
	var labels := PackedStringArray(["a.tres", "b.tres"])
	panel._apply_scan(paths, labels, 1, "")
	assert_eq(panel._selected_path(), "", "nothing picked yet -> row 0 '(none)'")
	assert_true(panel._show_btn.disabled, "Dialogue mode needs a pick before Show Graph")
	assert_eq(panel._show_btn.tooltip_text, DialogueGraph.TIP_PICK_FIRST % "conversation", "the disabled Show Graph asks for a pick")
	assert_true(panel._open_btn.disabled, "Open needs a pick")
	assert_eq(panel._skipped_note(), " Skipped 1 file that isn't a conversation.", "the skipped count is worded for one file")
	assert_true(panel._status.text.ends_with(panel._skipped_note()), "the idle status carries the skipped note: %s" % panel._status.text)

	# Rescan with a new file inserted ABOVE the pick: the pick must follow the path, not the index.
	var more: Array[String] = ["res://fixtures/_first.tres", "res://fixtures/a.tres", "res://fixtures/b.tres"]
	var more_labels := PackedStringArray(["_first.tres", "a.tres", "b.tres"])
	panel._apply_scan(more, more_labels, 2, "res://fixtures/b.tres")
	assert_eq(panel._selected_path(), "res://fixtures/b.tres", "the pick survives a rescan by PATH")
	assert_eq(panel._picker.selected, 3, "row 0 is '(none)', so b sits at row 3 after the insert")
	assert_false(panel._show_btn.disabled, "a real pick enables Show Graph")
	assert_eq(panel._show_btn.tooltip_text, DialogueGraph.TIP_SHOW_DIALOGUE, "the enabled Show Graph says what it draws + Read-only")
	assert_false(panel._open_btn.disabled, "a real pick enables Open")
	assert_eq(panel._open_btn.tooltip_text, DialogueGraph.TIP_OPEN, "the enabled Open says where it goes + Read-only")
	assert_eq(panel._skipped_note(), " Skipped 2 files that aren't conversations.", "the skipped count is worded for several files")

	# A pick whose file vanished falls back to '(none)'.
	var fewer: Array[String] = ["res://fixtures/a.tres"]
	panel._apply_scan(fewer, PackedStringArray(["a.tres"]), 0, "res://fixtures/b.tres")
	assert_eq(panel._selected_path(), "", "a deleted pick falls back to '(none)' rather than a neighbour")
	assert_eq(panel._status.text, DialogueGraph.MSG_IDLE_DIALOGUE, "and the status returns to the idle hint")
	panel.free()


## Switching to Quest mode clears the drawing and resets the status to the Quest idle hint. Quest mode needs no pick
## for Show Graph (it draws the folder), while Open still asks for one. This scans the real quest folder headless.
func test_mode_switch_clears_the_graph_and_resets_the_status() -> void:
	var panel = DialogueGraph.new()
	var res := _make_dialogue()
	panel._render(GraphData.build_dialogue(res))
	assert_eq(_graph_node_count(panel), 3, "a rendered conversation puts one box per line in the GraphEdit")

	panel._mode.select(1)
	panel._on_mode_selected(1)
	assert_eq(_graph_node_count(panel), 0, "switching mode clears the GraphEdit")
	assert_true(panel._status.text.begins_with(DialogueGraph.MSG_IDLE_QUEST) or panel._status.text.begins_with("No quest files found"), "the status resets to the Quest idle hint (or the empty-folder hint): %s" % panel._status.text)
	assert_eq(panel._selected_path(), "", "the Dialogue pick does not carry over into Quest mode")
	if panel._paths.is_empty():
		pass_test("no quest files on disk -- the disabled-state wording is covered by the empty-scan case")
	else:
		assert_false(panel._show_btn.disabled, "Quest mode draws the whole folder, so Show Graph needs no pick")
		assert_eq(panel._show_btn.tooltip_text, DialogueGraph.TIP_SHOW_QUEST, "Quest Show Graph says it draws the folder")
		assert_true(panel._open_btn.disabled, "Open still needs a pick")
		assert_eq(panel._open_btn.tooltip_text, DialogueGraph.TIP_PICK_FIRST % "quest", "the disabled Open asks for a quest")
		for p in panel._paths:
			assert_true(DialogueGraph.accepts(load(p), true), "every listed quest passes the loader's duck-typed test: %s" % p)
	res = null
	panel.free()


## The done line names the box (by title) for every problem and counts lines / links / problems in designer words.
func test_done_text_names_problem_boxes_by_title() -> void:
	var res := _make_dialogue()
	var g: Dictionary = GraphData.build_dialogue(res)
	var msg: String = DialogueGraph._done_text("Showed old_man.tres", g, "line")
	assert_true(msg.begins_with("Showed old_man.tres -- 3 lines, 2 links, 1 problem: Line 2: "), "head, counts and the box title lead the line: %s" % msg)
	assert_true(msg.contains("99"), "the problem detail names the bad target")
	var clean: Dictionary = GraphData.build_quests([])
	assert_eq(DialogueGraph._done_text("Showed the quest chain in quests", clean, "quest"), "Showed the quest chain in quests -- 0 quests, 0 links.", "a clean graph ends after the counts")
	res = null


func _graph_node_count(panel) -> int:
	var n := 0
	for c in panel._graph.get_children():
		if c is GraphNode:
			n += 1
	return n
