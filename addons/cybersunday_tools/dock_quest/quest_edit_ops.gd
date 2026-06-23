@tool
extends RefCounted

## PURE static mutation ops on a Quest's objectives list — the testable core of the Quest Edit dock. Every op
## works on a live Quest resource IN MEMORY only: no EditorInterface, no ResourceSaver, no scene tree, no file
## I/O. The dock (quest_editor.gd) is thin glue that calls these, then ResourceSaver.saves the result; the GUT
## suite exercises THESE headless (an EditorInterface call would crash a headless test).
##
## All ops are bounds-guarded and return a bool: true = the list changed, false = a no-op (bad quest / index /
## direction). This lets the dock skip a needless save + re-render when nothing moved.
##
## Field/method names mirror scripts/quests/quest.gd (Quest.objectives: Array[QuestObjective]) and
## quest_objective.gd (QuestObjective.id/type/target_id/required_count/description) EXACTLY.

## A fresh QuestObjective seeded the same designer-friendly way content_scaffold.build_quest seeds one: a FLAG
## objective (no on-disk target registry needed), a stable unique id, required_count 1. Appends it to the quest's
## objectives and returns true. No-op (false) on a null quest.
static func add_objective(q: Quest) -> bool:
	if q == null:
		return false
	var o := QuestObjective.new()
	o.id = _next_objective_id(q)
	o.type = QuestObjective.Type.FLAG  # default-friendly: a story flag, nothing to wire up yet
	o.target_id = &""
	o.required_count = 1
	o.description = "TODO: describe this objective."
	q.objectives.append(o)
	return true


## Remove the objective at `index`. Returns true if removed, false (no-op) on a null quest or an out-of-range
## index. Bounds-guarded so a stale selection can't crash the dock.
static func remove_objective(q: Quest, index: int) -> bool:
	if q == null:
		return false
	if index < 0 or index >= q.objectives.size():
		return false
	q.objectives.remove_at(index)
	return true


## Move the objective at `index` by `dir` (-1 = up / earlier, +1 = down / later). Returns true if it moved, false
## (no-op) on a null quest, a bad index, a |dir| != 1, or a move that would fall off either end. Order matters:
## non-optional objectives gate completion in list order, so up/down is the designer's sequencing tool.
static func move_objective(q: Quest, index: int, dir: int) -> bool:
	if q == null:
		return false
	if dir != -1 and dir != 1:
		return false
	var n := q.objectives.size()
	if index < 0 or index >= n:
		return false
	var target := index + dir
	if target < 0 or target >= n:
		return false
	var o := q.objectives[index]
	q.objectives.remove_at(index)
	q.objectives.insert(target, o)
	return true


# --- helpers (pure) --------------------------------------------------------------------------------------------

## A stable id unique within the quest, of the form "obj_N" (matching content_scaffold's seeding). Scans the
## existing objective ids and picks the lowest N that's free, so re-adding after a remove never collides.
static func _next_objective_id(q: Quest) -> StringName:
	var used := {}
	for o in q.objectives:
		if o != null:
			used[String(o.id)] = true
	var i := 1
	while used.has("obj_%d" % i):
		i += 1
	return StringName("obj_%d" % i)
