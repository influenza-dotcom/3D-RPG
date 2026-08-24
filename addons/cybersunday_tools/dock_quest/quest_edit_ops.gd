@tool
extends RefCounted

## PURE static mutation ops on a Quest's OBJECTIVES list, its item REWARDS list, and its drift-prone id fields —
## the testable core of the Quest Edit dock. Every op works on a live Quest resource IN MEMORY only: no
## EditorInterface, no ResourceSaver, no scene tree, no file I/O. The dock (quest_editor.gd) is thin glue that
## calls these, then persists the result through ContentSaveGuard.save_with_backup; the GUT suite exercises THESE
## headless (an EditorInterface call would crash a headless test).
##
## Every LIST op is bounds-guarded and returns a bool: true = the list changed, false = a no-op (bad quest / index
## / direction). The dock re-renders ONLY on true, and that is load-bearing rather than tidy: a re-render calls
## ItemList.clear(), which drops the selection, and the glue then re-selects `index + dir` — an index that doesn't
## exist when the move was refused. Re-rendering a no-op would therefore blank the row editor out from under the
## designer. (No op here ever saves anything — Save is its own button.) `normalize` is the one deliberate exception
## to the bool convention: it returns the NUMBER of fields it repaired, because the dock reports that count on its
## status line ("silently fixed 2 fields" is information a designer needs).
##
## Field/method names mirror scripts/quests/quest.gd (Quest.objectives: Array[QuestObjective], Quest.rewards:
## Array[ItemStack], Quest.prereq_quest_id, Quest.expire_on_flag), quest_objective.gd
## (QuestObjective.id/type/target_id/required_count/description) and scripts/items/item_stack.gd (ItemStack.item:
## Item, ItemStack.count: int) EXACTLY.

# --- objectives ------------------------------------------------------------------------------------------------

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


# --- rewards (Quest.rewards: Array[ItemStack], granted by QuestTracker on completion) ----------------------------
# Same shape as the objective ops above ON PURPOSE — bounds-guarded, bool-returning, one convention for the whole
# dock. (loot_edit_ops.add_entry returns an int index instead; that's the Loot tab's convention, not this one. The
# glue selects the new row with `q.rewards.size() - 1`, exactly as quest_editor._on_add already does.)

## Append a fresh ItemStack row (no item yet, count 1) to the quest's completion rewards and return true. No-op
## (false) on a null quest. The seeds are written out rather than left to ItemStack's own defaults so a default
## change over in item_stack.gd can never silently re-shape a row this dock creates.
##
## `count = 1` (not 0) because item_stack.gd:13 documents 0 as "skip the row" — a new row a designer just asked
## for must actually hand something over the moment they pick an item. `item = null` is the honest empty state:
## ItemStack.seed_into skips null-item rows, so an un-picked row grants nothing instead of erroring.
##
## `ItemStack` carries no @tool header and that is fine + precedented: loot_edit_ops.add_entry does LootEntry.new()
## from this same @tool context and loot_entry.gd is equally non-@tool. @tool governs whether a script's OWN code
## runs in the editor, not whether an editor script may instantiate the class.
static func add_reward(q: Quest) -> bool:
	if q == null:
		return false
	var s := ItemStack.new()
	s.item = null
	s.count = 1
	q.rewards.append(s)
	return true


## Remove the reward row at `index`. Returns true if removed, false (no-op) on a null quest or an out-of-range
## index. Bounds-guarded like remove_objective, for the same reason: a stale ItemList selection must never crash
## the dock (the row list is rebuilt on every load, so an index can outlive the row it named).
static func remove_reward(q: Quest, index: int) -> bool:
	if q == null:
		return false
	if index < 0 or index >= q.rewards.size():
		return false
	q.rewards.remove_at(index)
	return true


## Move the reward row at `index` by `dir` (-1 = up, +1 = down). Returns true if it moved, false (no-op) on a null
## quest, a bad index, a |dir| != 1, or a move off either end.
##
## Reward order matters far less than objective order — ItemStack.seed_into walks the array and seeds every row, so
## into a bag with room the player receives the same items whichever way round they sit. It is NOT purely cosmetic
## though, and the difference is worth knowing before tidying a list: seed_into STOPS at the first row that won't
## fit a spatially-capped (Tetris grid) bag and skips the rest, and QuestTracker._grant_quest_rewards only toasts
## the shortfall — the missed items are not refunded or retried. Against a nearly-full bag the EARLIER rows are the
## ones that land, so put the reward the designer most wants delivered first.
static func move_reward(q: Quest, index: int, dir: int) -> bool:
	if q == null:
		return false
	if dir != -1 and dir != 1:
		return false
	var n := q.rewards.size()
	if index < 0 or index >= n:
		return false
	var target := index + dir
	if target < 0 or target >= n:
		return false
	var s := q.rewards[index]
	q.rewards.remove_at(index)
	q.rewards.insert(target, s)
	return true


