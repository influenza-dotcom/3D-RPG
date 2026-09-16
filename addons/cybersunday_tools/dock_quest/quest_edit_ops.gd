@tool
extends RefCounted

## PURE static mutation ops on a Quest's STAGES, its OBJECTIVES (the quest's own, or one stage's), its item REWARDS
## list, and its drift-prone id fields —
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
## Field/method names mirror scripts/quests/quest.gd (Quest.objectives: Array[QuestObjective], Quest.stages:
## Array[QuestStage], Quest.rewards: Array[ItemStack], Quest.prereq_quest_id, Quest.expire_on_flag), quest_stage.gd
## (QuestStage.id/journal_text/objectives/next_stage_id/set_flag_on_enter), quest_objective.gd
## (QuestObjective.id/type/target_id/required_count/description) and scripts/items/item_stack.gd (ItemStack.item:
## Item, ItemStack.count: int) EXACTLY.
##
## WHERE OBJECTIVES LIVE: a stage-less quest's objectives are Quest.objectives; a staged quest's are each
## QuestStage.objectives (the Quest's own list is ignored at runtime). Every objective op therefore takes an OPTIONAL
## `stage` -- null means the quest's own list, exactly the pre-stages call shape -- and the dock passes the stage the
## designer picked.

# --- objectives ------------------------------------------------------------------------------------------------

## A fresh QuestObjective seeded the same designer-friendly way content_scaffold.build_quest seeds one: a FLAG
## objective (no on-disk target registry needed), a stable id unique across the WHOLE quest (its own list and every
## stage's, so a trigger's advance_objective_id can never be ambiguous), required_count 1. Appends it to `stage`'s
## objectives when a stage is given, else to the quest's own, and returns true. No-op (false) on a null quest.
static func add_objective(q: Quest, stage: QuestStage = null) -> bool:
	if q == null:
		return false
	var o := QuestObjective.new()
	o.id = _next_objective_id(q)
	o.type = QuestObjective.Type.FLAG  # default-friendly: a story flag, nothing to wire up yet
	o.target_id = &""
	o.required_count = 1
	o.description = "TODO: describe this objective."
	_objective_list(q, stage).append(o)
	return true


## Remove the objective at `index`. Returns true if removed, false (no-op) on a null quest or an out-of-range
## index. Bounds-guarded so a stale selection can't crash the dock.
static func remove_objective(q: Quest, index: int, stage: QuestStage = null) -> bool:
	if q == null:
		return false
	var list := _objective_list(q, stage)
	if index < 0 or index >= list.size():
		return false
	list.remove_at(index)
	return true


## Move the objective at `index` by `dir` (-1 = up / earlier, +1 = down / later). Returns true if it moved, false
## (no-op) on a null quest, a bad index, a |dir| != 1, or a move that would fall off either end. Order matters:
## non-optional objectives gate completion in list order, so up/down is the designer's sequencing tool.
static func move_objective(q: Quest, index: int, dir: int, stage: QuestStage = null) -> bool:
	if q == null:
		return false
	if dir != -1 and dir != 1:
		return false
	var list := _objective_list(q, stage)
	var n := list.size()
	if index < 0 or index >= n:
		return false
	var target := index + dir
	if target < 0 or target >= n:
		return false
	var o := list[index]
	list.remove_at(index)
	list.insert(target, o)
	return true


# --- stages (Quest.stages: Array[QuestStage]) -------------------------------------------------------------------------
# Same bool convention as the lists above. Two ops carry a deliberate data MOVE, and both exist so that turning stages
# on or off never loses an objective or changes how the quest plays:
#   * add_stage on a quest with NO stages yet moves the quest's own objectives into that first stage -- a one-stage,
#     terminal quest with the same objectives plays exactly like the stage-less quest it was (and a save made before
#     resumes in stages[0] with its progress keys intact);
#   * remove_stage of the LAST stage moves its objectives back onto the quest (when the quest's own list is empty),
#     the exact inverse.
# Neither op rewrites a next_stage_id or a conversation's set_quest_stage_id that named a removed stage: no silent
# edits -- the Audit reports every dangling one. rename_stage_id is the op that DOES carry references, because a
# rename is a request to keep them.

## Append a fresh stage with a unique "stage_N" id (terminal: no next stage) and return true. The FIRST stage added to a
## quest takes the quest's own objectives with it (see above). No-op (false) on a null quest.
static func add_stage(q: Quest) -> bool:
	if q == null:
		return false
	var st := QuestStage.new()
	st.id = _next_stage_id(q)
	if q.stages.is_empty() and not q.objectives.is_empty():
		st.objectives.append_array(q.objectives)
		q.objectives.clear()
	q.stages.append(st)
	return true


