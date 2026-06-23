extends GutTest

## PURE tests for the dev-tools graph viewers (BUILD plugin item 5: Dialogue + Quest graph panels).
## graph_data.gd is a pure builder (no EditorInterface / no scene tree), so we feed it in-memory
## DialogueResource + Quest resources and assert node/edge counts + dangling-target detection. We also
## assert the two @tool Controls CONSTRUCT via .new() -- the GUT run is the real compile check for
## addon-only scripts (--import does not deep-compile them).

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
	assert_string_contains(String(problems[0]["message"]), "99", "the message names the bad index")
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
	c.required_stat = &"persuasion"
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


# --- Controls construct (the real compile check for addon-only scripts) -----------------------------

func test_dialogue_graph_panel_constructs() -> void:
	var panel = DialogueGraph.new()
	assert_not_null(panel, "the combined Graphs panel constructs via .new()")
	assert_eq(panel.name, "Graphs", "panel names itself for the bottom-panel tab")
	panel.free()


func test_quest_graph_panel_constructs() -> void:
	var panel = QuestGraph.new()
	assert_not_null(panel, "the quest-first variant constructs via .new()")
	panel.free()
