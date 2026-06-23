@tool
extends RefCounted

## Pure graph BUILDER shared by the Dialogue + Quest viewers. NO editor APIs, NO scene-tree, NO rendering --
## it turns a DialogueResource or a set of Quests into a plain { nodes: Array, edges: Array, problems: Array }
## structure the @tool Controls then lay out with GraphEdit/GraphNode. Kept pure so the GUT test can feed it
## in-memory resources and assert node/edge counts + dangling-target detection with no EditorInterface.
##
## Shapes (plain Dictionaries so the test reads them without a class dep):
##   node    = { id: String, title: String, body: String, kind: String }   kind: "line" | "quest"
##   edge    = { from: String, to: String, label: String }                 (from/to are node ids)
##   problem = { node: String, message: String }                           (dangling / out-of-range target)
##
## Terminal sentinels (DialogueLine.END / CONTINUE) are NOT edges -- they're rendered as terminal pins by the
## view -- so they never appear in `edges`. Only real line->line jumps and quest prereq/next links are edges.

const END: int = -1  # mirrors DialogueLine.END (literal here to avoid a class_name dep at build time)
const CONTINUE: int = -2  # mirrors DialogueLine.CONTINUE


## Build the graph for a DialogueResource. One node per line ("line0", "line1", ...); one edge per choice
## whose target/target_on_fail is a real in-range line index. END/CONTINUE are skipped (terminal pins).
## An out-of-range target (>= line count, or < -2) is recorded in `problems` and produces NO edge.
static func build_dialogue(res: Resource) -> Dictionary:
	var nodes: Array = []
	var edges: Array = []
	var problems: Array = []
	if res == null:
		return {"nodes": nodes, "edges": edges, "problems": problems}
	var lines: Array = []
	var raw_lines: Variant = res.get("lines")
	if raw_lines is Array:
		lines = raw_lines
	var count: int = lines.size()
	for i in count:
		var line: Variant = lines[i]
		var id: String = "line%d" % i
		var body: String = ""
		var choices: Array = []
		if line != null:
			var raw_text: Variant = line.get("text")
			if raw_text != null:
				body = String(raw_text)
			var raw_choices: Variant = line.get("choices")
			if raw_choices is Array:
				choices = raw_choices
		nodes.append({
			"id": id,
			"title": "Line %d" % i,
			"body": body,
			"kind": "line",
		})
		# One edge per choice target (and target_on_fail when it's a real jump).
		for ci in choices.size():
			var choice: Variant = choices[ci]
			if choice == null:
				continue
			var ctext: String = ""
			var raw_ctext: Variant = choice.get("text")
			if raw_ctext != null:
				ctext = String(raw_ctext)
			var target: int = _as_int(choice.get("target"), CONTINUE)
			_add_target_edge(edges, problems, id, target, count, "[%d] %s" % [ci, ctext])
			var on_fail: int = _as_int(choice.get("target_on_fail"), END)
			# Only chart a fail-branch when this choice actually has a gate (else the field is ignored at runtime).
			if _choice_has_gate(choice) and on_fail >= 0:
				_add_target_edge(edges, problems, id, on_fail, count, "[%d] fail" % ci)
	return {"nodes": nodes, "edges": edges, "problems": problems}


## Resolve one choice target into an edge, a skipped sentinel, or a dangling-target problem.
static func _add_target_edge(edges: Array, problems: Array, from_id: String, target: int, line_count: int, label: String) -> void:
	if target == END or target == CONTINUE:
		return  # terminal sentinel -- rendered as a pin, never an edge
	if target < 0 or target >= line_count:
		problems.append({
			"node": from_id,
			"message": "%s -> out-of-range line index %d (lines: %d)" % [label, target, line_count],
		})
		return
	edges.append({"from": from_id, "to": "line%d" % target, "label": label})


## True when a choice carries any of the gate fields, so target_on_fail is meaningful. Mirrors the runtime
## gates on dialogue_choice.gd (stat / flag / faction / perk / item / quest).
static func _choice_has_gate(choice: Variant) -> bool:
	if choice == null:
		return false
	if String(choice.get("required_stat")) != "":
		return true
	if String(choice.get("required_flag")) != "":
		return true
	if String(choice.get("required_faction_id")) != "":
		return true
	if String(choice.get("required_perk_id")) != "":
		return true
	if String(choice.get("required_item_id")) != "":
		return true
	if String(choice.get("required_quest_id")) != "":
		return true
	return false