# --- normalize -------------------------------------------------------------------------------------------------

## Repair the quest's silently-fatal authoring drift IN PLACE and return HOW MANY fields changed (0 = already
## clean, so a caller can stay quiet). No-op returning 0 on a null quest. Idempotent by construction: every branch
## only fires when the value differs from its repaired form, so a second call on the same quest returns 0.
##
## The dock calls this on Save, but it is NOT merely a mirror of the dock's own input handlers — a .tres authored
## in the raw inspector, hand-edited in a text editor, or produced by an older tool reaches this the same way, and
## THAT is the case worth catching. Every field below is compared by EXACT StringName equality at runtime, so a
## single stray space makes the quest look perfectly authored and do nothing at all:
##
##   * `objective.target_id` — QuestTracker._advance_objectives_matching compares `obj.target_id == target` (and
##     the legacy display-name fallback the same way), and EVERY notify_* hook routes through it: kill, talk,
##     pickup, use-item, enter-area and flag alike. A padded id matches no event of any type, so the objective
##     sits at 0/N forever with no error anywhere.
##   * `objective.id` — the key a DESIGNER hand-types SOMEWHERE ELSE to advance this step: TriggerVolume,
##     DialogueChoice and Readable each export an `advance_objective_id` that reaches
##     QuestTracker.advance_objective, which resolves it through _quest_objective's exact `obj.id == objective_id`
##     compare. Pad the id on the objective and that lookup returns null — the trigger fires and the step never
##     moves. The quest's INTERNAL hooks stay self-consistent (start_quest seeds the progress Dictionary from the
##     same padded id, and _advance_objectives_matching hands obj.id straight back), which is exactly why the drift
##     stays invisible until someone wires a trigger against the id they see. Residual risk, accepted: trimming can
##     collide two ids that differed only by their padding, and _quest_objective then answers both with the first.
##     A duplicate id is its own authoring bug — visible in the dock's objective list, and NOT something normalize
##     may paper over by renaming a key other resources point at.
##   * `prereq_quest_id` — start_quest refuses (silently, by design) unless is_quest_completed(prereq) is true; a
##     padded id can never match a completed quest's id, so the quest becomes permanently unstartable.
##   * `expire_on_flag` — WR-6 fails the quest on `q.expire_on_flag == flag`. Padded, the fail window never fires
##     and the "you missed it" branch is dead content.
##   * `objective.required_count` — floored to 1. quest_objective.gd exports it as @export_range(1, 9999), but the
##     range is an INSPECTOR hint, not a stored-value guarantee: a hand-typed 0 loads fine and makes
##     _all_required_done read `0 >= 0` — the objective is "done" before the player does anything, and a quest of
##     nothing-but-zeroes completes on its first advance. The upper bound is deliberately NOT clamped: an absurdly
##     large count is visible in the journal as "3/9999999" and merely unfinishable, not silent.
##
## Deliberately NOT touched: `Quest.id` (this dock never exposes it, and Phase 2's reviewed scope is the four id
## fields above — repairing a primary key the designer can't see here would be a surprise edit); `title` /
## `description` / `objective.description` (player-facing prose where trailing whitespace is harmless, and
## strip_edges on a multiline description would eat intentional blank lines); `ItemStack.count` (0 is a legitimate
## authored "skip this row", per item_stack.gd:13).
static func normalize(q: Quest) -> int:
	if q == null:
		return 0
	var changed := 0
	if _drifted(q.prereq_quest_id):
		q.prereq_quest_id = _trim(q.prereq_quest_id)
		changed += 1
	if _drifted(q.expire_on_flag):
		q.expire_on_flag = _trim(q.expire_on_flag)
		changed += 1
	for o in q.objectives:
		if o == null:
			continue  # a null row is a separate authoring problem the dock renders as "<null>"; skip, don't crash
		if _drifted(o.id):
			o.id = _trim(o.id)
			changed += 1
		if _drifted(o.target_id):
			o.target_id = _trim(o.target_id)
			changed += 1
		if o.required_count < 1:
			o.required_count = 1
			changed += 1
	return changed


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


## True when `v` carries leading/trailing whitespace — i.e. normalize would change it. Both sides of the compare
## are real Strings (String() first, THEN strip_edges), so the test never leans on which of String's methods
## StringName happens to mirror in a given engine version.
static func _drifted(v: StringName) -> bool:
	var s := String(v)
	return s != s.strip_edges()


## `v` with its edges stripped, back as a StringName — the type every one of these fields is declared as. The
## String -> StringName conversion lives HERE, right next to _drifted, so the "is it clean?" test and the "make it
## clean" write can never disagree about what clean means.
static func _trim(v: StringName) -> StringName:
	return StringName(String(v).strip_edges())