## Remove the stage at `index`. Returns true if removed, false on a null quest / out-of-range index. Removing the ONLY
## stage hands its objectives back to the quest's own list when that list is empty (the quest becomes stage-less and
## plays as one implicit stage again).
static func remove_stage(q: Quest, index: int) -> bool:
	if q == null or index < 0 or index >= q.stages.size():
		return false
	var st := q.stages[index]
	q.stages.remove_at(index)
	if q.stages.is_empty() and st != null and q.objectives.is_empty():
		q.objectives.append_array(st.objectives)
	return true


## Move the stage at `index` by `dir` (-1 / +1). Order means ONE thing: the quest STARTS in stages[0]. After that it
## moves by next_stage_id / a jump, never by position. False on null / bad index / bad step / off either end.
static func move_stage(q: Quest, index: int, dir: int) -> bool:
	if q == null or (dir != -1 and dir != 1):
		return false
	var n := q.stages.size()
	if index < 0 or index >= n or index + dir < 0 or index + dir >= n:
		return false
	var st := q.stages[index]
	q.stages.remove_at(index)
	q.stages.insert(index + dir, st)
	return true


## Why `owner` may NOT take the stage id `id` (whitespace already stripped by the caller): "" when it may, else the
## refusal in designer words. Never blank (the save could not remember it), never another stage's (the first match
## would silently win).
static func stage_id_refusal(q: Quest, owner: QuestStage, id: StringName) -> String:
	if id == &"":
		return "a stage id can't be blank -- the save remembers stages by id, and nothing could move the quest to it."
	if q != null:
		for i in q.stages.size():
			var st := q.stages[i]
			if st != null and st != owner and st.id == id:
				return "'%s' is already stage %d's id -- stage ids must be unique within a quest." % [id, i + 1]
	return ""


## Rename `stage` to `new_id` (whitespace stripped) in ONE shot and carry every next_stage_id in the quest that named
## the old id. Returns {ok, reason, rewritten}. A refusal leaves the quest untouched; renaming to the same id is an ok
## no-op. References OUTSIDE the quest (a conversation's set_quest_stage_id) cannot be seen from here -- the Audit
## reports them -- and a saved game sitting in the old id resumes this quest at its first stage on its next load.
static func rename_stage_id(q: Quest, stage: QuestStage, new_id: StringName) -> Dictionary:
	var out := {"ok": false, "reason": "", "rewritten": 0}
	if q == null or stage == null:
		out["reason"] = "nothing is picked."
		return out
	var wanted := StringName(String(new_id).strip_edges())
	var why := stage_id_refusal(q, stage, wanted)
	if why != "":
		out["reason"] = why
		return out
	var old := stage.id
	stage.id = wanted
	if old != wanted and old != &"":
		for st in q.stages:
			if st != null and st.next_stage_id == old:
				st.next_stage_id = wanted
				out["rewritten"] += 1
	out["ok"] = true
	return out


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
	for st in q.stages:
		if st == null:
			continue
		# Stage ids are matched EXACTLY by the save, next_stage_id and set_quest_stage_id; the flag by GameState.
		if _drifted(st.id):
			st.id = _trim(st.id)
			changed += 1
		if _drifted(st.next_stage_id):
			st.next_stage_id = _trim(st.next_stage_id)
			changed += 1
		if _drifted(st.set_flag_on_enter):
			st.set_flag_on_enter = _trim(st.set_flag_on_enter)
			changed += 1
	for o in _every_objective(q):
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

## The list an objective op edits: `stage`'s objectives when a stage is given, else the quest's own. A typed Array is
## a reference, so mutating the returned list mutates the resource.
static func _objective_list(q: Quest, stage: QuestStage) -> Array[QuestObjective]:
	return stage.objectives if stage != null else q.objectives


## Every objective row the quest carries anywhere: its own list, then each stage's (even the own list of a staged
## quest, which runtime ignores -- normalize and id uniqueness still cover it).
static func _every_objective(q: Quest) -> Array[QuestObjective]:
	var out: Array[QuestObjective] = []
	out.append_array(q.objectives)
	for st in q.stages:
		if st != null:
			out.append_array(st.objectives)
	return out


## A stage id unique within the quest, "stage_N" with the lowest free N.
static func _next_stage_id(q: Quest) -> StringName:
	var used := {}
	for st in q.stages:
		if st != null:
			used[String(st.id)] = true
	var i := 1
	while used.has("stage_%d" % i):
		i += 1
	return StringName("stage_%d" % i)


## A stable id unique within the WHOLE quest (its own objectives and every stage's), of the form "obj_N" (matching
## content_scaffold's seeding). Picks the lowest N that's free, so re-adding after a remove never collides.
static func _next_objective_id(q: Quest) -> StringName:
	var used := {}
	for o in _every_objective(q):
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