## Build the graph for a set of Quests (Array of Quest resources). One node per quest keyed by its `id` (or a
## synthesized "quest<N>" when the id is blank). Edges: a prereq_quest_id link (prereq -> this) and a next_quest
## link (this -> next). A prereq id that names no quest in the set is recorded as a dangling-target problem.
static func build_quests(quests: Array) -> Dictionary:
	var nodes: Array = []
	var edges: Array = []
	var problems: Array = []
	# First pass: stable node id per quest + an id->node-id map for prereq/next resolution.
	var by_id: Dictionary = {}        # quest StringName/String id -> node id
	var quest_node_id: Array = []     # parallel to `quests`: the node id we assigned each
	for i in quests.size():
		var q: Variant = quests[i]
		var qid: String = ""
		if q != null:
			qid = String(q.get("id"))
		var node_id: String = qid if qid != "" else "quest%d" % i
		quest_node_id.append(node_id)
		if qid != "":
			by_id[qid] = node_id
	for i in quests.size():
		var q: Variant = quests[i]
		var node_id: String = quest_node_id[i]
		var title: String = node_id
		var body: String = ""
		if q != null:
			var raw_title: Variant = q.get("title")
			if raw_title != null and String(raw_title) != "":
				title = String(raw_title)
			var raw_desc: Variant = q.get("description")
			if raw_desc != null:
				body = String(raw_desc)
		nodes.append({
			"id": node_id,
			"title": title,
			"body": body,
			"kind": "quest",
		})
	# Second pass: prereq + next edges, with dangling detection on prereq ids.
	for i in quests.size():
		var q: Variant = quests[i]
		if q == null:
			continue
		var node_id: String = quest_node_id[i]
		var prereq: String = String(q.get("prereq_quest_id"))
		if prereq != "":
			if by_id.has(prereq):
				edges.append({"from": String(by_id[prereq]), "to": node_id, "label": "prereq"})
			else:
				problems.append({
					"node": node_id,
					"message": "prereq_quest_id '%s' names no quest in this set" % prereq,
				})
		var nxt: Variant = q.get("next_quest")
		if nxt != null and nxt is Resource:
			var nxt_id: String = String(nxt.get("id"))
			if nxt_id != "" and by_id.has(nxt_id):
				edges.append({"from": node_id, "to": String(by_id[nxt_id]), "label": "next"})
			else:
				# The chained quest isn't in this set -- add it as a stub node so the link is visible.
				var stub_id: String = nxt_id if nxt_id != "" else "next%d" % i
				if not _has_node(nodes, stub_id):
					var stub_title: String = stub_id
					var raw_nt: Variant = nxt.get("title")
					if raw_nt != null and String(raw_nt) != "":
						stub_title = String(raw_nt)
					nodes.append({"id": stub_id, "title": stub_title, "body": "(not in set)", "kind": "quest"})
				edges.append({"from": node_id, "to": stub_id, "label": "next"})
	return {"nodes": nodes, "edges": edges, "problems": problems}


static func _has_node(nodes: Array, id: String) -> bool:
	for n in nodes:
		if String(n.get("id")) == id:
			return true
	return false


## Layered (topological-ish) auto-layout: assign each node a column = longest incoming-edge depth, and stack
## nodes within a column by row. Returns id -> Vector2 grid coords (column, row); the view scales to pixels.
## Robust to cycles (a visited guard caps depth) and to nodes with no edges (they land in column 0).
static func layout(graph: Dictionary) -> Dictionary:
	var nodes: Array = graph.get("nodes", [])
	var edges: Array = graph.get("edges", [])
	var depth: Dictionary = {}  # node id -> column
	for n in nodes:
		depth[String(n.get("id"))] = 0
	# Relax depths: a node sits one column right of its deepest predecessor. Iterate up to node-count times
	# (longest simple path bound); a cycle simply stops improving and we break early.
	var changed: bool = true
	var passes: int = 0
	while changed and passes <= nodes.size():
		changed = false
		passes += 1
		for e in edges:
			var f: String = String(e.get("from"))
			var t: String = String(e.get("to"))
			if not depth.has(f) or not depth.has(t):
				continue
			var want: int = int(depth[f]) + 1
			if want > int(depth[t]):
				depth[t] = want
				changed = true
	# Stack within each column.
	var row_in_col: Dictionary = {}  # column -> next free row
	var pos: Dictionary = {}
	for n in nodes:
		var id: String = String(n.get("id"))
		var col: int = int(depth.get(id, 0))
		var row: int = int(row_in_col.get(col, 0))
		row_in_col[col] = row + 1
		pos[id] = Vector2(col, row)
	return pos


static func _as_int(v: Variant, fallback: int) -> int:
	if v == null:
		return fallback
	if v is int or v is float:
		return int(v)
	return fallback
